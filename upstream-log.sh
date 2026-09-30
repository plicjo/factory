#!/usr/bin/env bash
# What has changed in upstream pstack since my snapshot.
set -euo pipefail
BASE="12d587dfb20741cafc376c42c696c5f6e2a64487"
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
