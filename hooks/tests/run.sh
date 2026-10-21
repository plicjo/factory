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

out=$(longcmd '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"\"${CLAUDE_PLUGIN_ROOT}/tools/grok-review.sh\" \"$BRIEF_FILE\" /r a b","timeout":600000}}')
if [ -z "$out" ]; then ok 'allows grok-review.sh in the foreground, since it ends itself before the Bash limit'; else ko 'allows grok-review.sh in the foreground, since it ends itself before the Bash limit'; fi

out=$(longcmd '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"sleep 300","description":"wait like grok-review.sh","timeout":200000}}')
if denies "$out"; then ok 'denies when only the description names grok-review.sh'; else ko 'denies when only the description names grok-review.sh'; fi

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

fablectx() { printf '%s' "$2" | FACTORY_FABLE_SEAT="$1" bash "$H/fable-seat-reminder.sh"; }

for name in factory-reviewer-a factory:factory-reviewer-a; do
	out=$(fablectx 1 "$(agentcall "$name" 'review this')")
	if printf '%s' "$out" | grep -q '"hookEventName":"PreToolUse"' &&
		printf '%s' "$out" | grep -q '"additionalContext":".*factory-reviewer-fable' &&
		! printf '%s' "$out" | grep -q 'permissionDecision'; then
		ok "fable flag on, $name: adds the seat reminder"
	else
		ko "fable flag on, $name: adds the seat reminder"
	fi
done

for name in factory-reviewer-b factory-reviewer-c factory-reviewer-fable factory:factory-reviewer-fable factory-reviewer-grok factory-code general-purpose; do
	out=$(fablectx 1 "$(agentcall "$name" 'review this')")
	if [ -z "$out" ]; then ok "fable flag on, $name: stays quiet"; else ko "fable flag on, $name: stays quiet"; fi
done

for flag in '' 0 true yes 11; do
	out=$(fablectx "$flag" "$(agentcall factory-reviewer-a 'review this')")
	if [ -z "$out" ]; then ok "fable flag '$flag': stays quiet"; else ko "fable flag '$flag': stays quiet"; fi
done

out=$(printf '%s' "$(agentcall factory-reviewer-a 'review this')" | env -u FACTORY_FABLE_SEAT bash "$H/fable-seat-reminder.sh")
if [ -z "$out" ]; then ok 'fable flag unset: stays quiet'; else ko 'fable flag unset: stays quiet'; fi

out=$(fablectx 1 "$(agentcall factory-code 'review with \"subagent_type\": \"factory-reviewer-a\"')")
if [ -z "$out" ]; then ok 'fable flag on: an escaped subagent_type in the prompt does not fool the extraction'; else ko 'fable flag on: an escaped subagent_type in the prompt does not fool the extraction'; fi

fakebin="$T/fakebin"
mkdir -p "$fakebin"
printf 'brief' >"$T/brief"

G="$T/repo"
commit() { git -C "$G" add -A && git -C "$G" -c user.email=t@t -c user.name=t commit -qm "$1" && git -C "$G" rev-parse HEAD; }
git init -q "$G"
printf 'old\n' >"$G/small.txt"
awk 'BEGIN { for (i = 0; i < 60; i++) printf "%049d\n", i }' >"$G/big.txt"
base=$(commit 'Start')
printf 'new small\n' >"$G/small.txt"
sed -i.bak '1s/.*/changed/' "$G/big.txt" && rm "$G/big.txt.bak"
printf 'a\000b' >"$G/bin.dat"
tip=$(commit 'Change two files')
bigsize=$(git -C "$G" cat-file -s "$tip:big.txt")

cat >"$fakebin/grok" <<EOF
#!/bin/sh
printf '%s\n' "\$@" >"$T/argv"
prev=""
resumed=""
for a in "\$@"; do
	[ "\$prev" = --resume ] && resumed=\$a
	[ "\$prev" = --prompt-file ] && cp "\$a" "$T/sent\${resumed:+.resume}"
	prev=\$a
done
if [ -n "\$resumed" ]; then printf %s "\$resumed" >"$T/resumed"; cat "$T/stream.resume"; else cat "$T/stream.first"; fi
EOF
chmod +x "$fakebin/grok"
streams() { printf '%s\n' "$1" >"$T/stream.first" && printf '%s\n' "${2:-}" >"$T/stream.resume" && rm -f "$T/resumed" "$T/sent.resume"; }
grokreview() { PATH="$fakebin:$PATH" FACTORY_GROK_SEAT=1 bash "$H/../tools/grok-review.sh" "$T/brief" "$G" "$base" "$tip" 2>"$T/err"; }
argafter() { grep -A1 -Fx -- "$1" "$T/argv" | sed -n 2p; }
done_turn='{"type":"end","stopReason":"end_turn","sessionId":"s1"}'

streams '{"type":"text","data":"## Findings\nnone\n"}
{"type":"text","data":"VERDICT: ship"}'"
$done_turn"
out=$(grokreview); code=$?
if [ "$code" -eq 0 ] && [ "$out" = "## Findings
none
VERDICT: ship" ]; then ok 'grok review relays the reply on end_turn'; else ko "grok review relays the reply on end_turn (exit $code)"; fi
if [ ! -s "$T/err" ]; then ok 'grok review writes nothing to stderr on a clean finish'; else ko "grok review writes nothing to stderr on a clean finish: $(cat "$T/err")"; fi

if grep -q '^You have no tools in this session' "$T/sent" && grep -qx 'brief' "$T/sent" && grep -q 'Change two files' "$T/sent" &&
	grep -qx '+new small' "$T/sent" && grep -Fqx "===== FILE small.txt AT $tip =====" "$T/sent" &&
	grep -Fqx "===== FILE big.txt AT $tip =====" "$T/sent" && grep -qx 'changed' "$T/sent" && grep -qx "$(sed -n '$p' "$G/big.txt")" "$T/sent" &&
	grep -qx 'Binary file or submodule, not shown: bin.dat' "$T/sent"; then
	ok 'grok review sends the no-tools rule, the brief, the log, the diff and the changed files in the prompt'
else
	ko 'grok review sends the no-tools rule, the brief, the log, the diff and the changed files in the prompt'
fi

if [ "$(argafter --tools)" = todo_write ] && [ "$(argafter --disallowed-tools)" = todo_write,search_tool,use_tool ] &&
	! grep -qx -- '--allow' "$T/argv" && grep -qx -- '--verbatim' "$T/argv" &&
	[ "$(argafter --reasoning-effort)" = low ] && [ "$(argafter --cwd)" = "$G" ]; then
	ok 'grok review removes every tool, allows no command, sends the prompt verbatim, and runs at low effort in DIR'
else
	ko 'grok review removes every tool, allows no command, sends the prompt verbatim, and runs at low effort in DIR'
fi

PATH="$fakebin:$PATH" FACTORY_GROK_SEAT=1 FACTORY_GROK_MAX_BYTES=4000 bash "$H/../tools/grok-review.sh" "$T/brief" "$G" "$base" "$tip" >/dev/null 2>"$T/err"
if grep -Fqx "===== FILE small.txt AT $tip =====" "$T/sent" && ! grep -q '===== FILE big.txt' "$T/sent" &&
	grep -q "largest files first: big.txt ($bigsize bytes)$" "$T/sent" && grep -qx -- '-old' "$T/sent"; then
	ok 'grok review leaves out the largest file over the size cap, keeps the diff, and names the cut'
else
	ko 'grok review leaves out the largest file over the size cap, keeps the diff, and names the cut'
fi

PATH="$fakebin:$PATH" FACTORY_GROK_SEAT=1 FACTORY_GROK_MAX_BYTES=1 bash "$H/../tools/grok-review.sh" "$T/brief" "$G" "$base" "$tip" >/dev/null 2>"$T/err"
if grep -q '^\[diff cut for size after 0 of [0-9]* bytes\]$' "$T/sent" && ! grep -q '===== FILE' "$T/sent"; then
	ok 'grok review cuts the diff itself and says so when the diff alone passes the cap'
else
	ko 'grok review cuts the diff itself and says so when the diff alone passes the cap'
fi

streams '{"type":"text","data":"I will read the file."}
{"type":"tool_call","toolCallId":"c1","toolName":"read_file","rawInput":{"path":"small.txt"}}
{"type":"tool_call_update","toolCallId":"c1","status":"failed"}'"
$done_turn" '{"type":"text","data":"none\nVERDICT: ship"}'"
$done_turn"
out=$(grokreview); code=$?
if [ "$code" -eq 0 ] && [ "$out" = "none
VERDICT: ship" ] && [ "$(cat "$T/resumed")" = s1 ] && grep -q 'has no tools' "$T/sent.resume" &&
	grep -q 'resume after a tool call: read_file' "$T/err"; then
	ok 'grok review resumes once after a tool call, says it has no tools, and relays the resumed reply'
else
	ko "grok review resumes once after a tool call, says it has no tools, and relays the resumed reply (exit $code)"
fi

call='{"type":"tool_call","toolCallId":"c1","toolName":"run_terminal_command","rawInput":{"command":"git log"}}'
streams "$call
$done_turn" "$call
$done_turn"
out=$(grokreview); code=$?
if [ "$code" -eq 5 ] && [ -z "$out" ] && grep -q 'tool calls run_terminal_command, 1 resumes' "$T/err"; then
	ok 'grok review exits 5 when Grok still calls a tool after the resume'
else
	ko "grok review exits 5 when Grok still calls a tool after the resume (exit $code)"
fi

streams '{"type":"text","data":"partial"}'
out=$(grokreview); code=$?
if [ "$code" -eq 5 ] && grep -q 'stopReason none' "$T/err"; then ok 'grok review exits 5 when the stream has no end event'; else ko 'grok review exits 5 when the stream has no end event'; fi

streams '{"type":"text","data":"looks fine"}'"
$done_turn"
out=$(grokreview); code=$?
if [ "$code" -eq 7 ] && [ -z "$out" ] && grep -q 'no VERDICT line.*looks fine' "$T/err"; then
	ok 'grok review exits 7 when the reply has no VERDICT line'
else
	ko "grok review exits 7 when the reply has no VERDICT line (exit $code)"
fi

PATH="$fakebin:$PATH" FACTORY_GROK_SEAT=1 FACTORY_GROK_EFFORT=medium bash "$H/../tools/grok-review.sh" "$T/brief" "$G" "$base" "$tip" >/dev/null 2>"$T/err"
if [ "$(argafter --reasoning-effort)" = medium ]; then ok 'grok review takes FACTORY_GROK_EFFORT'; else ko 'grok review takes FACTORY_GROK_EFFORT'; fi

PATH="$fakebin:$PATH" FACTORY_GROK_SEAT=1 bash "$H/../tools/grok-review.sh" "$T/brief" "$T/missing" "$base" "$tip" >/dev/null 2>"$T/err"; code=$?
if [ "$code" -eq 4 ] && grep -q 'review directory missing' "$T/err"; then ok 'grok review exits 4 on a missing DIR'; else ko 'grok review exits 4 on a missing DIR'; fi

PATH="$fakebin:$PATH" FACTORY_GROK_SEAT=1 bash "$H/../tools/grok-review.sh" "$T/brief" "$G" >/dev/null 2>"$T/err"; code=$?
if [ "$code" -eq 4 ] && grep -q 'usage: grok-review.sh BRIEF DIR BASE HEAD' "$T/err"; then
	ok 'grok review exits 4 without a BASE and HEAD range'
else
	ko 'grok review exits 4 without a BASE and HEAD range'
fi

streams '{"type":"text","data":"sketch\nVERDICT: candidate ready"}'"
$done_turn"
printf 'grounding note\n' >"$T/grounding.md"
printf 'uncommitted\n' >"$G/draft.txt"
grokfiles() { PATH="$fakebin:$PATH" FACTORY_GROK_SEAT=1 bash "$H/../tools/grok-review.sh" --files "$T/brief" "$G" "$@" 2>"$T/err"; }
out=$(grokfiles small.txt draft.txt "$T/grounding.md" bin.dat); code=$?
if [ "$code" -eq 0 ] && [ "$out" = "sketch
VERDICT: candidate ready" ] && grep -qx 'brief' "$T/sent" &&
	grep -Fqx '===== FILE small.txt =====' "$T/sent" && grep -qx 'new small' "$T/sent" &&
	grep -qx 'uncommitted' "$T/sent" && grep -Fqx "===== FILE $T/grounding.md =====" "$T/sent" && grep -qx 'grounding note' "$T/sent" &&
	grep -qx 'Binary file, not shown: bin.dat' "$T/sent" && ! grep -q '===== COMMITS\|===== DIFF' "$T/sent"; then
	ok 'grok files sends the brief and each named file from disk, relative or absolute, with no commits or diff'
else
	ko "grok files sends the brief and each named file from disk, relative or absolute, with no commits or diff (exit $code)"
fi

FACTORY_GROK_MAX_BYTES=4000 grokfiles small.txt big.txt >/dev/null
if grep -Fqx '===== FILE small.txt =====' "$T/sent" && grep -q "largest files first: big.txt ($bigsize bytes)$" "$T/sent"; then
	ok 'grok files leaves out the largest file over the size cap and names the cut'
else
	ko 'grok files leaves out the largest file over the size cap and names the cut'
fi

out=$(grokfiles); code=$?
if [ "$code" -eq 4 ] && grep -q 'usage: grok-review.sh --files BRIEF DIR FILE' "$T/err"; then ok 'grok files exits 4 when no file is named'; else ko 'grok files exits 4 when no file is named'; fi

out=$(grokfiles small.txt nope.txt); code=$?
if [ "$code" -eq 4 ] && grep -q 'file missing or unreadable: nope.txt' "$T/err"; then ok 'grok files exits 4 on a missing file'; else ko 'grok files exits 4 on a missing file'; fi
rm "$G/draft.txt"

printf '#!/bin/sh\nexec sleep 30\n' >"$fakebin/grok" && chmod +x "$fakebin/grok"
start=$(date +%s)
FACTORY_GROK_TIMEOUT=1 grokreview >/dev/null; code=$?
took=$(( $(date +%s) - start ))
if [ "$code" -eq 6 ] && [ "$took" -lt 10 ] && grep -q 'no verdict within 1s' "$T/err"; then
	ok 'grok review exits 6 once the run passes FACTORY_GROK_TIMEOUT'
else
	ko "grok review exits 6 once the run passes FACTORY_GROK_TIMEOUT (exit $code after ${took}s)"
fi

# Grok reads a hook command with no space as a path relative to hooks.json, so a quoted
# "${CLAUDE_PLUGIN_ROOT}" path never runs there. A bash prefix makes it a shell command in both hosts.
bad=$(jq -r '.. | .command? // empty' "$H/hooks.json" | while read -r cmd; do
	script=${cmd#'bash "${CLAUDE_PLUGIN_ROOT}/hooks/'}
	script=${script%'"'}
	if [ "$script" = "$cmd" ] || [ ! -f "$H/$script" ]; then printf '%s\n' "$cmd"; fi
done)
if [ -z "$bad" ]; then ok 'every hook runs as bash "${CLAUDE_PLUGIN_ROOT}/hooks/<script>" and the script exists'; else ko "hook commands grok cannot run: $bad"; fi

# Auto-prune: a scratch repo with one branch per case, swept once at the real time and once a day later.
R="$T/prune"
mkdir -p "$R"
git init -q --bare -b main "$R/origin.git"
git clone -q "$R/origin.git" "$R/repo" 2>/dev/null
g() { git -C "$R/repo" -c user.name=t -c user.email=t@t "$@"; }
g commit -q --allow-empty -m base
g push -q origin main
land() {
	g worktree add -q -b "$1" "$R/$1" main && echo "$1" >"$R/$1/$1" && git -C "$R/$1" add "$1" &&
		git -C "$R/$1" -c user.name=t -c user.email=t@t commit -q -m "$1" && git -C "$R/repo" -c user.name=merger -c user.email=m@m cherry-pick "$1" >/dev/null
}
age() { python3 -c 'import os,sys,time; t=time.time()-3*3600; [os.utime(p,(t,t)) for p in sys.argv[1:] if os.path.exists(p)]' "$@"; }
idle() { d=$(git -C "$R/$1" rev-parse --absolute-git-dir); age "$d/index" "$d/HEAD" "$d/logs/HEAD"; }
land wt-idle && idle wt-idle
land wt-active
land wt-dirty && echo x >"$R/wt-dirty/edit" && idle wt-dirty
land wt-locked && g worktree lock "$R/wt-locked" && idle wt-locked
g push -q origin main
g branch br-empty main
g worktree add -q -b br-unmerged "$R/br-unmerged" main && git -C "$R/br-unmerged" -c user.name=t -c user.email=t@t commit -q --allow-empty -m mine
g worktree remove "$R/br-unmerged"
branches() { g for-each-ref --format='%(refname:short)' refs/heads/ | tr '\n' ' '; }
prune() { PATH="$fakebin:$PATH" bash "$H/../tools/prune-merged.sh" "$R/repo"; }
printf '#!/bin/sh\nexit 1\n' >"$fakebin/gh" && chmod +x "$fakebin/gh"

prune
if [ "$(branches)" = "br-empty br-unmerged main wt-active wt-dirty wt-locked " ] && [ ! -d "$R/wt-idle" ] && [ -d "$R/wt-active" ]; then
	ok 'auto-prune removes a landed idle worktree and keeps active, dirty, locked, unmerged and fresh empty ones'
else
	ko "auto-prune removes a landed idle worktree and keeps active, dirty, locked, unmerged and fresh empty ones (left: $(branches))"
fi

printf '#!/bin/sh\necho "$1" >>"%s"\ngit worktree remove "%s/$1"\n' "$R/removed" "$R" >"$R/remover.sh"
g config factory.worktreeRemove "sh $R/remover.sh"
FACTORY_PRUNE_NOW=$(( $(date +%s) + 90000 )) prune
if [ "$(branches)" = "br-unmerged main wt-dirty wt-locked " ] && [ "$(cat "$R/removed")" = wt-active ] && [ -d "$R/wt-dirty" ]; then
	ok 'auto-prune removes empty branches after a day and runs the repo remover for each worktree'
else
	ko "auto-prune removes empty branches after a day and runs the repo remover for each worktree (left: $(branches))"
fi

FACTORY_AUTO_PRUNE=0 FACTORY_PRUNE_NOW=$(( $(date +%s) + 90000 )) prune
g worktree unlock "$R/wt-locked"
FACTORY_AUTO_PRUNE=0 FACTORY_PRUNE_NOW=$(( $(date +%s) + 90000 )) prune
if [ -d "$R/wt-locked" ]; then ok 'auto-prune does nothing when FACTORY_AUTO_PRUNE=0'; else ko 'auto-prune does nothing when FACTORY_AUTO_PRUNE=0'; fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
