---
name: reflect
description: Spawn three parallel review subagents over the active transcript, surface learnings, and route each to a concrete edit on an existing skill. Use when the user says reflect.
disable-model-invocation: true
---

# Reflect

Mine the current conversation for durable learnings, then route them into skill edits.

Invoke when the user says "reflect" or "/reflect". Skip when the conversation is trivial, off-topic, or already covered by an existing skill the parent followed correctly. One-offs are not learnings.

## 1. Locate the active transcript

The parent finds its own transcript file before fanning out. Sessions live in this project's session directory, `~/.claude/projects/<slug>/`, where `<slug>` is the repo's absolute path with every `/` turned into `-` (so `/Users/you/projects/app` becomes `-Users-you-projects-app`). Each `<uuid>.jsonl` file there is one session, one JSON object per line. Do not glob across `~/.claude/projects/*/`. That crosses project boundaries and reads private chats from unrelated projects.

```bash
ls -t ~/.claude/projects/<slug>/*.jsonl 2>/dev/null | head -10
```

That covers the legacy flat (`<id>.jsonl`), current nested (`<id>/<id>.jsonl`), and subagent (`<parent>/subagents/<child>.jsonl`) layouts. For each candidate, read the first JSONL line. Take the file whose `message.content[0].text` contains the conversation's opening user prompt. If none matches, pass a tight digest of the session instead.

## 2. Spawn three reviewers in parallel

One message, three `Agent` calls, one per lens, using the agent named below. Reviewers keep MCP access for context lookups (tickets, chat threads, observability traces referenced in the transcript); the read-only agents restrict `Write` and `Edit` only, so MCP tools stay available.

Never pass `model`. It lives in each agent's definition under `agents/`.

| Lens | Agent | Prompt template |
|---|---|---|
| Judgment | `factory-reviewer-a` | `references/judgment-reviewer.md` |
| Tooling | `factory-reviewer-c` | `references/tooling-reviewer.md` |
| Divergent | `factory-reviewer-b` | `references/divergent-reviewer.md` |

When the environment sets `FACTORY_GROK_SEAT=1`, run the Divergent lens on `factory-reviewer-grok`, passing the template and the transcript path inside the brief. Fall back to `factory-reviewer-b` when the seat reports itself unavailable.

Pass each template verbatim, substituting the transcript path or digest where marked. Reviewers return findings in the `Agent` response body.

## 3. Synthesize

One `Agent` call, `subagent_type: factory-synthesizer`. Use `references/synthesizer.md` verbatim, with each reviewer's full output inlined where marked. The synthesizer returns a structured Accepted / Rejected / Backlog list.

## 4. Structural enforcement check

Move any Accepted item that a lint rule, script, metadata flag, or runtime check would enforce more reliably to Backlog. See the **encode-lessons-in-structure** principle skill.

## 5. Apply

Present the synthesizer's full Accepted / Rejected / Backlog output and wait for explicit approval before applying any Accepted edit. The user picks the subset and may redirect routings. Skill changes affect every future agent in the org. Do not auto-apply.

File each Backlog item to your team's devex or backlog tracker without waiting. Only the Accepted list waits for approval.

Follow each approved row's Routing exactly:

- Trivial existing-skill edit (a one-line bullet, a tightened sentence, a stale fact corrected): parent does directly.
- Substantive existing-skill edit (a new section, a new pattern table, more than ~10 lines): follow `skills/factory-mode/playbooks/authoring-a-skill.md`.
- `tune description: <skill path>` (the skill exists but didn't trigger when it should have): follow `skills/factory-mode/playbooks/authoring-a-skill.md` and rewrite the description against the missed trigger.
- `new skill via authoring-a-skill: <kebab-name>`: follow `skills/factory-mode/playbooks/authoring-a-skill.md`. A new skill is a directory under `skills/` with a `SKILL.md`. Do not invent the shape ad hoc.

If your environment ships a SKILL.md validator, run it on every touched skill before declaring done.

## 6. Summarize for the user

Short list, no preamble:

- Edits applied: `<skill path>`. What changed, one line each.
- New skills created: `<skill path>`. One line each (rare).
- Backlog filed to the devex tracker: `<issue title>` (`<tags>`). One line each.
- Dropped: one line per rejected finding + reason from the synthesizer.
