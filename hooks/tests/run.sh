#!/bin/sh
# Runs both plugin hooks against the JSON shapes Claude Code sends and checks
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

# Without a marker, an ordinary prompt produces nothing.
disarm
out=$(reminder 'hello there')
if [ -z "$out" ] && [ ! -f "$marker" ]; then ok 'unarmed session stays quiet'; else ko 'unarmed session stays quiet'; fi

longcmd() { printf '%s' "$1" | bash "$H/background-long-commands.sh"; }
denies() { printf '%s' "$1" | grep -q '"permissionDecision":"deny"'; }

out=$(longcmd '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"sleep 300","timeout":200000}}')
if denies "$out"; then ok 'denies timeout 200000 in the foreground'; else ko 'denies timeout 200000 in the foreground'; fi

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

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
