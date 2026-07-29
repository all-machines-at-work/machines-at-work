# Retro 2026-07-29 · tasks that write to a server are specified only for the write succeeding

Proposal — **apply by hand in the machines-at-work repo**: `skills/plan/SKILL.md`, one bullet.
Evidence window: tasks 0043–0121. Includes this retro's "observed, no action" list at the end.

## Evidence

**The task the human had to report twice.** Task 0085 "Persist room furniture placement across
sessions" carries six acceptance criteria. All six describe a successful write:

> WHEN a user finishes dragging a furniture piece THE SYSTEM SHALL persist that piece's room-space
> position through a write endpoint … WHEN the room is loaded THE SYSTEM SHALL draw each owned piece
> at its persisted position …

Not one names a failed write, a cancelled gesture, or what the client shows when the server disagrees.
The words "fail", "error", "revert" and "snackbar" appear nowhere in 0085, 0089, 0090 or 0091 —
the four tasks that built every write path in the room. All four shipped green and approved.
On 2026-07-28 the human texted (intent `1f99545`):

> …and the positions of the assets are still not saved when I move them around in the room…

Task **0115**, planned from that note, enumerates what was missing — and every item is a path no
criterion had asked for:

> a drag that is cancelled mid-way never writes, a failed write is swallowed with a `debugPrint`, and
> the offset map ignores whatever the server sends back afterwards — so a piece looks moved all
> session and snaps back on the next launch.

Task **0116**, from the same note: "the room never refetches after the arrange sheet closes, so it
keeps drawing a bunch the server now considers seated."

**The same shape as two blocking findings.** The reviewer catches this class when it is severe enough:

- 0093 [blocking] — "`_loadReactions()` runs only from `initState` … the room immediately re-renders
  as Kit … but `_reactions` still holds Bean's payload … and it stays wrong until the app is
  restarted."
- 0108 [blocking] — "the top-bar chip drops from 45 to 44 while the true balance is 47, and stays
  wrong until a manual pull-to-refresh or restart."
- and as nits when it is not: 0108 round 2 ("the *balance* is live now, but the checklist isn't"),
  0110 ("a refetch that lands while a creation is in flight drops the created tile"), 0089 and 0102
  (`_recover` calling `setState` twice).

**It is the criteria, not the implementers.** Across all 121 tasks only **11** task.md files contain a
write-failure criterion and **6** a refetch criterion — and every persistence one is 0115 or later,
i.e. written after the human complained. When a criterion did exist the implementer met it: 0111's
review confirms "failure restores the row … and shows `actionsTickFailed` — `:180-193`, tested."

Correlation worth noting but *not* the fix: 0085 and 0108 — the two worst outcomes here — are both
frontend tasks with **no** `design.md`, and `skills/design/SKILL.md:12` is the one place in the plugin
that already demands "States: empty, loading, error, success". `skills/build/SKILL.md:12` runs design
only "If UI-heavy", a judgment call. Tightening that judgment is a vaguer, larger change than putting
the requirement where the contract is written.

## Root cause

`skills/plan/SKILL.md:14-18` — the MUST list for every task is: a goal verifiable in one green run,
testable WHEN/SHALL criteria, explicit non-goals, the repos it spans. Nothing requires the failure or
staleness path of a mutation. The skill's own closing line for that step is "Decomposition quality is
the leading indicator of pipeline success" — and a task about a *write* whose contract only covers the
write landing is a decomposition defect, not an implementation one: the implementer met every
criterion, the reviewer checked against the same criteria, and `verify.sh` proved the happy path.

## Proposed change

One bullet in the step-3 MUST list, between non-goals and repos:

```diff
    - explicit non-goals ("don't touch X"),
+   - for a task whose client writes to a server: a criterion for the failed write (what the user sees, what the UI reverts to) and one for what the client renders after a refetch — without both, the implementer ships a swallowed error and optimistic state that never reconciles,
    - the repos it spans (cross-repo only when the feature genuinely spans them).
```

Would removing it cause the mistake to recur? It already did: 0085, 0089, 0090 and 0091 were all
planned without it, and the one that reached the user cost three follow-up tasks.

## Risk

- **Criteria inflation.** A task that writes nothing user-facing (a migration, a nightly script, a
  backend-only endpoint) does not need this; the clause is scoped to "whose client writes to a
  server", but /plan may over-apply it and add a test per task for a failure path the app's global
  error handling already covers.
- **Duplication with `design.md`** on UI-heavy tasks that get one — the design's error state and the
  criterion will say the same thing twice. Harmless, and the criterion is the one the reviewer checks
  against.
- It does not help tasks where the *staleness* is cross-screen rather than write-local (0093, 0108
  were both "another screen changed the same server state"). Those still depend on the reviewer, which
  did catch both.

## Confidence

**High.** The pattern is anchored on human feedback contradicting a task the pipeline declared done
(the strongest evidence class available), it recurs across four sibling tasks and two blocking
findings, and the counter-example holds: the tasks that *did* carry the criterion shipped the
behaviour.

---

# Observed, no action

One-offs and known-but-not-worth-a-prompt-line items from tasks 0043–0121.

- **Stale docstrings and comments describing deleted behaviour** — a recurring *nit* class, never
  worse than a nit: `list_instances` still promising retired rows are "for history and for selling"
  (0092), `fill_vase`'s docstring listing a 409 the diff deleted (0099), the sanitizer's docstring
  (0093), `chat_screen.dart:350` still promising "surfaces the unlock chip" (0104), flower head counts
  (0098), "matcha/classic" theme comments (0069). The reviewer catches these reliably and they cost
  nothing at runtime; no prompt line would earn its place. They ride along in the
  `2026-07-29-review-nits-are-write-only.md` channel if that lands.
- **Wall-clock time-bomb in a fixture (0111 → 0121).** `frontend/test/caretap_log_test.dart` pinned a
  fixture day to the literal `'2026-07-27'`; when the date rolled over the suite went red and left
  `main` RED with nothing blocked — every subsequent `task.sh done` preflight would have failed.
  `unblock` diagnosed it exactly right and one task (0121) fixed it. **One instance**; a "no wall-clock
  literals in fixtures" rule is not earned until it happens twice.
- **`frontend/integration_test/` is executed by nothing.** `VERIFY_frontend` is `flutter analyze &&
  flutter test`, which never runs it (it needs a device and a live backend). Flagged since 0011 and
  0013, rotted through 0042, 0072, 0105, 0108, 0109. Not proposed as a plugin change: this is a
  project-side configuration gap and the plugin already ships the slot for it (`SMOKE_<repo>`,
  `proposals/2026-07-24-boot-smoke-gate.md`, applied v0.23.0), and both agents have now written
  themselves memory files about it. If `2026-07-29-agent-memory-forks-by-cwd.md` lands and those
  memories are actually delivered, this should self-correct; if it recurs afterwards, the earned
  change is one question in `init-project` — "does `VERIFY_<repo>` run every test directory in the
  repo? if not, wire it into `SMOKE_<repo>` or delete it."
- **Three "session ended in-progress with no committed work" escalations** (0083, 0091 ×2) in
  NEEDS_HUMAN.md. Already the subject of the 2026-07-08 loop retros; no new signal.
- **Genuine one-offs**, each already fixed or inert: the tautological `List == List` assertion in
  `frontend/test/creature_frame_test.dart:57` (0055); the sanitizer regex turning `2*3*4` into `234`
  (0094, fixed in round 2); dead `theme`/`tokens` parameters in `sell_sheet.dart:136` (0092);
  `_upsert_summary` NULLing an embedding column on the weekly/monthly path (0105).
- **Empty `.claude/agent-memory/` directories** at `machines-at-work/tasks/` and
  `machines-at-work/tasks/0108-…/` — symptoms of the cwd fork, covered by proposal 1.
- **No cost or timing outliers in the window.** Every recorded cost since 0019 reads `subscription`
  (largest API-equivalent estimate ~$22.7); the one dollar outlier on record, `$25.29` on task 0014,
  predates the last retro. 68 of 121 task.md files record no cost at all (`Cost: -`) — a gap, but a
  harmless one while the project is on a subscription. `_timings.tsv` is flat: `verify:backend`
  16–22 s, `verify:frontend` 50–82 s across the whole window. One small inefficiency, not worth a prompt line: `verify.sh` already accepts
  repo arguments, but `agents/implementer.md` rule 4 never mentions them, so a backend-only task
  (0106) still paid two full `verify:frontend` runs.
