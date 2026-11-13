---
name: interrogate
description: "Use for \"interrogate\", \"adversarial review\", \"multi-model review\", \"challenge this\", \"stress test this code\", \"find blind spots\", or \"tear this apart\". Adversaries try to break a change or design, and only findings proven by a run survive."
disable-model-invocation: true
---

# Interrogate

Adversaries try to break a change or a design. A finding survives only when a run proves it. Report the findings. Do not apply fixes.

## Frame

The scope is what the user names. Otherwise it is the branch diff from its merge base with the base branch, through the working tree. State the intent with the **in-your-own-words** skill, from the user's message, the commits, and the PR description. Ask the user when the intent is unclear.

## Fan out

Run Phase A steps 3 and 4 and Phase B of the **arena** skill, with three changes. Copy the scope's uncommitted changes into each worktree. Arena's Grok runner rule does not apply here. The Grok seat below replaces it. In place of the arena task and rationale, give each adversary the scope, the intent, and this brief:

> Break this change. Prove each finding with a run against the real code, such as a failing test, a repro script, or command output that shows the wrong behavior. For a design or plan, run a prototype or probe the current tree. Keep repros in your own worktree. Report each finding with a title, the exact command, the output it printed, and the output the intent requires. Leave out anything you did not run. That covers style, naming, structure, and risks that need a future change to matter. No findings is a valid result.

**Grok seat (opt-in).** When the environment sets `FACTORY_GROK_SEAT=1`, add one adversary on `factory-reviewer-grok`. It relays the brief to the local `grok` CLI through `tools/grok-review.sh`. Grok has no tools and sees only what the script sends: the commits, diff and changed files of one committed range, or a list of text files. So the brief names the repository directory and either the `BASE..HEAD` range or the files under review, and asks for the command that would prove each finding and the output it expects, in place of a run. When the subject is neither, or the seat reports itself unavailable, continue without it and name the absence in the output.

Seats A, B and C are all Anthropic models, so agreement among them is weaker evidence than a cross-family panel. A finding the Grok seat and an Anthropic seat both reach is cross-family agreement.

## Verify

Verify each finding per arena Phase F by rerunning its command. For a Grok finding, run the command it proposed. Keep a finding when the output shows the failure and the failure breaks the intent. Drop the rest. Merge findings that share a root cause.

Skip arena Phases C, D, and E. Adversaries find different failures, so the verdict keeps every verified finding, not one adversary's list.

## Output

- **Intent**: the restatement.
- **Findings**: for each verified finding, the command, its output, how it breaks the intent, and the adversaries that found it. Say "no verified findings" when none survive.
- **Dropped**: for each adversary, the count of dropped findings and why.
