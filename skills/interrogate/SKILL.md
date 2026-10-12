---
name: interrogate
description: "Use for \"interrogate\", \"adversarial review\", \"multi-model review\", \"challenge this\", \"stress test this code\", \"find blind spots\", or \"tear this apart\". Multiple LLM reviewers challenge changes from independent angles."
disable-model-invocation: true
---

# Interrogate

Spawn one reviewer per configured model to adversarially review code changes. The adversarial signal comes from model diversity, not assigned personas. The deliverable is a synthesized verdict. Do NOT auto-apply changes.

## Step 1, Scope

Identify what to review from context:

- If the user points at specific files or a diff, use that.
- If on a feature branch, run `git diff main...HEAD` (or the appropriate base branch) for the full changeset.
- If the user's message references recent work, gather the relevant files.

Package the diff or file contents with any surrounding context files the reviewers need to understand the code.

## Step 2, Intent

Before spawning reviewers, state the intent in one clear paragraph from the user's message, commit messages, the PR description if one exists, and the code. If you're unsure about the intent, ask the user before proceeding.

## Step 3, Spawn Reviewers

Launch all reviewers in a single message using the Agent tool, one per seat.
Never pass `model`, it lives in each agent's definition under `agents/`.

| Seat | Agent |
|------|-------|
| Reviewer A | `factory-reviewer-a` |
| Reviewer B | `factory-reviewer-b` |
| Reviewer C | `factory-reviewer-c` |

**Fable seat (opt-in).** Seat A is `factory-reviewer-a`. When the environment sets `FACTORY_FABLE_SEAT=1`, spawn `factory-reviewer-fable` with the same brief in place of `factory-reviewer-a`. If it fails with "requires usage credits", respawn on `factory-reviewer-a` and use it for seat A for the rest of the session. Extra seats that reuse seat A go to `factory-reviewer-a`, never to the Fable agent.

**Grok seat (opt-in).** When the environment sets `FACTORY_GROK_SEAT=1`, add seat D on `factory-reviewer-grok`. It relays the same filled brief to the local `grok` CLI through `tools/grok-review.sh`. Grok has no tools and reviews only the commits, diff and changed files of one committed range, so the brief must name the repository directory and the `BASE..HEAD` range. When the subject is not a committed range, or the seat reports itself unavailable, continue with the Anthropic seats and name the absence in the verdict. Agreement between the Grok seat and any Anthropic seat is cross-family agreement. Weight it above agreement among the Anthropic seats.

Add a fourth or fifth seat by reusing these agents when the design is
contested enough to warrant it.

Unless the Grok seat is active, seats A and B run the same model at the same effort and only seat C differs, by model. That makes
agreement between them weaker evidence than upstream's cross-family panel.
Treat a concrete reproducible defect from one seat as outranking agreement
between the other two, and say so in the verdict when the panel splits that way.

Read `references/reviewer-prompt.md` and fill in the same template for every reviewer with the stated intent, the diff or file contents, the rubric from `references/rubric.md`, and the code-quality lens from `references/code-quality-review.md`.

## Step 4, Synthesize

As results come back, build a unified picture. Parse every reviewer's findings. Merge findings that describe the same issue differently, and note which models raised each one. Findings two or more models raised independently are the highest signal. Agreement between the Grok seat and any Anthropic seat is cross-family and the highest-signal consensus. Read a lone model's finding, but weight it accordingly. Note disagreements. If one model flags something and another explicitly says the opposite, that is context for the verdict.

## Step 5, Lead Judgment

You are the lead reviewer, a pragmatic senior engineer, not a neutral aggregator. Read `references/lead-judgment.md` for the full framework. Put every finding in one of four buckets, with the model(s) that raised it and a one-line rationale.

- **Act on**. Real issues affecting correctness, security, or maintainability given the actual goals. They would block a real PR.
- **Consider**. Legitimate, but you're not sure they outweigh the cost of addressing them now. Worth the user's attention.
- **Noted**. Technically valid but not actionable. Context-dependent, premature optimization, or low-impact at this stage.
- **Dismissed**. Wrong, nitpicky, or missing context, with a brief reason.

## Output Format

### Intent
> [The stated intent paragraph from Step 2]

### Reviewers
- Reviewer [label]: [model name], [N findings] (one bullet per reviewer)

### Act On
[Each: description, which models raised it, why it matters.]

### Consider
[Each: description, which models raised it, the tradeoff.]

### Noted
[Brief list.]

### Dismissed
[Each with a brief rationale.]

### Agreement Map
[Where models agreed and diverged, and what that pattern tells us.]
