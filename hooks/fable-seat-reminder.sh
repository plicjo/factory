#!/usr/bin/env bash
# Subagents never see FACTORY_FABLE_SEAT unless a command prints it, so panels kept seat A on Opus.
set -euo pipefail

input=$(cat)

[ "${FACTORY_FABLE_SEAT:-}" = "1" ] || exit 0

seat=$(printf '%s' "$input" | sed -n 's/.*"subagent_type" *: *"\([^"]*\)".*/\1/p' | head -n1)

case "${seat#factory:}" in
	factory-reviewer-a) ;;
	*) exit 0 ;;
esac

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"FACTORY_FABLE_SEAT=1 is set, so panel seat A must run on factory-reviewer-fable with the same brief. If this spawn is seat A, spawn it on factory-reviewer-fable instead. If it is an extra seat, or the fallback after a usage-credits failure, ignore this reminder."}}
JSON
