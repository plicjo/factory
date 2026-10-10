#!/usr/bin/env bash
# Single chokepoint for the opt-in Grok review seat. Refuses to run unless
# FACTORY_GROK_SEAT=1 so environments that must not send code to non-Anthropic
# vendors never reach the CLI, and pins the read-only flags in one place.
# grok exits 0 even when a refused tool call cancels the session, so the script reads the
# stream's final `end` event and fails unless its stopReason is `end_turn`.
# Exit codes: 2 seat not enabled, 3 grok CLI or jq missing, 4 brief unreadable,
# 5 session did not finish, from a refused command that survived every resume or the turn cap (the reason and the last failed tool call go to stderr).
set -euo pipefail

brief="${1:-}"

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

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

read_only=(
  'git log *' 'git diff *' 'git show *' 'git status *' 'git rev-parse *' 'git fetch *' 'git blame *'
  'git ls-files *' 'git ls-tree *' 'git cat-file *' 'git merge-base *' 'git grep *' 'git rev-list *'
  'git diff-tree *' 'git show-ref *' 'git describe *' 'git shortlog *' 'gh pr view *' 'gh pr diff *'
  'echo *' 'rg *' 'grep *' 'ls *' 'cat *' 'head *' 'tail *' 'wc *' 'nl *' 'cut *'
  'diff *' 'jq *' 'find *' 'sed -n *'
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
for rule in "${unsafe[@]}"; do rules+=(--deny "Bash($rule)"); done

# Grok has no switch to turn off its bundled skills, and its review skill tells it to spawn a
# subagent and write notes to a file. Under dontAsk any command outside the allow list ends the
# session as cancelled, so the brief names the allowed commands. dontAsk also cancels any command
# with a * inside quotes, such as rg --glob "*.ex", whatever the allow rule says, so the brief
# steers Grok to type filters and unquoted globs.
{
  echo "Do this review yourself in this session. Do not load skills or spawn subagents, write no files, and print the findings as your final reply."
  echo "Run only these read-only commands, each with no output redirection, process substitution or command substitution: ${allowed%, }. Join them with a pipe when you need to, as long as every stage is one of these. Never put * inside quotes. Filter files by type, such as rg -t js, or write a glob unquoted, such as --glob=*.ex. Any other command ends the session."
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
)

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
grok "${grok_flags[@]}" --prompt-file "$work/brief" >"$work/stream" || status=$?
reason=$(stop_reason)

# A refused command cancels the whole turn, so resume the session and name the refusal. Grok then
# rewrites the command inside the rules and carries on with the review it already started.
retries=0
while [[ "$status" -eq 0 && "$reason" == "cancelled" && "$retries" -lt "${FACTORY_GROK_RETRIES:-3}" ]]; do
  session=$(session_id)
  [[ -n "$session" ]] || break
  retries=$((retries + 1))
  echo "This command was refused and ended your turn: $(last_failed). Rewrite it to follow the command rules above, with no * inside quotes, and continue the review." >"$work/retry"
  grok "${grok_flags[@]}" --resume "$session" --prompt-file "$work/retry" >"$work/stream" || status=$?
  reason=$(stop_reason)
done

if [[ "$status" -ne 0 || "$reason" != "end_turn" ]]; then
  echo "grok-review: session did not finish (grok exit $status, stopReason ${reason:-none}, $retries resumes); last failed tool call: $(last_failed)" >&2
  exit 5
fi

jq -rj 'select(.type == "text") | .data' "$work/stream"
echo
