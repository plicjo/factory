# Set up factory

In this page you install the plugin and run your first task.

## Install the plugin

In a terminal, run:

```text
claude plugin marketplace add plicjo/factory
claude plugin install factory@factory
```

For Grok Build 1.0.46 or later, run `grok plugin install <path-to-this-repo>` instead.

There are no models to pick. Each agent under `agents/` sets its own model and reasoning effort, and the playbooks choose agents by role.

## Create a verification skill, or don't

Agents prove app behavior best with a project skill that drives your app the way a user does. Run [`/create-verification-skill`](../../skills/create-verification-skill/SKILL.md) to generate one at `.claude/skills/verify-<app>/`. It proves the skill works once before handing it over. [Verify and ship](./06-verify-and-ship.md#create-a-project-verification-skill) covers when it earns its place.

## Run your first task

Pick something real but small, and describe it the way you'd describe it to a colleague:

```text
/factory-mode add a --json flag to this command. text output stays byte-identical. verify both.
```

Watch the todo list. Its first items are the matched playbook's steps copied in, the Feature playbook for this prompt. If `/factory-mode` skips a step, the step stays in the list with `skip: <reason>`, so you can see what it chose not to do.

From here you can type normal follow-ups. `/factory-mode` is sticky. It stays on for the conversation until you opt out by saying so.

Next: [Route work through `/factory-mode`](./02-factory-mode.md).
