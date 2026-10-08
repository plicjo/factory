#!/usr/bin/env bash
# A foreground command blocks the session, so the user cannot talk to the agent until it
# exits. The agent raises the Bash timeout above its 2-minute default only when it expects
# a long wait, which makes that timeout the signal to run the command in the background.
set -euo pipefail

input=$(cat)

[ "${FACTORY_ALLOW_LONG_FOREGROUND:-}" = "1" ] && exit 0
printf '%s' "$input" | grep -qE '"run_in_background" *: *true' && exit 0

timeout=$(printf '%s' "$input" | sed -n 's/.*"timeout" *: *\([0-9][0-9]*\).*/\1/p' | head -n1)
[ -n "$timeout" ] && [ "$timeout" -gt 120000 ] || exit 0

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"This command expects to run longer than 2 minutes, and a foreground run blocks the user until it exits. Run the same command again with run_in_background set to true. You will be notified when it exits, and the user can talk to you meanwhile. Do not lower the timeout to get past this check."}}
JSON
