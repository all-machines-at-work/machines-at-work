# Retro 2026-07-29 · a reviewer's nit has no reader, so known defects reach the user

Proposal — **apply by hand in the intentpipe repo**: `scripts/task.sh` (new read-only
subcommand) and `skills/plan/SKILL.md` (one sentence). Evidence window: tasks 0043–0121.

## Evidence

Since 0043 the reviewer has recorded roughly **55 `[nit]` findings**. Nothing in the pipeline ever
reads one again. Three of them, traced forward:

**1. 0085 → the human's bug report → 0115/0116/0117.** Task 0085 "Persist room furniture placement
across sessions" was approved with this nit:

> [nit] `frontend/lib/screens/bibble_screen.dart:231` — `_placeItem` fires each PUT fire-and-forget
> with no sequencing or cancellation of an in-flight write for the same item. … after the next
> Building → Inside remount the piece snaps back to X rather than where the user dropped it.

Four days later the human texted in (intent commit `1f99545`, 2026-07-28):

> …and the positions of the assets are still not saved when I move them around in the room…

which became tasks **0115, 0116 and 0117**. 0115's goal names the same defect the reviewer had
already written down: "a failed write is swallowed with a `debugPrint`, and the offset map ignores
whatever the server sends back afterwards".

**2. 0104 → 0105 missed it → still shipping.** 0104's round-2 nit was addressed *to the next task*:

> [nit] frontend/lib/bibble/life_asset.dart:92 — `LifeAssetView` … now has zero readers in `lib/` and
> `test/`. … the Notes' hand-off list for 0105 names only `BibbleManifest` and `BibbleShapeParams`, so
> this widget would be missed.

0105 ("Dead-code and duplication sweep across both repos") ran next and missed it. On `main` today:
`LifeAssetView` at `frontend/lib/bibble/life_asset.dart:81`, the dead `unlockedKeys` at
`frontend/test/chat_photo_share_test.dart:78`, the stale doc comment at `life_asset_pixel.dart:167`.

**3. The same finding re-derived three times.** `integration_test/app_shell_test.dart` was flagged
stale as a nit in **0042** ("already non-functional … outside the `flutter test` verify gate"), again
in **0072** ("a 0069 home-title leftover — unused on main too"), and again in **0108** ("it taps an
'Actions' tab and a 'Bibble' tab that do not exist on `main`"). Three reviewers spent context
rediscovering the same fact; the file is still stale.

## Root cause

DESIGN #5 — "Findings typed `[blocking|nit]`; nits are logged, not re-looped" — is right about the
*build* loop: re-looping nits is how review ping-pong becomes unbounded. But "logged" turned out to
mean "written to a file with no reader":

- `skills/build/SKILL.md:16` — "send **ONLY** the blocking findings back to the implementer".
- `skills/plan/SKILL.md:13` (step 2) — /plan reads the notes, `tasks/_log.md` and `task.sh status`.
  Never `review.md`.
- `scripts/loop.sh:262` and `scripts/task.sh:157` — read `review.md` only for its final `VERDICT:`
  line.
- `scripts/task.sh:222,274` — paste the whole file into a PR body, and only under `DONE=pr`. bibbles
  runs `DONE=local`, so here `review.md` has **no** post-verdict reader at all.

So the pipeline's cheapest, highest-signal defect source — a fresh-context critic that already read
the diff — writes to `/dev/null`, and the same defects come back either as a user complaint or as
another reviewer's context spend.

## Proposed change

Keep DESIGN #5 exactly as it is (nits still never re-loop inside a build) and give them one triage
point at the next planning run. Mechanics in the script, judgment in the skill.

**1. `scripts/task.sh` — a read-only `nits` subcommand.**

```diff
+cmd_nits() { # every [nit] from a done task's review, newest task first. The
+  # disposal channel for DESIGN #5: nits are not re-looped inside a build, so
+  # /plan is the only place they get triaged into work or dropped on purpose.
+  local d md id
+  for d in $(ls -dr "$TASKS"/[0-9]*/ 2>/dev/null); do
+    md="$d/task.md"; [ -f "$md" ] || continue
+    [ "$(get_field "$md" Status)" = "done" ] || continue
+    [ -f "$d/review.md" ] || continue
+    id=$(basename "$d" | cut -d- -f1)
+    grep -h '\[nit\]' "$d/review.md" | sed "s|^|$id |"
+  done
+}
+
 case "${1:-}" in
-  new|start|next|status|diagnose|done|sync|block|reopen|abandon|clean-repo|resolve) c="${1//-/_}"; shift; "cmd_$c" "$@" ;;
+  new|start|next|status|diagnose|nits|done|sync|block|reopen|abandon|clean-repo|resolve) c="${1//-/_}"; shift; "cmd_$c" "$@" ;;
   *) usage ;;
 esac
```

and the `# Usage` line (task.sh:3), which `usage()` prints verbatim:

```diff
-# Usage: task.sh new "<title>" [repos] [feature] | start <id> | next | status | diagnose | done <id> | sync | block <id> "<reason>" | reopen <id> | abandon <id> | clean-repo <repo> | resolve <id> "<decision>"
+# Usage: task.sh new "<title>" [repos] [feature] | start <id> | next | status | diagnose | nits | done <id> | sync | block <id> "<reason>" | reopen <id> | abandon <id> | clean-repo <repo> | resolve <id> "<decision>"
```

**2. `skills/plan/SKILL.md` step 2 — one sentence, appended.**

```diff
-2. Read the notes, `intentpipe/tasks/_log.md`, and `${CLAUDE_PLUGIN_ROOT}/scripts/task.sh status` output. Plan only what the notes ask for
+2. Read the notes, `intentpipe/tasks/_log.md`, and `${CLAUDE_PLUGIN_ROOT}/scripts/task.sh status` output. Also run `${CLAUDE_PLUGIN_ROOT}/scripts/task.sh nits` — the build never re-loops a nit (DESIGN #5), so this is the only place they are triaged: fold the ones that touch code a note in this run already changes into that task's criteria, and name the rest you are consciously leaving. Plan only what the notes ask for
```

Does the sentence pull its weight? It is the *only* reader `review.md` would have; delete it and
`task.sh nits` is a command nobody runs, and the 0085 → 0115 sequence repeats verbatim.

## Risk

- **Scope creep in /plan.** ~55 open nits could turn a three-note plan run into a cleanup sprint. The
  wording bounds it deliberately: fold in only nits that touch code the run is already changing;
  everything else is named, not planned.
- **The list only grows.** Nothing marks a nit resolved, so a fixed one keeps printing and /plan pays
  a few hundred tokens re-reading it. Accepted as the cost of not inventing a second status ledger
  (DESIGN #3). If it becomes noisy, the cheap next step is to print only tasks newer than the last
  entry in `_log.md`, not a per-nit state machine.
- **Format dependence.** `grep '\[nit\]'` assumes the format `agents/reviewer.md` mandates; a review
  that writes a bare `nit …` (0111 did) is silently missed. That is a reviewer-conformance issue, not
  a reason to loosen the grep into false positives.
- **The reviewer could start inflating nits** once it learns they reach the queue. The reviewer prompt
  already caps this ("drop anything you cannot substantiate"; "An empty report is a valid, good
  outcome") and is not being changed here.

## Confidence

**High** on the pattern — the 0085 nit and the human's bug report describe the same defect, four days
apart, and the file-reader audit is exhaustive (`grep -rn review.md scripts/ skills/ agents/`).
**Medium** on this being the best mechanism: a ledger with no resolved-state will accumulate, and the
alternative (letting the reviewer file follow-up tasks itself) was rejected only because a critic that
can create work stops being cheap.
