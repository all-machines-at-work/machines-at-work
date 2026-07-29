# Retro 2026-07-29 · The assertion is weaker than the criterion it is cited for

Proposal — **apply by hand in the machines-at-work repo** (the plugin is read-only inside projects;
move this into `machines-at-work/proposals/` when applying). Touches `agents/implementer.md` (rule
8) and `agents/reviewer.md` (the severity line).

## Evidence

The pipeline's contract is "every acceptance criterion demonstrably met (cite the test or command
that proves each)" (`implementer.md:8`). Repeatedly, the cited test proves something *adjacent* to
the criterion — measured on a convenient inner object, or covering part of what the criterion
claims — and the review reproduces the same blind spot because it re-derives from the same code.

**Task 0052 → 0053, the clean case.** 0052's AC3:

> "WHEN the keyboard is up on either surface THE SYSTEM SHALL leave **no strip of a different
> color** between the composer bar and the top edge of the keyboard."

The cited test asserted `getRect(_trayFill) == getRect(_blob)` — the fill matches *the blob*, an
inner widget of the composer. Review 0052 checked AC3 by reasoning, and reasoned downward:

> "the docked `AnimatedPadding` has no bottom padding — **no strip below the bar**. AC 3."

`no findings`, `VERDICT: approve`. The strip was **above** the fill: the blob sits inside an outer
`AnimatedPadding` that still applied `EdgeInsets.only(top: AppSpacing.sm)`, so ~8px of the
composer's own bounds showed the comment list through. Task 0053's Goal names the mechanism itself:

> "The existing test … pins the blob's left, right and bottom to the composer's bounds — **but not
> its top, which is why this slipped through.**"

0053 (14m30s, ~$1.91 API-equiv) exists only to close a criterion 0052 had already been credited
with. Its test asserts what AC3 always meant: `trayFill rect == TyfStickyComposer rect`, top
included — the rect of the thing the criterion names.

**Same class, filed as nits.** Review 0049:

> "[nit] … i.e. **AC1's 'keyboard down ⇒ floating pill' is violated** on desktop web…, macOS
> desktop, and the iOS Simulator with the hardware keyboard (all three are documented run targets
> in README.md:123-135)."

> "[nit] … Deleting `|| widget.focusNode.hasFocus` from `_isDocked` **leaves the whole suite green**
> while the thread composer silently never docks again."

> "[nit] … the `_separator` finder matches `Container.color == AppColors.border` exactly, so the
> keyboard-down `findsNothing` assertion passes for any alpha ≠ 1 … **the assertion is weaker than
> it reads.**"

Three findings in one review, one of them stating in its own words that an acceptance criterion is
violated — all `nit`, and `nit`s are logged, not re-looped (DESIGN #5). `reviewer.md:16` already
says `blocking` = "an unmet criterion"; the reviewer wrote "AC1 … is violated" and typed it `nit`.

**Corroborating, older:** task 0013 pinned the share button's *geometric* center onto the bookmark
icon's — tests green, review clean — and the human reverted the whole thing (app-mobile PR #116,
+1/−330): "`Icons.ios_share` and the bookmark glyph have different visual centers, so equal
*geometric* centers look misaligned." The assertion was true; the criterion ("aligned") was optical.

Counted across tasks 0048–0053: one criterion shipped unmet and re-tasked, three assertions the
review itself described as satisfiable by the broken state, zero blocking findings.

## Root cause

Two prompt lines that stop one step short of the property they exist to protect.

`agents/implementer.md:8` — "cite the test or command that proves each" — constrains that a citation
*exists*, not that it is *about* the criterion. Under rule 2 (TDD from the acceptance criteria) the
implementer writes the test from the criterion's words while holding the widget tree it just built,
and reaches for whatever node is convenient to measure. `_blob` was in hand; `TyfStickyComposer`'s
rect required one more step.

`agents/reviewer.md:11` names "gamed acceptance criteria (especially weakened/deleted/tautological
tests)" — all three are *authorship* failures, things done to a test to make it pass. An assertion
that is honest, additive, non-tautological and simply narrower than the sentence it proves is none
of them, so the reviewer classifies it as a nit and approves. `reviewer.md:16`'s definition of
`blocking` would cover it, but nothing connects the two.

Review 0050 shows the reviewer already owns the right technique and applies it unprompted —
"verified by reverse-applying the `lib/` change and re-running: 4 of the 5 new assertions fail
against the pre-fix code". That catches a *tautological* test. It does not catch a *narrow* one:
reverse-applying 0052's change would have failed its 3-edge assertion too.

## Proposed change

### 1) `agents/implementer.md` — anchor the proof to the criterion's subject

```diff
@@ rule 8
-8. Done = verify.sh green AND every acceptance criterion demonstrably met (cite the test or command that proves each).
+8. Done = verify.sh green AND every acceptance criterion demonstrably met (cite the test or command that proves each). The assertion must be anchored to the thing the criterion names and be as strong as its claim: a measurement taken on a convenient inner object does not prove a claim about the object the criterion names, and "no X anywhere" is not proven by checking three of four sides.
```

### 2) `agents/reviewer.md` — a narrow assertion is an unmet criterion, not a nit

```diff
@@ severity line
-`blocking` = ships a bug, a hole, or an unmet criterion. Everything else is `nit`.
+`blocking` = ships a bug, a hole, or an unmet criterion — including an assertion weaker than the criterion it is cited for, and any criterion you can only satisfy by reasoning about intermediate objects instead of an executed check on the thing it names. Everything else is `nit`.
```

Weight test. Remove the implementer clause and the test is written against `_blob` again — it is the
node in hand. Remove the reviewer clause and 0049's "AC1 … is violated" stays a nit, which by
DESIGN #5 means it is logged and shipped. Both are single clauses on lines that already exist; no
new step, no new artifact, no extra run.

## Risk

- **Blocking-rate inflation.** Moving a whole class from `nit` to `blocking` costs review rounds
  (each capped at 2, then escalation — DESIGN #5). If it over-fires, tasks stall at the round cap
  and reach NEEDS_HUMAN. Mitigated by the current baseline: **one** blocking finding in 53 tasks, so
  there is a very large margin before the round cap becomes the binding constraint.
- **"As strong as its claim" invites unbounded assertions.** A criterion saying "identical to the
  reply view" can always be made to demand one more property. `reviewer.md:11`'s "NOT … rewrites
  you'd prefer" and "verify each finding by reading the actual code" still bound it, and the clause
  is written about the criterion's *named subject*, not about general thoroughness.
- **Some criteria genuinely cannot be asserted end-to-end** — optical alignment (the #116 revert) is
  the real limit. This change makes the reference frame right; it does not make a widget test see.
  The honest catcher there stays the human on the preview.

## Confidence

**Medium-high.** The 0052→0053 case is fully documented, including the pipeline's own post-mortem
sentence, and the three 0049 nits show the class is recurrent rather than a single slip. Slightly
below high because the fix is prompt-level judgment, not a deterministic gate: it raises the floor
on what counts as proof, and nothing mechanically enforces the anchor.
