#!/usr/bin/env bash
# Subagents never see FACTORY_GROK_SEAT unless a command prints it, so panels skipped the Grok seat.
set -euo pipefail

input=$(cat)

[ "${FACTORY_GROK_SEAT:-}" = "1" ] || exit 0

seat=$(printf '%s' "$input" | sed -n 's/.*"subagent_type" *: *"\([^"]*\)".*/\1/p' | head -n1)

case "${seat#factory:}" in
	factory-reviewer-a | factory-reviewer-c | factory-reviewer-fable) ;;
	*) exit 0 ;;
esac

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"FACTORY_GROK_SEAT=1 is set, so this panel must also spawn a seat on factory-reviewer-grok with the same brief. If this panel already has that seat, ignore this reminder."}}
JSON
