# Design 2026-07-31 · The loop never de-dups: `/cleanup` sweep skill + 🧹 trigger

**Status:** applied · 2026-07-31 · v0.31.0
**Scope:** machines-at-work (new `skills/cleanup/SKILL.md`); server-orchestrator leg (🧹 in
`TRIGGERS`/`dispatch`/help text) included below for reference, lands in that repo.

## Evidence / observation

Slop accumulates by construction. Every implementer runs fresh-context per task (deliberately —
DESIGN.md core thesis), so no agent ever holds the whole codebase; the reviewer sees one task's
diff; duplication and dead-code findings are filed as **write-only nits** (proposal
2026-07-29-review-nits-are-write-only) — logged, never re-looped. Nothing in the pipeline reads
*across* tasks, so the junk compounds, and it also taxes every future session: dead helpers and
duplicated logic are context every later implementer and reviewer must wade through.

Bibbles proves both the accumulation and the fix-shape:

- Nits piled up and went stale across ~90 tasks: 0011 flags `chatSend` as dead — 0072 finds it
  *still* dead ("unused on main too"); 0058 flags `lifeToppings` as "already dead on `main`
  (pre-existing) — out of scope for this cleanup"; 0022 flags the unlocked-keys loop duplicated
  across two screens; 0024 flags orphaned `ApiClient.getBytes`; 0086 a duplicated test helper.
  The reviewer keeps saying "pre-existing, not this task" — correctly, per its per-diff contract —
  and nobody is the someone whose scope it is.
- The human eventually hand-planned exactly the missing step: **task 0105 "Dead-code and
  duplication sweep across both repos"** (Intent 1be7e37) — behaviour-preserving, verify-gated,
  "no test deleted to make a removal pass", judgement calls listed in Notes. It converged in one
  round at 293k tok / 42m and removed every symbol the nits had been circling for weeks. The step
  works; it just has no trigger and depends on a human noticing the drift.

## Root cause

The pipeline has no codebase-scope maintenance surface. `/retro` mines *pipeline* weaknesses (its
prompt is about review/feedback patterns, not code health); `/toolsmith` wraps repetitive
*operations*; the reviewer is per-diff by design. The one step that reads the repos whole —
find what's dead or duplicated across task boundaries — exists nowhere, so it only happens when a
human notices and writes the note themselves.

## Proposed change

A `/cleanup` skill: a **read-only sweep that feeds the normal pipeline**, plus a 🧹 daemon trigger.
It scans the repos, verifies each finding, and writes one intent note into `updates/` — the human
approves via the ordinary `/plan` gate, and the fix lands as ordinary verify-gated, reviewed tasks
(0105 is the template). No second write path: like `/retro`, it proposes and never applies —
behaviour-preserving refactors are exactly where the test suite is the only net, so they must ride
`verify.sh` + fresh review, not a side channel.

**Manual trigger, deliberately not every-N-tasks:**

- Same knob discipline as #10/#17: defer automation until observed need. An N-task counter fires at
  arbitrary moments — mid-feature, with open PRs against the fixed plan-time base (#29) — and
  cleanup churn racing open PRs is a conflict generator. A human triggers 🧹 at natural quiet
  points, after a feature lands.
- The "when is it due" signal already exists free of charge: duplication/dead-code nits
  accumulating in `review.md`. The skill reads them as pre-verified leads; `/retro` (or a human
  skimming) reading "nits piling up" as "time for 🧹" costs no machinery.

### `skills/cleanup/SKILL.md`

```markdown
---
name: cleanup
description: Read-only sweep of the project repos for dead and duplicated code; findings become one intent note in updates/ for the normal plan → build pipeline. Never edits code.
disable-model-invocation: true
argument-hint: "[headless]"
---

Find the junk the per-task loop cannot see. Fresh-context implementers re-invent helpers and leave
orphans; the reviewer sees one diff and files duplication as write-only nits. You read across the
whole codebase and turn what you find into plannable intent. You NEVER edit code — fixes ride the
normal pipeline (/plan → tasks → verify → review).

Headless mode — when $ARGUMENTS contains `headless`: never prompt; step 5's summary goes through
`${CLAUDE_PLUGIN_ROOT}/scripts/notify.sh` as well as stdout.

1. Read machines-at-work/agents.env (`REPOS`). Find the last cleanup note (`git log --oneline --
   machines-at-work/updates/` for `cleanup-`); skim `tasks/*/review.md` nits since then —
   duplication/dead-code nits are pre-verified leads.
2. Sweep each repo for: symbols with zero readers outside their own definition; near-identical
   logic at ≥2 call sites worth one shared helper; orphaned files and exports; stale doc comments
   narrating removed designs. Grep-verify every candidate — a "dead" symbol with a reflective or
   string-keyed reader is a false positive that would plan a breaking task.
3. Keep only findings worth tasking, each with file:line evidence. Skip anything an open task or
   unmerged PR already touches (`task.sh status`) — don't race live work.
4. Nothing significant → report that and stop. Do not invent work; a near-empty sweep is the good
   outcome.
5. Else write ONE note `machines-at-work/updates/cleanup-<date>.md`: per finding, the evidence and
   the intended action (delete / extract shared helper), plus the standing constraints — behaviour-
   preserving only, verify green, no test deleted to make a removal pass, judgement calls listed in
   task Notes (bibbles 0105 is the model). Sized for /plan to cut into 1–2 tasks. Report ≤5 lines;
   headless: notify `🧹 sweep: <N> findings → updates/cleanup-<date>.md — 🧠 to plan`.

Never edit repo code, never write tasks/ directly — the human gates the plan.
```

### server-orchestrator leg (reference — lands in that repo)

```diff
 TRIGGERS = {"🧠": "plan", "plan": "plan", "🚀": "loop", "build-all": "loop",
-            "🩹": "unblock", "unblock": "unblock", "📋": "retro", "retro": "retro"}
+            "🩹": "unblock", "unblock": "unblock", "📋": "retro", "retro": "retro",
+            "🧹": "cleanup", "cleanup": "cleanup"}
```

```diff
     elif action == "retro":
         cmd, ack = ["claude", "-p", "/machines-at-work:retro headless", *PLAN_CLAUDE_FLAGS], \
                    "📋 retro — mining finished tasks; proposals will post back…"
+    elif action == "cleanup":
+        cmd, ack = ["claude", "-p", "/machines-at-work:cleanup headless", *PLAN_CLAUDE_FLAGS], \
+                   "🧹 sweeping for dead/duplicated code — findings land as an updates/ note…"
```

Plus `"cleanup"` in `PROJECT_ACTIONS` and a help line ("🧹 or cleanup — sweep the repos for
dead/duplicated code; findings land as an updates/ note — 🧠 to plan them"). No completion-time
special case in `reap_jobs` (unlike retro's react-to-apply offers): notify.sh carries the
substance and the note simply waits for the next 🧠. The skill stays on the CLI default model,
like unblock/retro.

## Risk

- **False-positive deletions.** A symbol read reflectively/by string key looks dead to grep. Two
  gates before any damage: the skill must grep-verify (step 2), and the finding still passes human
  plan approval + implementer + verify + reviewer. Worst case matches today's manual flow.
- **Make-work.** A sweep prompted to find things may pad findings. Step 4 makes the empty sweep an
  explicit good outcome, and the human sees the note before anything is planned.
- **Racing open work.** A cleanup task touching files an open PR touches conflicts at merge.
  Step 3 excludes open tasks/PRs, and the manual trigger biases runs to quiet points.
- **Scan cost.** A whole-codebase read is a real session (~0105's planning share). Manual trigger
  keeps the spend deliberate.

## Not proposed

- **Auto-cadence (every N tasks / cron).** Wrong moments, unearned automation — see above. Promote
  later if the manual rhythm proves stable.
- **Letting the skill edit code or write tasks/.** Would create a second, less-gated write path;
  everything in DESIGN.md (#4, retro's propose-don't-apply, /unblock's never-edits) says no.
- **Widening the reviewer's scope to codebase-wide duplication.** Per-diff review is what makes
  review converge (#5); cross-task health belongs to a step that runs at codebase scope.
