#!/usr/bin/env bash
# Single chokepoint for the opt-in Grok review seat. Refuses to run unless
# FACTORY_GROK_SEAT=1 so environments that must not send code to non-Anthropic
# vendors never reach the CLI, and pins the read-only flags in one place.
# grok exits 0 even when a refused tool call cancels the session, so the script reads the
# stream's final `end` event and fails unless its stopReason is `end_turn`.
# Usage: grok-review.sh BRIEF [DIR]. Grok starts in DIR (default: the current directory), so it reads that repository's git history without git -C.
# Exit codes: 2 seat not enabled, 3 grok CLI or jq missing, 4 brief or DIR unreadable,
# 5 session did not finish, from a refused command that survived every resume or the turn cap (the reason and the last failed tool call go to stderr),
# 6 the run passed FACTORY_GROK_TIMEOUT seconds (default 600), counted across resumes.
set -euo pipefail

brief="${1:-}"
dir="${2:-$PWD}"

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

if [[ ! -d "$dir" ]]; then
  echo "grok-review: review directory missing: $dir" >&2
  exit 4
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

read_only=(
  'git log *' 'git diff *' 'git show *' 'git status *' 'git rev-parse *' 'git fetch *' 'git blame *'
  'git ls-files *' 'git ls-tree *' 'git cat-file *' 'git merge-base *' 'git grep *' 'git rev-list *'
  'git diff-tree *' 'git show-ref *' 'git describe *' 'git shortlog *' 'gh pr view *' 'gh pr diff *'
  'echo *' 'rg *' 'grep *' 'ls *' 'cat *' 'head *' 'tail *' 'wc *' 'nl *' 'cut *'
  'diff *' 'jq *' 'find *' 'sed -n *'
)
# grok approves a chain only when every stage matches an allow rule, and its built-in read-only list does
# not count toward that. `git status *` does not match a bare `git status`, so a chain such as
# `git fetch && git status` is cancelled. These commands run usefully with no argument, so each also gets a bare rule.
bare=(
  'git log' 'git diff' 'git show' 'git status' 'git fetch' 'git ls-files' 'git show-ref' 'git describe'
  'gh pr view' 'gh pr diff' 'ls'
)
# sort and uniq have no rule: an allow rule would admit sort -o and uniq IN OUT, which grok's own
# read-only handling refuses while still running them in a pipeline.
# Redirection, substitution and the destructive find actions turn an allowed command into a write.
# dontAsk lets touch and mkdir through, so they are denied by name.
unsafe=('*>*' '*<(*' '*$(*' '*`*' 'find * -delete*' 'find * -exec*' 'touch *' 'mkdir *')

# No --deny Write or --deny Edit: either one makes grok refuse an rg that reads a pipe, which cancels
# the session. dontAsk already refuses both tools because no rule allows them.
rules=()
allowed=""
for rule in "${read_only[@]}"; do
  rules+=(--allow "Bash($rule)")
  allowed+="${rule% \*}, "
done
for rule in "${bare[@]}"; do rules+=(--allow "Bash($rule)"); done
for rule in "${unsafe[@]}"; do rules+=(--deny "Bash($rule)"); done

# Grok has no switch to turn off its bundled skills, and its review skill tells it to spawn a
# subagent and write notes to a file. Under dontAsk any command outside the allow list ends the
# session as cancelled, so the brief names the allowed commands. dontAsk also cancels any command
# with a * inside quotes, such as rg --glob "*.ex", whatever the allow rule says, so the brief
# steers Grok to type filters and unquoted globs.
{
  echo "Do this review yourself in this session. Do not load skills or spawn subagents, write no files, and print the findings as your final reply."
  echo "Your working directory is the repository under review. Run git there with no -C; read files elsewhere by absolute path."
  echo "Run only these read-only commands, each with no output redirection, process substitution or command substitution: ${allowed%, }. Join them with a pipe or && when you need to, as long as every stage is one of these. Never put * inside quotes. Filter files by type, such as rg -t js, or write a glob unquoted, such as --glob=*.ex. Any other command ends the session."
  echo "End the reply with one line that starts with VERDICT: and gives your verdict in the brief's terms, for example VERDICT: ship with fixes."
  echo
  cat "$brief"
} >"$work/brief"

grok_flags=(
  -m "${FACTORY_GROK_MODEL:-grok-4.7}"
  --output-format streaming-json
  "${rules[@]}"
  --no-subagents
  --max-turns "${FACTORY_GROK_MAX_TURNS:-60}"
  --permission-mode dontAsk
  --disable-web-search
  --reasoning-effort "${FACTORY_GROK_EFFORT:-low}"
  --cwd "$dir"
)

# grok has no wall-clock limit, and a hung session once held a panel for 25 minutes, so a watchdog
# ends it at the shared deadline. The watchdog's sleep is killed first so a finished run leaves no marker.
deadline=$(( $(date +%s) + ${FACTORY_GROK_TIMEOUT:-600} ))
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
last_failed() {
  jq -rs '
    (map(select(.type == "tool_call") | {key: .toolCallId, value: (.rawInput.command // .toolName)}) | from_entries) as $calls
    | map(select(.type == "tool_call_update" and .status == "failed")) | last
    | if . == null then "none" else "\($calls[.toolCallId] // .toolCallId): \(.content[0].content.text // "no detail")" end
  ' "$work/stream" 2>/dev/null || echo "unreadable"
}

status=0
run_grok --prompt-file "$work/brief" || status=$?
reason=$(stop_reason)

# A refused command cancels the whole turn, so resume the session and name the refusal. Grok then
# rewrites the command inside the rules and carries on with the review it already started.
retries=0
while [[ "$status" -eq 0 && "$reason" == "cancelled" && "$retries" -lt "${FACTORY_GROK_RETRIES:-3}" ]]; do
  session=$(session_id)
  [[ -n "$session" ]] || break
  retries=$((retries + 1))
  refused=$(last_failed)
  echo "grok-review: resume $retries after a refused command: $refused" >&2
  echo "This command was refused and ended your turn: $refused. Rewrite it to follow the command rules above, with no * inside quotes, and continue the review." >"$work/retry"
  run_grok --resume "$session" --prompt-file "$work/retry" || status=$?
  reason=$(stop_reason)
done

if [[ -e "$work/timed_out" ]]; then
  echo "grok-review: no verdict within ${FACTORY_GROK_TIMEOUT:-600}s ($retries resumes); last failed tool call: $(last_failed)" >&2
  exit 6
fi

if [[ "$status" -ne 0 || "$reason" != "end_turn" ]]; then
  echo "grok-review: session did not finish (grok exit $status, stopReason ${reason:-none}, $retries resumes); last failed tool call: $(last_failed)" >&2
  exit 5
fi

# Text before a tool call is Grok narrating its next step, so relay only the reply after the last one.
jq -rjs '(map(.type == "tool_call") | rindex(true) // -1) as $last | .[$last + 1:][] | select(.type == "text") | .data' "$work/stream"
echo
