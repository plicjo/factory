# factory

My agent workflow stack. Forked from [pstack](https://github.com/cursor/plugins/tree/main/pstack)
by Lauren Tan (poteto), MIT licensed, last synced at pstack 0.15.15 (cursor/plugins@df58112, the `BASE` in `upstream-log.sh`).
Diverged since; not a mirror.

Packaged as a Claude Code plugin. Grok Build (1.0.46 or later) reads the same format with no changes:

    grok plugin install <path-to-this-repo>

A local-path install is a symlink, so edits are live. A git-URL install is a copy; run `grok plugin update` to refresh it.

## Install

    claude plugin marketplace add plicjo/factory
    claude plugin install factory@factory

## Checking what upstream has done since

    ./upstream-log.sh
