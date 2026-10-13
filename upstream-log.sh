#!/usr/bin/env bash
# What has changed in upstream pstack since my last sync.
set -euo pipefail
BASE="7845807642f9ef234a0ec5b4067fa3f11fd92a85"
DIR="${TMPDIR:-/tmp}/pstack-upstream"

if ! git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  rm -rf "$DIR"
  git clone -q --filter=blob:none --no-checkout \
    https://github.com/cursor/plugins.git "$DIR"
else
  git -C "$DIR" fetch -q origin main
fi

git -C "$DIR" log --oneline "$BASE..origin/main" -- pstack
echo
echo "diff a file:  git -C $DIR diff $BASE..origin/main -- pstack/skills/<name>/SKILL.md"
echo "after syncing, reconcile FORKS.md (bump its snapshot SHA, then):  python3 tools/check-forks.py"
