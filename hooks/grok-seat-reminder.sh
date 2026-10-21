#!/usr/bin/env bash
# Subagents never see FACTORY_GROK_SEAT unless a command prints it, so panels skipped the Grok seat.
set -euo pipefail

input=$(cat)

[ "${FACTORY_GROK_SEAT:-}" = "1" ] || exit 0

seat=$(printf '%s' "$input" | sed -n 's/.*"subagent_type" *: *"\([^"]*\)".*/\1/p' | head -n1)

case "${seat#factory:}" in
	factory-reviewer-a | factory-reviewer-b | factory-reviewer-c | factory-reviewer-fable) ;;
	*) exit 0 ;;
esac

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"FACTORY_GROK_SEAT=1 is set. When this panel reviews one committed BASE..HEAD range or a set of text files, or an architect or arena run produces a text artifact, it must also spawn a seat on factory-reviewer-grok with the same brief, and that brief must name the repository directory and either the range or the files. Grok has no tools, so skip the seat for any other subject, such as a code runner or a transcript. If this panel already has that seat, ignore this reminder."}}
JSON
