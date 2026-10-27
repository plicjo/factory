# factory

My agent workflow stack, packaged as a Claude Code plugin. Forked from [pstack](https://github.com/cursor/plugins/tree/main/pstack)
by Lauren Tan (poteto), MIT licensed, last synced at pstack 0.15.34 (cursor/plugins@519d36a, the `BASE` in `upstream-log.sh`).
Diverged since; not a mirror. [FORKS.md](FORKS.md) records every intentional divergence.
The `deslop` skill comes from cursor-team-kit in the same repo, also MIT licensed (`LICENSE-cursor-team-kit`).

This is a personal setup, loaded from a checkout. It has no marketplace entry and no versions. For pstack itself in Claude Code, install upstream's `pstack@cursor-plugins`.

## Install

    git clone https://github.com/plicjo/factory.git ~/projects/factory
    claude --plugin-dir ~/projects/factory

Edits to skills, agents and hooks take effect the next time `claude` starts with that flag. Wrap the command in a shell alias per profile, with that profile's `CLAUDE_CONFIG_DIR` and environment flags.

## Quick start

Type `/factory-mode` followed by your task. The mode matches the task to one of
[22 playbooks](skills/factory-mode/playbooks/) (feature, bug fix, investigation, babysit,
shipping, autopilots, and more), copies the playbook's steps into a todo list, and names the
principles that shaped each decision in its reply. A hook keeps the mode on for the rest of
the session; say "exit factory mode" to turn it off.

In each project, run `/create-verification-skill` once so agents can launch and drive the app.

## Layout

- `skills/` holds the workflow skills, the [playbooks](skills/factory-mode/playbooks/) and the principle skills. The principles stay out of the slash menu.
- `agents/` pins each role's model, effort, tools and isolation, so a playbook picks a role and never passes a model.
- `hooks/` keeps factory-mode on for the session, runs long Bash commands in the background, reminds panels to add the opt-in seats, and prunes landed branches at session start. `hooks/tests/run.sh` tests them.

## Environment flags

| Flag | Effect |
|---|---|
| `FACTORY_GROK_SEAT=1` | Adds the cross-family Grok seat to review panels, architect sketches and text arenas. Needs the `grok` CLI, installed and authenticated. |
| `FACTORY_GROK_EFFORT`, `FACTORY_GROK_TIMEOUT` | Grok reasoning effort and time limit in seconds. Keep the timeout under 600. |
| `FACTORY_FABLE_SEAT=1` | Runs review seat A on Fable, with a fallback to `factory-reviewer-a`. |
| `FACTORY_ALLOW_LONG_FOREGROUND=1` | Allows Bash calls over two minutes in the foreground. |
| `FACTORY_AUTO_PRUNE=0` | Turns off the session-start branch and worktree prune. |

A `Bash(grok *)` permissions deny rule blocks the Grok CLI outright where code must not leave Anthropic. The prune logs to `.git/factory-prune.log`, and `tools/prune-merged.sh --dry-run` previews it. Set `git config factory.worktreeRemove '<command>'` when a repo removes worktrees its own way.

## Syncing upstream

    ./upstream-log.sh

It lists upstream commits since the sync base. After a sync, bump the snapshot SHA in `FORKS.md` and run `python3 tools/check-forks.py`. CI runs that check, the hook tests, a dangling-reference and Cursor-term check, and the watch-pr tests.
