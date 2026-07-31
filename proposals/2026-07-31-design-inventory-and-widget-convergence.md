# Design 2026-07-31 · Similar-but-not-same widgets: inventory rule in /design, convergence findings in /cleanup

**Status:** applied · 2026-07-31 · v0.32.0
**Scope:** machines-at-work only (`skills/design/SKILL.md`, `skills/cleanup/SKILL.md`).

## Evidence / observation

The reuse pressure in the pipeline targets *exact* duplication: implementer rule 5 ("the function
may already exist"), reviewer duplication nits, and /cleanup's zero-reader/near-identical sweep.
None of it addresses the harder class: **similar-but-not-same widgets**. A task builds a bottom
sheet; a later task builds a slightly different bottom sheet. Neither "duplicates an existing
helper" — each is a new component that should probably have *been* the existing one. The variant
zoo grows one justified decision at a time, and every fresh-context session pays to read it.

Two structural causes:

- `/design` says "visual language consistent with the existing app (read it first)" but nothing
  makes it inventory existing *components* — so a design.md can spec a fresh sheet that is 90% of
  one that exists, and the implementer (who follows design.md literally) builds it.
- Per-task aesthetic guidance amplifies the drift: `/design`'s "one deliberate, fresh touch" — and,
  on projects that load an aesthetic skill like Anthropic's `frontend-design` ("take one real
  aesthetic risk") — is sound for one page, but one fresh touch *per task* across 50 fresh-context
  tasks accumulates fifty flourishes and parallel variants, each individually justified.

## Root cause

Reuse is enforced nowhere at the layer where variants are minted (design time), and /cleanup —
the only step that reads the codebase whole — was not asked to look for convergence candidates.

## Proposed change

**1. `/design` — inventory before inventing.** Before the "Cover, tersely" list:

> Before speccing any component, inventory what exists (shared widget dirs, sibling screens): per
> component, name the existing widget to reuse or extend, or say why none fits. A new variant of
> an existing component is a recorded decision, never a default.

And item 5's fresh touch is spent *inside* the design, never on a parallel variant of an existing
component. This makes reuse reviewable: the reviewer can check the built widget against an
explicit design.md statement instead of guessing intent.

**2. `/cleanup` — widget convergence is a normal finding.** Step 2 grows one clause: parallel
variants of the same UI concept (two sheets/cards/pickers that should be one widget) are swept
and reported like any other finding. A variant that looks deliberate is flagged as a judgement
call in the note — not silently skipped, not separately asked.

**Deliberately NOT a human-gated "observation" clause.** An earlier sketch had /cleanup surface
widget variants as questions ("converge or bless?") instead of findings. Rejected by the human
directly: the answer is always "converge", and the plan approval *already is* the gate — the note
flows through /plan, where striking a finding is exactly as expensive as answering a question.
Asking twice is noise (same reasoning as #5's write-only nits: don't create a second loop for a
decision an existing gate already owns).

## Risk

- **Over-consolidation.** The implementer's "no speculative abstractions" rule is load-bearing;
  a design.md that forces every near-match into one widget breeds `GenericSheet` frameworks. The
  rule asks /design to *name or justify*, not to unify at any cost — and convergence tasks from
  /cleanup stay behaviour-preserving under the standing constraints.
- **Design.md gets longer.** One line per component ("extends `AppSheet`") is the intended cost;
  the ≤60-line cap still holds.
- **A deliberate variant striked at plan time recurs next sweep.** Acceptable: the note's
  judgement-call flag plus the false-positive ledger convention ("checked and not dead — leave
  alone") is the place to record a blessed variant so the next sweep cites it instead of
  re-flagging.
