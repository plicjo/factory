---
name: principle-laziness-protocol
description: "Apply to any code change, and especially when refactoring, evaluating diff size, or tempted to add abstractions, layers, or signal threading. Bias toward deletion, reuse, and the smallest change that solves the problem."
disable-model-invocation: true
user-invocable: false
---

# Laziness Protocol

- **Reuse before you build.** Before writing new code, look for an existing feature, model, or framework built-in that already does the job. Extend the existing modal. Use nested attributes instead of hand-rolled saves.
- **Consolidate decisions.** Do not repeat the same choice in several places. Put it behind one source of truth and pass the result as a simple flag.
- **Minimize the diff.** Make the smallest change that solves the problem. Fewer lines beat "elegant" boilerplate.
