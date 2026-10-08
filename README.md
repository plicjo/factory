# factory

My agent workflow stack. Forked from [pstack](https://github.com/cursor/plugins/tree/main/pstack)
by Lauren Tan (poteto), MIT licensed, last synced at pstack 0.15.15 (cursor/plugins@df58112, the `BASE` in `upstream-log.sh`).
Diverged since; not a mirror.
The `deslop` skill comes from cursor-team-kit in the same repo, also MIT licensed.

Packaged as a Claude Code plugin. Grok Build (1.0.46 or later) reads the same format with no changes.

## Install

    claude plugin marketplace add plicjo/factory
    claude plugin install factory@factory

## Run from a local clone

Clone the repo, then point your agent at the checkout.

    git clone https://github.com/plicjo/factory.git ~/projects/factory

**Claude Code.** Load the plugin straight from the checkout for one session:

    claude --plugin-dir ~/projects/factory

Edits to skills, agents and hooks take effect the next time you start `claude` with that flag.
Uninstall the marketplace copy first (`claude plugin uninstall factory@factory`) so the two don't both load.

**Grok Build.** Install from the local path:

    grok plugin install ~/projects/factory

A local-path install is a symlink, so edits are live. A git-URL install is a copy; run `grok plugin update` to refresh it.

## Set up each project

Then, in each project you use factory in, run `/create-verification-skill` once. It writes
`.claude/skills/verify-<app>/`, a project skill that teaches agents to launch and drive your app,
so they can prove a change works on the real app instead of claiming it.

## Checking what upstream has done since

    ./upstream-log.sh
