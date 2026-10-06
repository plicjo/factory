#!/usr/bin/env bash
# What has changed in upstream pstack since my last sync.
set -euo pipefail
BASE="df581122cde17e6e27686b5a448bde23e4ad4318"
DIR="${TMPDIR:-/tmp}/pstack-upstream"

if [ ! -d "$DIR" ]; then
  git clone -q --filter=blob:none --no-checkout \
    https://github.com/cursor/plugins.git "$DIR"
else
  git -C "$DIR" fetch -q origin main
fi

git -C "$DIR" log --oneline "$BASE..origin/main" -- pstack
echo
echo "diff a file:  git -C $DIR diff $BASE..origin/main -- pstack/skills/<name>/SKILL.md"
