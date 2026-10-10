#!/usr/bin/env bash
# Sweeps landed and empty branches and their clean worktrees at session start. The sweep fetches, so it runs
# detached and the session never waits on it. tools/prune-merged.sh holds the rules and logs what it removed.
set -uo pipefail

cwd=$(sed -n 's/.*"cwd" *: *"\([^"]*\)".*/\1/p' | head -n1)
[[ -n "$cwd" && -d "$cwd" ]] || cwd=$PWD

nohup bash "$(dirname "$0")/../tools/prune-merged.sh" "$cwd" >/dev/null 2>&1 &
exit 0
