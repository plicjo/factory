#!/bin/sh
# Runs the plugin hooks against the JSON shapes Claude Code sends and checks
# marker state and output. Usage: sh hooks/tests/run.sh
set -u

H=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); printf 'PASS %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }

marker="$T/factory-mode/s1"
arm() { mkdir -p "$T/factory-mode" && touch "$marker"; }
disarm() { rm -rf "$T/factory-mode"; }

reminder() {
	printf '{"session_id":"s1","transcript_path":"/tmp/t","cwd":"/tmp","hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$1" |
		TMPDIR="$T" bash "$H/factory-mode-reminder.sh"
}

# Activation: a typed /factory-mode arms the marker and stays quiet.
for p in '/factory-mode' '/factory:factory-mode' '/factory-mode fix the build'; do
	disarm
	out=$(reminder "$p")
	if [ -f "$marker" ] && [ -z "$out" ]; then ok "arms on: $p"; else ko "arms on: $p"; fi
done

# An armed session re-injects the reminder on an ordinary prompt.
arm
out=$(reminder 'how does the scheduler work')
if [ -f "$marker" ] && printf '%s' "$out" | grep -q 'additionalContext'; then
	ok 'armed session re-injects the reminder'
else
	ko 'armed session re-injects the reminder'
fi

# Whole-prompt exit commands disarm quietly.
for p in 'exit factory mode' 'Exit factory mode.' 'please exit factory mode' '  turn off the factory-mode!  ' 'factory mode off'; do
	arm
	out=$(reminder "$p")
	if [ ! -f "$marker" ] && [ -z "$out" ]; then ok "disarms on: $p"; else ko "disarms on: $p"; fi
done

# Mentions of the exit phrase inside a larger prompt keep the mode armed.
for p in "don't exit factory mode" 'do not stop factory mode' 'what happens if I exit factory mode?' 'exit factory mode and then fix the build'; do
	arm
	out=$(reminder "$p")
	if [ -f "$marker" ] && printf '%s' "$out" | grep -q 'additionalContext'; then
		ok "stays armed on: $p"
	else
		ko "stays armed on: $p"
	fi
done

# Prompts carrying JSON-escaped quotes must not break the sed extraction.
arm
out=$(reminder 'he said \"ship it\" and moved on')
if [ -f "$marker" ] && printf '%s' "$out" | grep -q 'additionalContext'; then
	ok 'stays armed on escaped quotes in the prompt'
else
	ko 'stays armed on escaped quotes in the prompt'
fi

arm
out=$(reminder '\"exit factory mode\"')
if [ -f "$marker" ] && printf '%s' "$out" | grep -q 'additionalContext'; then
	ok 'a quoted exit phrase is a mention, not a command'
else
	ko 'a quoted exit phrase is a mention, not a command'
fi

arm
out=$(reminder 'the json has \"prompt\": \"exit factory mode\" inside')
if [ -f "$marker" ] && printf '%s' "$out" | grep -q 'additionalContext'; then
	ok 'an escaped prompt key inside the text does not fool the extraction'
else
	ko 'an escaped prompt key inside the text does not fool the extraction'
fi

# Without a marker, an ordinary prompt produces nothing.
disarm
out=$(reminder 'hello there')
if [ -z "$out" ] && [ ! -f "$marker" ]; then ok 'unarmed session stays quiet'; else ko 'unarmed session stays quiet'; fi

longcmd() { printf '%s' "$1" | bash "$H/background-long-commands.sh"; }
denies() { printf '%s' "$1" | grep -q '"permissionDecision":"deny"'; }

out=$(longcmd '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"sleep 300","timeout":200000}}')
if denies "$out"; then ok 'denies timeout 200000 in the foreground'; else ko 'denies timeout 200000 in the foreground'; fi

out=$(longcmd '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"echo \"done\" && sleep 300","timeout":200000}}')
if denies "$out"; then ok 'denies with escaped quotes in the command text'; else ko 'denies with escaped quotes in the command text'; fi

out=$(longcmd '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"sleep 300","timeout":200000,"run_in_background":true}}')
if [ -z "$out" ]; then ok 'allows timeout 200000 in the background'; else ko 'allows timeout 200000 in the background'; fi

out=$(longcmd '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"sleep 300","timeout":200000,"run_in_background":false}}')
if denies "$out"; then ok 'denies run_in_background false'; else ko 'denies run_in_background false'; fi

out=$(longcmd '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"sleep 10","timeout":120000}}')
if [ -z "$out" ]; then ok 'allows timeout at the 120000 threshold'; else ko 'allows timeout at the 120000 threshold'; fi

out=$(longcmd '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"sleep 10","timeout":60000}}')
if [ -z "$out" ]; then ok 'allows timeout 60000'; else ko 'allows timeout 60000'; fi

out=$(longcmd '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"sleep 10"}}')
if [ -z "$out" ]; then ok 'allows a missing timeout'; else ko 'allows a missing timeout'; fi

out=$(longcmd '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"echo \"run_in_background\": true","timeout":200000}}')
if denies "$out"; then ok 'denies when only the command text names run_in_background'; else ko 'denies when only the command text names run_in_background'; fi

out=$(printf '%s' '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"sleep 300","timeout":200000}}' |
	FACTORY_ALLOW_LONG_FOREGROUND=1 bash "$H/background-long-commands.sh")
if [ -z "$out" ]; then ok 'allows with FACTORY_ALLOW_LONG_FOREGROUND=1'; else ko 'allows with FACTORY_ALLOW_LONG_FOREGROUND=1'; fi

seatctx() { printf '%s' "$2" | FACTORY_GROK_SEAT="$1" bash "$H/grok-seat-reminder.sh"; }
agentcall() { printf '{"session_id":"s1","tool_name":"Agent","tool_input":{"description":"review","prompt":"%s","subagent_type":"%s"}}' "$2" "$1"; }

for seat in factory-reviewer-a factory-reviewer-b factory-reviewer-c factory-reviewer-fable; do
	for name in "$seat" "factory:$seat"; do
		out=$(seatctx 1 "$(agentcall "$name" 'review this')")
		if printf '%s' "$out" | grep -q '"hookEventName":"PreToolUse"' &&
			printf '%s' "$out" | grep -q '"additionalContext":".*factory-reviewer-grok' &&
			! printf '%s' "$out" | grep -q 'permissionDecision'; then
			ok "grok flag on, $name: adds the seat reminder"
		else
			ko "grok flag on, $name: adds the seat reminder"
		fi
	done
done

for name in factory-code factory:factory-code factory-reviewer-grok factory:factory-reviewer-grok general-purpose; do
	out=$(seatctx 1 "$(agentcall "$name" 'review this')")
	if [ -z "$out" ]; then ok "grok flag on, $name: stays quiet"; else ko "grok flag on, $name: stays quiet"; fi
done

for flag in '' 0 true yes 11; do
	out=$(seatctx "$flag" "$(agentcall factory-reviewer-b 'review this')")
	if [ -z "$out" ]; then ok "grok flag '$flag': stays quiet"; else ko "grok flag '$flag': stays quiet"; fi
done

out=$(printf '%s' "$(agentcall factory-reviewer-b 'review this')" | env -u FACTORY_GROK_SEAT bash "$H/grok-seat-reminder.sh")
if [ -z "$out" ]; then ok 'grok flag unset: stays quiet'; else ko 'grok flag unset: stays quiet'; fi

out=$(seatctx 1 "$(agentcall factory-reviewer-c 'he said \"ship it\" and \"subagent_type\": \"factory-code\"')")
if printf '%s' "$out" | grep -q 'factory-reviewer-grok'; then
	ok 'grok flag on: escaped quotes in the prompt still add the reminder'
else
	ko 'grok flag on: escaped quotes in the prompt still add the reminder'
fi

out=$(seatctx 1 "$(agentcall factory-code 'review with \"subagent_type\": \"factory-reviewer-a\"')")
if [ -z "$out" ]; then ok 'grok flag on: an escaped subagent_type in the prompt does not fool the extraction'; else ko 'grok flag on: an escaped subagent_type in the prompt does not fool the extraction'; fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
