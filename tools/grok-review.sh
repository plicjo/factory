#!/usr/bin/env bash
# Single chokepoint for the opt-in Grok review seat. Refuses to run unless
# FACTORY_GROK_SEAT=1 so environments that must not send code to non-Anthropic
# vendors never reach the CLI.
# Grok runs with no tools. Every allowlist of read-only shell commands still let some command through
# that grok refused, which cancelled the session, so the script builds the whole review context itself
# and Grok reads only the prompt.
# Usage: grok-review.sh BRIEF DIR BASE HEAD. The prompt carries the brief, then git log BASE..HEAD,
# git diff BASE HEAD and the full text at HEAD of each changed file, cut to FACTORY_GROK_MAX_BYTES
# (default 400000) by leaving out the largest files first. The prompt names what was cut.
# Exit codes: 2 seat not enabled, 3 grok CLI or jq missing, 4 brief, DIR or a commit unreadable,
# 5 session did not finish or Grok still called a tool after one resume, 6 the run passed
# FACTORY_GROK_TIMEOUT seconds (default 540), counted across the resume, 7 the reply has no VERDICT line.
set -euo pipefail

brief="${1:-}"
dir="${2:-}"
base="${3:-}"
head="${4:-}"

if [[ "${FACTORY_GROK_SEAT:-}" != "1" ]]; then
  echo "grok-review: seat disabled, set FACTORY_GROK_SEAT=1 to enable" >&2
  exit 2
fi

for tool in grok jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "grok-review: $tool not found on PATH" >&2
    exit 3
  fi
done

if [[ -z "$brief" || ! -r "$brief" || ! -f "$brief" ]]; then
  echo "grok-review: brief file missing or unreadable: ${brief:-<none>}" >&2
  exit 4
fi

if [[ -z "$dir" || ! -d "$dir" ]]; then
  echo "grok-review: review directory missing: ${dir:-<none>}" >&2
  exit 4
fi

for ref in "$base" "$head"; do
  if [[ -z "$ref" ]] || ! git -C "$dir" rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then
    echo "grok-review: not a commit in $dir: ${ref:-<none>} (usage: grok-review.sh BRIEF DIR BASE HEAD)" >&2
    exit 4
  fi
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# grok has no wall-clock limit, and a hung session once held a panel for 25 minutes, so a watchdog
# ends it at a deadline counted from here. The transport's Bash timeout is 600 seconds.
deadline=$(( $(date +%s) + ${FACTORY_GROK_TIMEOUT:-540} ))

cap=${FACTORY_GROK_MAX_BYTES:-400000}
git -C "$dir" log --oneline "$base..$head" >"$work/log"
git -C "$dir" diff --no-color --no-ext-diff "$base" "$head" >"$work/diff"

{
  echo "You have no tools in this session. You cannot run commands, read files, search, load skills or spawn subagents. Do not try."
  echo "Everything you may review is in this prompt: the brief, then the commits, the diff and the full text at $head of the files changed in $base..$head of the repository at $dir."
  echo "Review only that material. Where it cannot settle a point, say what you would need to see instead of guessing."
  echo "Print the findings as your final reply. End it with one plain line that starts with VERDICT: and gives your verdict in the brief's terms, for example VERDICT: ship with fixes."
  echo
  echo "===== BRIEF ====="
  cat "$brief"
  echo
  echo "===== COMMITS $base..$head ====="
  cat "$work/log"
} >"$work/head"

omitted=()
binary=()
: >"$work/sizes"
while IFS= read -r -d '' rec; do
  path=${rec#*$'\t'*$'\t'}
  if [[ "$rec" == -$'\t'-$'\t'* ]]; then binary+=("$path"); continue; fi
  size=$(git -C "$dir" cat-file -s "$head:$path" 2>/dev/null) || { binary+=("$path"); continue; }
  printf '%s\t%s\0' "$size" "$path" >>"$work/sizes"
done < <(git -C "$dir" diff -z --numstat --no-renames --diff-filter=d "$base" "$head")

# The 1024 bytes leave room for the left-out list and the closing lines.
fixed=$(( $(wc -c <"$work/head") + 1024 ))
diff_size=$(( $(wc -c <"$work/diff") ))
diff_keep=$diff_size
if (( fixed + diff_size > cap )); then diff_keep=$(( cap > fixed ? cap - fixed : 0 )); fi
budget=$(( cap - fixed - diff_keep ))

# Leaving out the largest files first is the same as keeping the smallest files while they fit.
included=()
while IFS= read -r -d '' rec; do
  size=${rec%%$'\t'*}
  path=${rec#*$'\t'}
  cost=$(( size + 2 * ${#path} + ${#head} + 64 ))
  if (( cost <= budget )); then
    included+=("$path")
    budget=$(( budget - cost ))
  else
    omitted+=("$path ($size bytes)")
  fi
done < <(sort -z -n "$work/sizes")

{
  cat "$work/head"
  echo
  echo "===== DIFF $base $head ====="
  (( diff_keep == 0 )) || head -c "$diff_keep" "$work/diff"
  if (( diff_keep < diff_size )); then
    echo
    echo "[diff cut for size after $diff_keep of $diff_size bytes]"
  fi
  for path in ${included[@]+"${included[@]}"}; do
    echo
    echo "===== FILE $path AT $head ====="
    git -C "$dir" show "$head:$path"
    echo "===== END FILE $path ====="
  done
  if (( ${#omitted[@]} + ${#binary[@]} > 0 )); then
    echo
    echo "===== LEFT OUT ====="
    for line in ${omitted[@]+"${omitted[@]}"}; do echo "Full text left out to fit the $cap-byte prompt limit, which drops the largest files first: $line"; done
    for line in ${binary[@]+"${binary[@]}"}; do echo "Binary file or submodule, not shown: $line"; done
  fi
  echo
  echo "===== END OF MATERIAL ====="
  echo "Review the material above as the brief asks, with no tools, and end with the VERDICT: line."
} >"$work/prompt"

# --tools "" is ignored, so the allowlist names one tool and the deny list removes it along with
# search_tool and use_tool, which grok adds to any allowlist. That leaves Grok no tool at all.
# Without --verbatim grok replaces the middle of a long prompt with a note to read the rest with
# tools, which a session with no tools cannot do.
grok_flags=(
  -m "${FACTORY_GROK_MODEL:-grok-4.7}"
  --output-format streaming-json
  --verbatim
  --tools todo_write
  --disallowed-tools todo_write,search_tool,use_tool
  --max-turns "${FACTORY_GROK_MAX_TURNS:-4}"
  --permission-mode dontAsk
  --reasoning-effort "${FACTORY_GROK_EFFORT:-low}"
  --cwd "$dir"
)

# The watchdog's sleep is killed first so a finished run leaves no marker.
run_grok() {
  local left=$(( deadline - $(date +%s) )) rc=0 pid watchdog
  if (( left <= 0 )); then touch "$work/timed_out"; return 1; fi
  grok "${grok_flags[@]}" "$@" >"$work/stream" &
  pid=$!
  ( sleep "$left" && touch "$work/timed_out" && kill "$pid" ) 2>/dev/null &
  watchdog=$!
  wait "$pid" || rc=$?
  pkill -P "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  return "$rc"
}

stop_reason() { jq -r 'select(.type == "end") | .stopReason' "$work/stream" | tail -n1; }
session_id() { jq -r 'select(.type == "end") | .sessionId // empty' "$work/stream" | tail -n1; }
tool_calls() { jq -r 'select(.type == "tool_call") | .toolName // "unnamed"' "$work/stream" | sort -u | paste -sd ' ' -; }

status=0
run_grok --prompt-file "$work/prompt" || status=$?
reason=$(stop_reason)
calls=$(tool_calls)
resumed=0

session=$(session_id)
if [[ "$status" -eq 0 && -n "$calls" && -n "$session" ]]; then
  resumed=1
  echo "grok-review: resume after a tool call: $calls" >&2
  echo "You called $calls, but this session has no tools and none will run. Review only the material in the first prompt, print your findings, and end with the VERDICT: line." >"$work/retry"
  run_grok --resume "$session" --prompt-file "$work/retry" || status=$?
  reason=$(stop_reason)
  calls=$(tool_calls)
fi

if [[ -e "$work/timed_out" ]]; then
  echo "grok-review: no verdict within ${FACTORY_GROK_TIMEOUT:-540}s ($resumed resumes)" >&2
  exit 6
fi

if [[ "$status" -ne 0 || "$reason" != "end_turn" || -n "$calls" ]]; then
  echo "grok-review: session did not finish (grok exit $status, stopReason ${reason:-none}, tool calls ${calls:-none}, $resumed resumes)" >&2
  exit 5
fi

reply=$(jq -rj 'select(.type == "text") | .data' "$work/stream")
if ! grep -Eq '^[*_]*VERDICT:' <<<"$reply"; then
  echo "grok-review: the reply has no VERDICT line; it ended: $(tail -c 300 <<<"$reply")" >&2
  exit 7
fi
printf '%s\n' "$reply"
