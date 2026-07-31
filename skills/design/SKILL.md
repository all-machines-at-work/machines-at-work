---
name: design
description: Produce a concrete UI/UX design for one task before implementation. For user-facing tasks.
argument-hint: "<task-id>"
---

Write `machines-at-work/tasks/<id>-<slug>/design.md` for task $ARGUMENTS. The implementer will follow it literally — be concrete, not aspirational. If the task's `Resources:` field lists files, Read them first (images too): a referenced mockup is the design's starting point — interpret it, don't override it.

Before speccing any component, inventory what exists (shared widget dirs, sibling screens): per component, name the existing widget to reuse or extend, or say why none fits. A new variant of an existing component is a recorded decision, never a default.

Cover, tersely:
1. Layout: components, hierarchy, spacing (ASCII sketch beats prose).
2. Visual language: colors (exact values), type scale, radii — consistent with the existing app (read it first).
3. States: empty, loading, error, success.
4. Interactions: what happens on click/hover/keyboard; motion only if it carries meaning.
5. One deliberate, fresh touch that elevates the design above the default — named explicitly so the implementer builds it. Spend it inside this design, never on a parallel variant of an existing component.

≤60 lines. No mood boards, no alternatives — decide.
