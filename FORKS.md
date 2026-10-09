# Forks

This file records every intentional divergence from upstream pstack.

- Upstream is `pstack/` in [cursor/plugins](https://github.com/cursor/plugins).
- The recorded sync base is `df581122cde17e6e27686b5a448bde23e4ad4318`, the `BASE` in `upstream-log.sh`.
- The compared snapshot is `ccb5507cec1546dc88135c1139c811e6c59115ba`, the upstream head when this file was written.
- A file absent from the tables below matches upstream apart from the name substitutions. `poteto-mode` is `factory-mode`, `poteto-agent` is `factory-agent`, and prose says factory instead of poteto.
- The `deslop` skill is vendored from cursor-team-kit, not pstack. Its license is in `LICENSE-cursor-team-kit`.
- A PR that changes a ported file, or adds or drops one, updates its row here. The `forks` CI job runs `tools/check-forks.py` and fails on an undeclared divergence. After a sync, bump the snapshot SHA above and rerun it.

## Dropped

Upstream files not ported. Paths are upstream paths.

| Path | Reason |
|---|---|
| `.cursor-plugin/plugin.json` | Cursor plugin manifest. `.claude-plugin/` replaces it. |
| `automations/benny/` | Cursor automations for Slack issue reports. Nothing here runs them. |
| `skills/poteto-help/` | Onboarding help for pstack. The guide covers setup here. |
| `skills/setup-pstack/` | Wrote a Cursor model rule. Models now live in each agent definition under `agents/`. |
| `skills/make-bot-ui/` | Builds UIs for Cursor's automation webhook and Grok Bot, which Claude Code cannot run. |
| `skills/poteto-mode/playbooks/orchestrate.md` | Coordinator playbook built on Cursor cloud agents and the Cursor dashboard, with 2,819 lines of `orch` store tooling. Autopilot-full, autopilot-stack and multi-phase-plan cover that scale here. Port from upstream head if a program-scale need appears. |
| `skills/poteto-mode/scripts/orch/` | The orchestrate playbook's store tooling. Dropped with it. |

## Added

Files with no upstream counterpart.

| Path | Reason |
|---|---|
| `.claude-plugin/` | Claude Code plugin and marketplace manifests. |
| `agents/factory-code.md` | Standard code delegate with its model and effort pinned. |
| `agents/factory-hard.md` | Delegate for the hardest changes. |
| `agents/factory-explorer.md` | Read-only explorer for `how` and `why`. |
| `agents/factory-synthesizer.md` | Read-only synthesis seat for `how`, `why` and `reflect`. |
| `agents/factory-reviewer-a.md` | Review panel seat A. |
| `agents/factory-reviewer-b.md` | Review panel seat B. |
| `agents/factory-reviewer-c.md` | Review panel seat C. |
| `agents/factory-reviewer-fable.md` | Seat A on Fable, with `factory-reviewer-a` as the fallback. |
| `agents/factory-worker.md` | Swarm worker that isolates into its own git worktree. |
| `hooks/hooks.json` | Registers the Claude Code hooks. |
| `hooks/factory-mode-reminder.sh` | Keeps factory-mode on for the whole session. |
| `hooks/background-long-commands.sh` | Runs long Bash commands in the background. |
| `hooks/tests/run.sh` | Tests both hooks. |
| `.github/workflows/ci.yml` | Runs the hook tests, the watch-pr tests and typecheck, and the port checks. |
| `tools/check-references.py` | Fails CI on dangling markdown references. |
| `tools/check-forks.py` | Fails CI when the repo diverges from upstream without a row here. |
| `upstream-log.sh` | Lists upstream commits since the sync base. |
| `skills/deslop/SKILL.md` | Vendored from cursor-team-kit. Upstream pstack points at that plugin instead. |
| `LICENSE-cursor-team-kit` | MIT license for the vendored `deslop` skill. |
| `FORKS.md` | This file. |

## Modified

Ported files with content changes beyond the name substitutions.

| Path | Reason |
|---|---|
| `README.md` | Rewritten for Claude Code install, with a fork notice and the sync base. |
| `docs/guide/` (all 10 chapters and the index) | Rewritten for Claude Code. Setup, model choice, `factory-help`, and Cursor-only automation material are cut. |
| `skills/factory-mode/SKILL.md` | Adds the sticky rule and the named-skill fallback. Subagents section names the `factory-*` agents and the Fable seat. Drops the Orchestrate playbook and the Cursor-only triggers. |
| `agents/factory-agent.md` | Claude frontmatter for background, model, effort and the preloaded skill. |
| `agents/comment-sicko.md` | Name lowercased to match Claude agent naming. |
| `skills/principle-*/SKILL.md` (all 24) | `user-invocable: false` hides them from the slash menu. |
| `skills/principle-laziness-protocol/SKILL.md` | Adds the reuse rule and widens the trigger to any code change. |
| `skills/principle-fix-root-causes/SKILL.md` | Adds two bullets on guards and downstream patches. |
| `skills/principle-test-behavior-not-implementation/SKILL.md` | Adds the framework and real-data rules. |
| `skills/principle-sequence-verifiable-units/SKILL.md` | Delivery guidance says one commit per PR. |
| `skills/how/SKILL.md`, `skills/why/SKILL.md`, `skills/swarm/SKILL.md` | Spawns name `factory-explorer`, `factory-synthesizer` or `factory-worker` instead of model lines. |
| `skills/architect/SKILL.md`, `skills/arena/SKILL.md`, `skills/interrogate/SKILL.md`, `skills/reflect/SKILL.md` | Panel seats run on `factory-reviewer-a`, `-b` and `-c`. The text says same-vendor agreement is weaker evidence. |
| `skills/reflect/references/` (`divergent-reviewer.md`, `judgment-reviewer.md`, `synthesizer.md`, `tooling-reviewer.md`) | Claude skill paths, and the `authoring-a-skill` playbook replaces `create-skill`. |
| `skills/factory-mode/playbooks/opening-a-pr.md` | One PR is one commit, force-push with lease, capitalized `Type(scope): Subject` titles, and `deslop` by name. |
| `skills/factory-mode/playbooks/bug-fix.md`, `feature.md`, `hillclimb.md`, `perf-issue.md`, `refactoring.md` | Delegation goes to `factory-code` or `factory-hard`. Feature, Hillclimb and Refactoring squash to one commit. |
| `skills/factory-mode/playbooks/autopilot-full.md`, `autopilot-stack.md`, `shipping.md` | Owners are `factory-worker` agents in git worktrees. Control skills become `verify-*` skills. |
| `skills/factory-mode/playbooks/autonomous-run.md` | Uses the Claude Code `/loop` command and `AskUserQuestion`. |
| `skills/factory-mode/playbooks/authoring-a-skill.md` | Replaces Cursor's `create-skill` with the `skills/<name>/SKILL.md` layout. |
| `skills/factory-mode/playbooks/babysit.md` | Drops the Cursor built-in babysit note and the Bugbot step. |
| `skills/factory-mode/playbooks/multi-phase-plan.md` | Plugin-relative paths, `verify-*` skills, worktree lanes, and review-bot wording. |
| `skills/factory-mode/playbooks/eval.md`, `session-pickup.md` | Reads Claude Code sessions under `~/.claude/projects/`. |
| `skills/factory-mode/references/bugbot-triage.md` | Names the review bot generically instead of Bugbot. |
| `skills/factory-mode/scripts/worktree-audit.sh` | Finds sessions under `~/.claude/projects/`. |
| `skills/factory-mode/scripts/package.json`, `bun.lock` | The package is `factory-mode-tools` and the test script drops `orch`. |
| `skills/recall/SKILL.md`, `skills/show-me-your-work/SKILL.md` | Read Claude Code sessions, and `recall` fans out to `factory-explorer`. |
| `skills/automate-me/SKILL.md` | Claude paths, `AskUserQuestion`, and the authoring playbook instead of `create-skill`. |
| `skills/no-comments/SKILL.md` | Spawns `factory:comment-sicko` through the `Agent` tool. |
| `skills/create-verification-skill/SKILL.md`, `skills/maintain-verification-skill/SKILL.md` | Verify skills live under `.claude/skills/`. |
