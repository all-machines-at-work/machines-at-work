# Retro 2026-07-29 · The review gate cannot falsify the task

Proposal — **apply by hand in the intentpipe repo** (the plugin is read-only inside projects;
move this into `intentpipe/proposals/` when applying). Touches `agents/reviewer.md` (two
clauses) and `skills/plan/SKILL.md` (two clauses).

## Evidence

Feature `tyf-180-discussion-composer-tap-and-dock` (tasks 0048–0053, app-mobile PR #120, still
open). Six tasks on one widget, `TyfStickyComposer`. Three of them wrote an *interpretation of the
human's note* into the task and addressed it to the reviewer:

- **0049** — "Interpretation of the note being implemented — flagged so it can be corrected in
  review: 'more integrated into the keyboard' applies **only while the keyboard is on screen**".
- **0050** — "Interpretation flagged for review — the note names only the camera, but the send
  button flanks the same row…".
- **0051** — "Interpretation flagged for review, as in 0050: with `center`, a docked draft that has
  grown to several lines also centers its circles rather than keeping send on the last line…".

All three reviews returned `VERDICT: approve`. None of the three adjudicated the flagged
interpretation — because the reviewer is prompt-bound to check the diff against the *acceptance
criteria*, and the criteria were written **from** the interpretation. The flag is addressed to an
agent whose scope forbids acting on it.

The cost lands on the human, who re-reports the same defect. Task **0050**'s Goal states the shared
cause it found — "*both bars* lay their controls out with `Row(crossAxisAlignment:
CrossAxisAlignment.end)`" — and then scopes the fix: "Fix the *floating* look only." Fourteen hours
later, note `tg-1785220920-596` (Intent `9f8f955`):

> "The **Same** alignment issue appears when I click the Dialog and the Keyboard opens. Here the
> send Button and the Camera Button are aligned to the bottom"

That became task 0051 — 12m50s, ~$1.55 API-equiv, a full plan → implement → review → merge cycle to
delete a ternary the pipeline had deliberately introduced one task earlier.

The reviewer had *already found it*. Review 0050, filed as a **nit**:

> "[nit] `tyf_sticky_composer.dart:458` — the alignment flips in a single frame … **matching the
> task's explicit "keep `end` while docked" instruction requires some switch.**"

That sentence is the pattern in one line: the reviewer sees the defect, measures it against task.md,
and defers to task.md. The same shape one task later — note `tg-1785245401-614` asks for one
backdrop color on both surfaces; 0052 ships and is approved; note `tg-1785268502-646` (Intent
`2a2ad8c`) says:

> "The Colors between the Keyboard and the Florine Dialog are **still** different in the Place sheet
> and the reply view."

Two "same"/"still" re-reports in six tasks. Across the whole project the reviewer has produced
**one** blocking finding in 53 tasks (0002, before the last retro) and 28 nits, while the human
filed at least three correction tasks against work it approved.

Corroborating, older: app-mobile PR **#116** ("Revert sheet-header share/bookmark button
alignment", merged 2026-07-22 by the human, +1/−330) reverts task 0013 wholesale — approved with
zero findings, tests green, and optically wrong.

Excluded as product evolution, deliberately: the visit-pill chain 0029→0035→0039 and 0036→0041. The
notes there are changed requests, not re-reports — `a5f278e` "the layouting … doesn't look so good
actually because … but actually let's do it like this", `b9b660a` "immediately show 'resets in 24h'
and **do not** reload the place sheet" after the previous note had asked for the reload. Not
actionable (retro SKILL step 3, DESIGN #13).

## Root cause

`agents/reviewer.md:9` tells the reviewer to read `task.md` and the diff. Nothing points it at
`Intent:` — the field DESIGN #13 created for exactly this purpose ("each task.md records the note
commit it was planned from"), currently consumed only by `/retro`, days or weeks later. So the
reviewer's yardstick is the plan's *reading* of the human's words, never the words.

`agents/reviewer.md:11` then scopes findings to "unmet or gamed acceptance criteria". An
interpretation baked into the criteria is unfalsifiable by construction: the diff meets the
criteria, so there is nothing to report. DESIGN #4's trust hierarchy (compiler >> fresh-context
critic) is intact for *correctness*; it has no rung at all for *intent*, and on a UI-polish project
every escaped defect has been an intent defect.

`skills/plan/SKILL.md:19` requires "explicit non-goals ('don't touch X')" — sound for excluding
unrelated work, but 0050 used it to exclude *the other instance of the defect being reported*. And
step 5's `Decision:` gate — which works; task 0045 used it correctly for a notification-dedupe
question — is scoped to "a product decision the user has **not** made (a lifetime, a threshold, an
either/or)". A planner reading a note the user *did* write does not classify its own scope choice as
an unmade decision, so it reaches for the prose escape hatch instead.

## Proposed change

### 1) `agents/reviewer.md` — read the note, and own the interpretation

```diff
@@ line 9
 You review one task. Read `intentpipe/tasks/<id>-<slug>/task.md` (including any files its `Resources:` field lists — a referenced mockup or screenshot is acceptance criteria in picture form; you can view images), then the diff of branch `task/<id>-<slug>` against the default branch in each affected repo (`git diff <default>...<branch>`).
+Also read the note the task was planned from — `git -C <workspace> show <task.md's `Intent:` sha>`. That is the human's words; task.md is only the plan's reading of them, and the reading is what fails.
@@ line 11
-Scope — report ONLY: correctness bugs, security issues, unmet or gamed acceptance criteria (especially weakened/deleted/tautological tests), dead or duplicated code. NOT style, naming, hypothetical scale, or rewrites you'd prefer.
+Scope — report ONLY: correctness bugs, security issues, unmet or gamed acceptance criteria (especially weakened/deleted/tautological tests), a diff that meets every criterion yet leaves the Intent note's complaint standing (an interpretation the task flags is yours to settle against the note — no one downstream does, and the human re-reports it as "the same" or "still"), dead or duplicated code. NOT style, naming, hypothetical scale, or rewrites you'd prefer.
```

### 2) `skills/plan/SKILL.md` — a non-goal is not a place to park half a defect

```diff
@@ step 3
-   - explicit non-goals ("don't touch X"),
+   - explicit non-goals ("don't touch X") — which exclude other *work*, never another instance of the defect the note reports,
@@ step 5
-If a task hinges on a product decision the user has **not** made (a lifetime, a threshold, an either/or), set the task's `Decision: <the exact question>` field rather than guessing
+If a task hinges on a product decision the user has **not** made (a lifetime, a threshold, an either/or — including how far a reported defect's fix reaches, when the cause you diagnose is shared with a surface the note didn't name), set the task's `Decision: <the exact question>` field rather than guessing; flagging an interpretation in prose "for review" is not an escalation, since the reviewer reviews against the criteria you wrote from it
```

Weight test. Remove the reviewer's two clauses and 0050→0051 recurs exactly: the reviewer writes the
nit, defers to task.md, approves. Remove the plan clauses and the planner keeps writing "fix the
floating look only" over a cause it has just documented as shared. Each addition is one clause on an
existing line; the reviewer prompt grows from 26 to 27 lines.

## Risk

- **Scope creep in review.** "Leaves the note's complaint standing" is a softer predicate than "test
  is tautological", and a reviewer could stretch it into re-litigating approved decomposition. Two
  guards already hold: the finding must still be substantiated by reading the code
  (`reviewer.md:13`), and rounds are capped at 2 (DESIGN #5) — a reviewer that argues with the plan
  twice escalates to the human, which is the correct outcome for a genuine intent dispute.
- **More `Decision:` gates ⇒ more pauses.** A build that stops for a Telegram reply has latency the
  current guess-and-ship path does not. Bounded by the same evidence: the guesses cost 12–19 minutes
  and a human round trip *anyway*, and only where the diagnosed cause demonstrably spans an unnamed
  surface — 0049's "keyboard-up only" reading, which was never contradicted, would still ship as a
  flagged interpretation.
- **Notes are transcribed voice memos**, often garbled ("the Florine Dialog"). A reviewer weighting
  them literally over a careful task.md could produce noise; the clause deliberately says the
  *complaint*, not the wording.

## Confidence

**High.** The mechanism is visible end to end in one feature — the flag, the reviewer's own nit
naming the instruction it deferred to, the human's "Same"/"still" notes, and the follow-up tasks
with their costs — and the fix reuses two fields the pipeline already maintains (`Intent:`,
`Decision:`) rather than inventing machinery.
