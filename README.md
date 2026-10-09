# factory

My agent workflow stack, packaged as a Claude Code plugin. Forked from [pstack](https://github.com/cursor/plugins/tree/main/pstack)
by Lauren Tan (poteto), MIT licensed, last synced at pstack 0.15.15 (cursor/plugins@df58112, the `BASE` in `upstream-log.sh`).
Diverged since; not a mirror. [FORKS.md](FORKS.md) records every intentional divergence.
The `deslop` skill comes from cursor-team-kit in the same repo, also MIT licensed (`LICENSE-cursor-team-kit`).

## Install

    claude plugin marketplace add plicjo/factory
    claude plugin install factory@factory

## Quick start

Type `/factory-mode` followed by your task. The mode matches the task to one of
[22 playbooks](skills/factory-mode/playbooks/) (feature, bug fix, investigation, babysit,
shipping, autopilots, and more), copies the playbook's steps into a todo list, and names the
principles that shaped each decision in its reply. A hook keeps the mode on for the rest of
the session; say "exit factory mode" to turn it off.

## Run from a local clone

Clone the repo, then point your agent at the checkout.

    git clone https://github.com/plicjo/factory.git ~/projects/factory

**Claude Code.** Load the plugin straight from the checkout for one session:

    claude --plugin-dir ~/projects/factory

Edits to skills, agents and hooks take effect the next time you start `claude` with that flag.
Uninstall the marketplace copy first (`claude plugin uninstall factory@factory`) so the two don't both load.

## Set up each project

Then, in each project you use factory in, run `/create-verification-skill` once. It writes
`.claude/skills/verify-<app>/`, a project skill that teaches agents to launch and drive your app,
so they can prove a change works on the real app instead of claiming it.

## What's inside

**49 skills.** 25 workflow skills you can invoke directly, such as `/how`, `/why`, `/architect`,
`/arena`, `/interrogate`, `/swarm`, `/tdd`, `/unslop` and `/deslop`, plus 24 principle skills
that factory-mode reads by path and cites in replies. The principles stay out of the slash menu.

**12 agents.** Each agent file pins its model, reasoning effort, tool limits and isolation, so a
playbook picks a role and never passes a model.

| Agent | Role | Model and effort |
|---|---|---|
| `factory-agent` | Routing wrapper for `/factory-mode` tasks | Opus, max |
| `factory-code` | Standard code delegate | Sonnet, high |
| `factory-hard` | Hardest changes, where a mistake is expensive | Opus, max |
| `factory-explorer` | Read-only exploration | Sonnet, high |
| `factory-synthesizer` | Read-only prose and judgment | Opus, max |
| `factory-reviewer-a` / `-b` / `-c` | Review panel seats | Opus max, Opus high, Sonnet high |
| `factory-reviewer-fable` | Seat A on accounts with Fable access | Fable, max |
| `factory-reviewer-grok` | Opt-in cross-family seat via the local grok CLI | Haiku transport, Grok 4.7 does the reviewing |
| `factory-worker` | Swarm worker, isolated in its own git worktree | Sonnet, high |
| `comment-sicko` | Comment reviewer for `/no-comments` | inherits |

Review seat A tries `factory-reviewer-fable` first and falls back to `factory-reviewer-a` without
Fable access. By default every seat is an Anthropic model, so the skills weight a concrete reproducible
defect over panel consensus.

The Grok seat is opt-in. Set `FACTORY_GROK_SEAT=1` and install and authenticate the `grok` CLI to add it. Environments that must not send code to non-Anthropic vendors simply never set the flag, and a `Bash(grok *)` permissions deny rule can block the CLI outright.

**2 hooks.** One keeps factory-mode sticky for the session. The other moves long Bash commands
to the background: a foreground call with a timeout over two minutes is denied and the agent
reruns it with `run_in_background`, so a long test run never locks you out of the conversation.
`hooks/tests/run.sh` tests both.

## CI

Four jobs run on every PR and push to main:

- `hooks` runs the 22 hook tests.
- `port` fails on a markdown reference to a missing file and on banned Cursor-era terms.
- `forks` fetches upstream at the SHA pinned in `FORKS.md` and fails on an undeclared divergence.
- `scripts` runs the watch-pr watcher's tests and typecheck under bun.

## Long commands run in the background

A Bash call with a timeout over two minutes is denied in the foreground, and the denial tells the
agent to rerun the same command in the background. A long test suite, a CI watch, or a polling
loop then runs while you keep talking to the agent, and the agent is told when the command exits.
To allow long foreground runs, start `claude` with `FACTORY_ALLOW_LONG_FOREGROUND=1`.

## Checking what upstream has done since

    ./upstream-log.sh

It lists upstream commits since the sync base and names the fork-registry reconcile step.

## Docs

The [10-chapter guide](docs/guide/) walks the whole stack: setup, factory-mode, the understand
and design skills, building, verifying, overnight runs, principles, and customization.
