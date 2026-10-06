#!/usr/bin/env bash
# Keeps /factory-mode on for the rest of a session, the way Cursor's `mode: true` did.
set -euo pipefail

input=$(cat)
session=$(printf '%s' "$input" | sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p' | head -n1)
prompt=$(printf '%s' "$input" | sed -n 's/.*"prompt" *: *"\(.*\)".*/\1/p' | head -n1)
[ -n "$session" ] || exit 0

state="${TMPDIR:-/tmp}/factory-mode"
marker="$state/$session"

if printf '%s' "$prompt" | grep -qiE '^[[:space:]]*/(factory:)?factory-mode([[:space:]]|$)'; then
	mkdir -p "$state"
	touch "$marker"
	exit 0
fi

[ -f "$marker" ] || exit 0

if printf '%s' "$prompt" | grep -qiE '(exit|stop|leave|turn off|disable|end) (the )?factory[- ]mode|factory[- ]mode off'; then
	rm -f "$marker"
	exit 0
fi

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"factory-mode is on for this session. New task? Playbook match or rigor needed -> apply factory-mode, re-reading its SKILL.md if it is no longer in context. Casual turn -> don't. The user can say \"exit factory mode\" to turn it off."}}
JSON
