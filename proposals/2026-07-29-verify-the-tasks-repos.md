# Retro 2026-07-29 · Verify runs every repo, including the ones the task declares out of scope

Proposal — **apply by hand in the intentpipe repo** (the plugin is read-only inside projects;
move this into `intentpipe/proposals/` when applying). Touches `agents/implementer.md` (rule
4), `scripts/task.sh` (one line), and a clarifying line in `DESIGN.md` #33. `scripts/verify.sh`
itself needs no change — it already takes the argument.

This is not a re-proposal of the 2026-07-24 boot-smoke gate. That gate is right and has paid for
itself. This is a scoping bug in how it — and `VERIFY_<repo>` before it — is *called*.

## Evidence

`verify.sh` has signature `verify.sh [--no-smoke] [repo ...]`, defaulting to all of `$REPOS`
(line 34). **No caller ever passes repos.** `implementer.md:4` says "Run
`${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh` after each meaningful change"; `task.sh` calls it bare in
`cmd_done` (the merge gate) and in `cmd_diagnose`. Meanwhile `Repos:` is a first-class task.md field
written by `task.sh new`, and `cmd_done` itself iterates `$(get_field "$md" Repos)` for every other
step — the dirty check, the push, the PR loop. The one call that doesn't use it is the expensive one.

Tasks 0048–0053 are all `Repos: app_mobile`, with explicit non-goals ("Don't touch … anything in
`core`"), and their branches exist only in app-mobile. Their `timings.tsv` (seconds):

| task | `verify:core` runs | `smoke:core` runs | core seconds | task total |
|---|---|---|---|---|
| 0048 | 65, 55, 57 | 34, 33, 33 | 277 | 23m43s |
| 0049 | 58, 56, 58 | 33, 33 | 238 | 28m46s |
| 0050 | 56, 57, 56 | 33, 23 | 225 | 18m39s |
| 0051 | 56, 55, 55 | 27, 23 | 216 | 12m50s |
| 0052 | 53, 60 | 28, 33 | 174 | 13m56s |
| 0053 | 55, 54, 54 | 27, 28 | 218 | 14m30s |
| | | | **1348s = 22m28s** | **112m24s** |

**20% of six tasks' wall clock was spent building, migrating, seeding and booting a repo those tasks
could not have touched.** Seventeen `VERIFY_core` runs — each `docker compose up --wait tyf-db-test`
plus `tox -e qa,py313` plus an infra pytest — and **13 `SMOKE_core` runs.**

The smoke command is not read-only, by design:

```sh
SMOKE_core='docker compose up -d --force-recreate --wait tyf-api'
# "--force-recreate is load-bearing: a plain `up -d` on an already-running container is a no-op
#  that proves nothing." … "Leaves the stack up (it is the preview)."   — agents.env
```

So each of those 13 runs tears down and rebuilds the API container **that serves the preview the
human is reviewing on** (`.tunnels/core-url.txt`, the Cloudflare-served preview), for ~30s, during
a task whose whole subject is a Flutter padding. Tasks 0048–0053 are precisely the feature where the
human was going back and forth on the preview between rounds (notes `tg-1785171526-576`,
`tg-1785220920-596`, `tg-1785245401-614`, `tg-1785268502-646`).

`--no-smoke` exists and `implementer.md:4` advertises it, but the timings show it is used
inconsistently — 0048 smoked on all three verify runs, 0052 on both. It is also the wrong knob here:
it would skip the boot check for `core` *and* for any repo the task actually changes.

## Root cause

`DESIGN.md` #33 weighed the honest cost of the smoke gate as *boot time on the inner loop* and
answered it with `--no-smoke`. It never considered *which repos* a given task's verify should cover,
because before #33 the surplus was ~55s of test run and nobody measured it. Nothing in the design
argues for verifying an untouched repo per change: DESIGN #4 makes `verify.sh` "the engine" and #7
makes `agents.env` a generic repo list, but the *unit* being gated is a task, and the task already
declares its repos. The all-repos sweep has a proper home — `preflight.sh`, which `loop.sh` runs
unconditionally at the top of every loop run (`until "$SCRIPTS/preflight.sh"`, line 97) and which
validates every repo, verifies every repo and smokes every repo. That is where "is the whole
workspace green?" belongs; it is not a per-change question.

## Proposed change

Pass the task's declared repos at the two per-task call sites. Leave `preflight.sh` and `loop.sh`
alone — the full sweep stays exactly as it is, once per run.

### 1) `agents/implementer.md`

```diff
@@ rule 4
-4. Run `${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh` after each meaningful change (`--no-smoke` skips the app-boot check for a faster inner loop; the run that declares done must be the full one).
+4. Run `${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh <the repos in task.md's `Repos:` field>` after each meaningful change — verifying a repo the task does not touch costs minutes and, if it smokes, restarts a service someone may be looking at (`--no-smoke` skips the app-boot check for a faster inner loop; the run that declares done must be the full one).
```

### 2) `scripts/task.sh`, `cmd_done`

```diff
@@ cmd_done, before the merge
-  "$(dirname "${BASH_SOURCE[0]}")/verify.sh" || { echo "ERROR: verify failed — not merging" >&2; exit 1; }
+  # The task's repos, not all of them: a repo this task never branched in was green at
+  # preflight and no commit here can have moved it. Unquoted — the field is a word list.
+  # shellcheck disable=SC2046
+  "$(dirname "${BASH_SOURCE[0]}")/verify.sh" $(get_field "$md" Repos) \
+    || { echo "ERROR: verify failed — not merging" >&2; exit 1; }
```

(`cmd_diagnose`'s call already carries `--no-smoke` and is a whole-workspace color — leave it.)

### 3) `DESIGN.md` #33, one sentence appended

```diff
-… hence `--no-smoke`, used by the two callers that only want a status color … The two real gates — `preflight.sh` and `task.sh done` — always run it.
+… hence `--no-smoke`, used by the two callers that only want a status color … The two real gates — `preflight.sh` and `task.sh done` — always run it. Scope follows the unit being gated: `preflight.sh` sweeps every repo once per run (workspace health), while the implementer's loop and `task.sh done` verify and smoke only the task's declared `Repos:` — a repo the task never branched in was green at preflight and no commit on the branch can have moved it, so re-testing it per change buys nothing and a smoke command with side effects (`--force-recreate` on a live preview) actively costs.
```

Weight test. Remove #1 and every Flutter task keeps paying ~90s per inner-loop iteration to test and
boot a Python service. Remove #2 and the merge gate keeps recreating the preview container at the
exact moment `AFTER_DONE` (#36) is about to check out the new branch and relaunch it anyway.

## Risk

- **An implementer edits a repo the task didn't declare, and its tests never run.** This is the real
  regression, and it is caught loudly one step later: `task.sh done` refuses to merge a repo with
  uncommitted changes only for declared repos, so the stray edit sits in the worktree and the *next*
  `preflight.sh` fails with "FAIL: `<repo>` has uncommitted changes" before any agent runs
  (`preflight.sh:25`). Noisier than today's silent-green, but it fails closed and points at the
  actual mistake instead of hiding it behind a passing suite of unrelated tests.
- **Cross-repo API drift** — the failure mode DESIGN's implementer role is built around. Unaffected:
  a task that genuinely spans repos declares both, and `/plan` step 3 already requires "the repos it
  spans (cross-repo only when the feature genuinely spans them)". Only single-repo tasks change.
- **A stale `Repos:` field** (hand-edited, or a task that grew) would under-verify. Same containment
  as above: preflight catches the uncommitted remainder next run.
- **Less frequent core boots ⇒ a core regression is found later**, at the next loop preflight rather
  than mid-Flutter-task. That is the correct place to find it, and it is still before any merge.

## Confidence

**High** on the measurement and the mechanism — the argument already exists in `verify.sh`'s
signature, `Repos:` is already the authority everywhere else in `cmd_done`, and the 22m28s / 13
preview restarts are counted from the recorded timings. **Medium** on the size of the real-world
win, since the wasted minutes are wall clock on a subscription plan rather than billed tokens; the
preview-restart side effect is the part that is unambiguously wrong.

---

# Observed, no action

One-offs and things checked and deliberately not proposed from, 2026-07-24 → 2026-07-29:

- **The visit-pill rework chain is product evolution, not a pipeline pattern.** 0029 → 0035 → 0039
  and 0036 → 0041 rewrite each other, which looks like the strongest rework signal in the log. The
  spawning notes say otherwise: `74586c8` asks for "a second row of text, smaller and in brackets";
  `a5f278e` then says "the layouting with the resets in 24 hours doesn't look so good actually …
  but actually let's do it like this"; `f84e434` asks that clicking reload the place sheet, and
  `b9b660a` reverses it — "immediately show 'resets in 24h' and **do not** reload the place sheet".
  The human changed their mind, twice, and the pipeline tracked it correctly. Retro SKILL step 3 /
  DESIGN #13 say explicitly: never propose from this.
- **`NEEDS_HUMAN.md` 0031 — "loop.sh: session ended in-progress with no committed work."** Single
  occurrence in 53 tasks; the in-progress backstop (DESIGN #15/#22) and `/unblock` (#31) already own
  this class. No new evidence.
- **The `Decision:` gate worked.** Task 0045 parked a genuine either/or ("should a returning visitor
  re-notify after the 24h reset?") on Telegram with a stated default instead of guessing. It is
  still unanswered in `NEEDS_HUMAN.md`, which is a human-latency fact, not a pipeline defect — worth
  recording as the positive control for proposal 1's "use the gate more".
- **No `tasks/*/feedback.md` exists anywhere in 53 tasks**, though retro SKILL step 1 and DESIGN #9
  name it as the highest-weight retro input. Not proposed as a change: the human's corrective
  feedback does arrive, as Telegram notes in `updates/`, and step 3's `Intent:` trace reads them
  directly and more reliably than a file nobody is prompted to write. Flagging only so a future
  retro doesn't read the empty channel as "no human feedback".
- **Cost outlier: task 0049, ~$5.99 API-equiv / 546k tokens / 28m46s** — 4× the median of its
  feature for a two-file layout change. Its `timings.tsv` shows six `llm` segments (181s, then 3s,
  2s, 2s, 2s) before the real run: a session that died early and resumed, i.e. DESIGN #14/#15
  machinery working. One occurrence; not a pattern yet, but worth watching if resume-thrash shows up
  again in the next window.
- **`_timings.tsv` at the tasks root mixes loop-level preflight runs with nothing to distinguish
  them** — five identical preflight/verify/smoke blocks with no task id or timestamp. Minor
  observability wart; the per-task `timings.tsv` files (0048+) carry the useful signal.
- **Review 0049's "the `_separator` finder … is weaker than it reads"** is folded into proposal 2 as
  evidence, not treated separately.
