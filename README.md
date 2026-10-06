# factory

My agent workflow stack. Forked from [pstack](https://github.com/cursor/plugins/tree/main/pstack)
by Lauren Tan (poteto), MIT licensed, last synced at pstack 0.15.15 (cursor/plugins@df58112, the `BASE` in `upstream-log.sh`).
Diverged since; not a mirror.
The `deslop` skill comes from cursor-team-kit in the same repo, also MIT licensed.

Packaged as a Claude Code plugin. Grok Build (1.0.46 or later) reads the same format with no changes:

    grok plugin install <path-to-this-repo>

A local-path install is a symlink, so edits are live. A git-URL install is a copy; run `grok plugin update` to refresh it.

## Install

    claude plugin marketplace add plicjo/factory
    claude plugin install factory@factory

Then, in each project you use factory in, run `/create-verification-skill` once. It writes
`.claude/skills/verify-<app>/`, a project skill that teaches agents to launch and drive your app,
so they can prove a change works on the real app instead of claiming it.

## Checking what upstream has done since

    ./upstream-log.sh
