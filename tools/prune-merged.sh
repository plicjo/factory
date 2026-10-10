#!/usr/bin/env bash
# Removes local branches and worktrees that can no longer hold unique work. A branch is landed when every
# commit has an equivalent on the base branch, or a merged PR's head is its exact tip. It is empty when it
# has no commits past the base. A worktree goes only when it is clean, unlocked, not the caller's checkout,
# and idle: an hour for a landed branch, a day for an empty one, since a subagent's fresh worktree is empty too.
# A repo can name its own remover, which receives the branch name:
#   git config factory.worktreeRemove 'bin/worktree remove'
# Usage: prune-merged.sh [--dry-run] [repo-path]. FACTORY_AUTO_PRUNE=0 turns it off.
set -uo pipefail

dry=0
[[ "${1:-}" == "--dry-run" ]] && { dry=1; shift; }
[[ "${FACTORY_AUTO_PRUNE:-1}" == "0" ]] && exit 0

caller=$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
common=$(cd "$caller" && cd "$(git rev-parse --git-common-dir)" && pwd)
main_wt=$(git -C "$caller" worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
now=${FACTORY_PRUNE_NOW:-$(date +%s)}
log="$common/factory-prune.log"

lock="$common/factory-prune.lock"
if ! mkdir "$lock" 2>/dev/null; then
  [[ -n $(find "$lock" -maxdepth 0 -mmin +60 2>/dev/null) ]] || exit 0
  rm -rf "$lock" && mkdir "$lock" || exit 0
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT

git -C "$main_wt" fetch --quiet origin 2>/dev/null
base=$(git -C "$main_wt" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
for b in "$base" origin/main origin/master main master; do
  [[ -n "$b" ]] && git -C "$main_wt" rev-parse --verify --quiet "$b^{commit}" >/dev/null && { base=$b; break; }
done
git -C "$main_wt" rev-parse --verify --quiet "$base^{commit}" >/dev/null || exit 0
base_local=${base#origin/}

merged_heads=$(cd "$main_wt" && command -v gh >/dev/null &&
  gh pr list --state merged --limit 200 --json headRefName,headRefOid \
    -q '.[] | "\(.headRefName) \(.headRefOid)"' 2>/dev/null)

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

state_of() {
  local branch=$1 tip ahead
  tip=$(git -C "$main_wt" rev-parse "refs/heads/$branch")
  ahead=$(git -C "$main_wt" rev-list --count "$base..$tip")
  if [[ "$ahead" -eq 0 ]]; then echo empty
  elif ! git -C "$main_wt" cherry "$base" "$tip" | grep -q '^+'; then echo landed
  elif grep -qx "$branch $tip" <<<"$merged_heads"; then echo landed
  else echo unmerged; fi
}

# Prints "prune" or "keep <reason>" for one branch, with its worktree path when it has one.
decide() {
  local branch=$1 wt=$2 state idle last grace
  [[ "$branch" == "$base_local" ]] && { echo "keep base branch"; return; }
  state=$(state_of "$branch")
  [[ "$state" == unmerged ]] && { echo "keep unmerged commits"; return; }
  if [[ -n "$wt" ]]; then
    [[ "$wt" == "$main_wt" || "$wt" == "$caller" ]] && { echo "keep checked out here"; return; }
    [[ -d "$wt" ]] || { echo "keep worktree missing"; return; }
    local gitdir; gitdir=$(git -C "$wt" rev-parse --absolute-git-dir)
    [[ -f "$gitdir/locked" ]] && { echo "keep locked"; return; }
    last=0
    for f in "$gitdir/index" "$gitdir/HEAD" "$gitdir/logs/HEAD"; do
      [[ -e "$f" ]] && (( $(mtime "$f") > last )) && last=$(mtime "$f")
    done
    # A plain status refreshes the index, which would make every worktree look active.
    [[ -n $(git --no-optional-locks -C "$wt" status --porcelain 2>/dev/null) ]] && { echo "keep uncommitted changes"; return; }
  else
    last=$(git -C "$main_wt" reflog show --format=%ct -n1 "refs/heads/$branch" 2>/dev/null)
    [[ -n "$last" ]] || last=$(git -C "$main_wt" log -1 --format=%ct "refs/heads/$branch")
  fi
  idle=$(( now - last ))
  [[ "$state" == landed ]] && grace=3600 || grace=86400
  (( idle < grace )) && { echo "keep $state but active $(( idle / 60 ))m ago"; return; }
  echo prune
}

remove() {
  local branch=$1 wt=$2 remover
  if [[ -n "$wt" ]]; then
    remover=$(git -C "$main_wt" config --get factory.worktreeRemove)
    if [[ -n "$remover" ]]; then
      (cd "$main_wt" && sh -c "$remover \"\$1\"" _ "$branch") >/dev/null 2>&1 || return 1
    else
      git -C "$main_wt" worktree remove "$wt" || return 1
    fi
  fi
  if git -C "$main_wt" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$main_wt" branch -D "$branch" >/dev/null
  fi
}

git -C "$main_wt" worktree prune
worktrees=$(git -C "$main_wt" worktree list --porcelain |
  awk '/^worktree /{wt = substr($0, 10)} /^branch refs\/heads\//{print substr($0, 19) "\t" wt}')

for branch in $(git -C "$main_wt" for-each-ref --format='%(refname:short)' refs/heads/); do
  wt=$(awk -F '\t' -v b="$branch" '$1 == b {print $2; exit}' <<<"$worktrees")
  verdict=$(decide "$branch" "$wt")
  if (( dry )); then
    echo "$verdict: $branch${wt:+ ($wt)}"
  elif [[ "$verdict" == prune ]]; then
    if remove "$branch" "$wt"; then
      echo "$(date -u +%FT%TZ) pruned $branch${wt:+ ($wt)}" >>"$log"
    else
      echo "$(date -u +%FT%TZ) failed $branch${wt:+ ($wt)}" >>"$log"
    fi
  fi
done
