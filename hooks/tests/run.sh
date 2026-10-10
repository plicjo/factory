#!/bin/sh
# Runs the plugin hooks and the Grok review script against the JSON shapes Claude Code sends and checks
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

fakebin="$T/fakebin"
mkdir -p "$fakebin"
printf 'brief' >"$T/brief"
fakegrok() {
	{
		printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s"\nprev=""\nfor a in "$@"; do\n' "$T/argv"
		printf '\t[ "$prev" = --prompt-file ] && cp "$a" "%s"\n' "$T/sent"
		printf '\t[ "$prev" = --max-turns ] && printf %%s "$a" >"%s"\n\tprev=$a\ndone\n' "$T/turns"
		printf 'cat <<'"'"'EOF'"'"'\n%s\nEOF\n' "$1"
	} >"$fakebin/grok"
	chmod +x "$fakebin/grok"
}
grokreview() { PATH="$fakebin:$PATH" FACTORY_GROK_SEAT=1 bash "$H/../tools/grok-review.sh" "$T/brief" 2>"$T/err"; }

fakegrok '{"type":"text","data":"## Findings\n"}
{"type":"text","data":"none"}
{"type":"end","stopReason":"end_turn"}'
out=$(grokreview); code=$?
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -q 'none'; then ok 'grok review relays the reply on end_turn'; else ko 'grok review relays the reply on end_turn'; fi

if [ "$(cat "$T/turns")" = 60 ] && grep -q 'starts with VERDICT:' "$T/sent" && grep -q '^brief$' "$T/sent"; then
	ok 'grok review caps at 60 turns and sends the verdict instruction ahead of the brief'
else
	ko 'grok review caps at 60 turns and sends the verdict instruction ahead of the brief'
fi

fakegrok '{"type":"text","data":"I will review"}
{"type":"tool_call","toolCallId":"c1","rawInput":{"command":"python --version"}}
{"type":"tool_call_update","toolCallId":"c1","status":"failed","content":[{"type":"content","content":{"type":"text","text":"User cancelled"}}]}
{"type":"end","stopReason":"cancelled"}'
out=$(grokreview); code=$?
if [ "$code" -eq 5 ] && [ -z "$out" ] && grep -q 'stopReason cancelled.*python --version' "$T/err"; then
	ok 'grok review exits 5 and names the failed call on a cancelled session'
else
	ko 'grok review exits 5 and names the failed call on a cancelled session'
fi

fakegrok '{"type":"end","stopReason":"end_turn"}'
grokreview >/dev/null
if grep -qx 'Write' "$T/argv" || grep -qx 'Edit' "$T/argv"; then
	ko 'grok review denies no tool by name, since that cancels piped rg'
else
	ok 'grok review denies no tool by name, since that cancels piped rg'
fi
if grep -Fqx 'Bash(touch *)' "$T/argv" && grep -Fqx 'Bash(*>*)' "$T/argv" && grep -Fqx 'Bash(rg *)' "$T/argv" && grep -q 'Join them with a pipe' "$T/sent"; then
	ok 'grok review denies shell writes and allows pipes between read-only commands'
else
	ko 'grok review denies shell writes and allows pipes between read-only commands'
fi

fakegrok '{"type":"text","data":"partial"}'
out=$(grokreview); code=$?
if [ "$code" -eq 5 ]; then ok 'grok review exits 5 when the stream has no end event'; else ko 'grok review exits 5 when the stream has no end event'; fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
