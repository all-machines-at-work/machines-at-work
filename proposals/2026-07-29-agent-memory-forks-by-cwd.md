# Retro 2026-07-29 · agent memory forks by working directory, so lessons stop being delivered

Proposal — **apply by hand**: `intentpipe/scripts/{loop.sh,preflight.sh}` and
`server-orchestrator/daemon.py` (both read-only inside projects). Evidence window: tasks 0043–0121
(everything merged after the 2026-07-08 reports).

## Evidence

`agents/implementer.md:5` and `agents/reviewer.md:5` both declare `memory: project`. In the bibbles
workspace that store has silently split into **three live copies plus two empty ones** (all
git-tracked, dates are the first commit that added each file):

| store | first / last write | contents |
|---|---|---|
| `bibbles/.claude/agent-memory/` | 2026-07-20 | implementer: 4 topics; reviewer: 1 topic |
| `bibbles/intentpipe/.claude/agent-memory/` | 2026-07-24 → 2026-07-27 | implementer: 5 topics; reviewer: 4 topics |
| `bibbles/intentpipe/tasks/0104-…/.claude/agent-memory/` | 2026-07-27 | implementer: 1 topic, `type: feedback` |
| `intentpipe/tasks/.claude/agent-memory/` | — | empty |
| `intentpipe/tasks/0108-…/.claude/agent-memory/` | — | empty |

Only one of these is loaded on any given run — whichever matches that session's working directory.
The split is not cosmetic; the two halves hold different eras of the project:

- The **root** store's reviewer index ends at task 0073 (`…0073 persona prose→persona_content/*.md
  files…`). It knows nothing about 0099, 0104, 0107 or 0108.
- The **`intentpipe/`** store holds every lesson learned since the Telegram triggers went live:
  `review_retired_catalog_keys.md` (0099), `review_deletion_tasks_consumers.md` (0104),
  `review_pixel_art_criteria.md` (0107), `review_frontend_integration_tests.md` (0108),
  `project_frontend_integration_test_stale.md`, `project_no_dart_format.md`,
  `project_flutter_layout_screenshot.md`, `project_ephemeral_purchase_preconditions.md`.
  An interactive `/intentpipe:build` started at the project root today loads **none** of them.
- The **`tasks/0104-…/`** store holds a `metadata: type: feedback` entry — the highest-weight kind,
  human-authored — stranded where nothing can ever load it:

  > On a deletion task, walk every consumer of the endpoint/table being removed — not just the ones
  > the task's goal names … task 0104 deleted `GET /assets` for the accessory overlay; the same
  > endpoint also fed the photo-derived life asset in the room.

  The very next task, **0105 "Dead-code and duplication sweep across both repos"**, then missed the
  stranded widget that 0104's reviewer had named and predicted would be missed:

  > [nit] frontend/lib/bibble/life_asset.dart:92 — `LifeAssetView` … now has zero readers in `lib/`
  > and `test/`. … the Notes' hand-off list for 0105 names only `BibbleManifest` and
  > `BibbleShapeParams`, so this widget would be missed.

  Checked on `main` today: `LifeAssetView` is still at `frontend/lib/bibble/life_asset.dart:81`, its
  stale doc comment still at `life_asset_pixel.dart:167`, and the dead `unlockedKeys` still at
  `frontend/test/chat_photo_share_test.dart:78`.

Cross-check that the loss is real and not merely theoretical: `frontend/integration_test/` staleness
was re-derived from scratch by three separate reviewers (0042, 0072, 0108) before anyone wrote it
down — and when it finally *was* written down, it went into the store the interactive path cannot
see.

## Root cause

Claude Code resolves `memory: project` from the **session's working directory**, and nothing in the
pipeline ever normalizes that directory:

- `scripts/lib.sh:7-16` — `find_workspace()` deliberately walks up from `$PWD`, so every script works
  identically from the project root, from `intentpipe/`, or from inside a repo. Correct for the
  scripts; it also means cwd is never pinned.
- `scripts/loop.sh:15` — the comment says "Run from the project root", but nothing enforces it, and
  line 162 invokes `claude -p` with whatever cwd it inherited.
- `server-orchestrator/daemon.py` — `dispatch()` does
  `name, workspace = entry["name"], entry["workspace"]` … `spawn_detached(cmd, workspace, base, …)`,
  and `~/.agent-orchestrator/registry.json` sets
  `"workspace": "/home/agent/projects/bibbles/intentpipe"`. So **every** 🚀 / 🧠 / 🩹 run has
  cwd = `intentpipe/`, while a human's interactive session sits at the project root. The fork
  date (first file 2026-07-24) is the day the trigger daemon started driving this project.

The third store (`tasks/0104-…/`) is the same bug one level deeper: an agent that `cd`s into a task
folder writes its memory there.

## Proposed change

Three parts. (1) and (2) stop new forks; (3) makes a fork impossible to miss.

**1. `scripts/loop.sh` — pin cwd to the project root (after line 31).**

```diff
 SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 source "$SCRIPTS/lib.sh"
+# `claude -p` below resolves the agents' `memory: project` store from cwd, so every
+# caller must agree on one directory or the implementer's and reviewer's lessons
+# fork per launcher. The project root (parent of the workspace) is that directory.
+cd "$(dirname "$WS")"
```

**2. `server-orchestrator/daemon.py` — spawn triggers from the project root, not the workspace.**

```diff
     try:
-        pid = spawn_detached(cmd, workspace, base,
+        # The agents declare `memory: project`, which resolves from cwd. The registry's
+        # workspace is <root>/intentpipe, so spawning there gives headless runs a
+        # different memory store than an interactive session at the project root.
+        root = os.path.dirname(workspace) if os.path.basename(workspace) == "intentpipe" else workspace
+        pid = spawn_detached(cmd, root, base,
                              track={"name": name, "action": action, "topic": thread_id})
```

Everything else keeps using `workspace` unchanged — inbox writes (`write_image_inbox`), `task.sh
resolve` (line 522), `checkout_options`. Only the spawn cwd moves.

**3. `scripts/preflight.sh` — fail on a forked store (after the `[ -d "$TASKS" ]` check, line 41).**

```diff
 [ -d "$TASKS" ] || { echo "FAIL: no tasks/ dir (run /intentpipe:init-project)" >&2; err=1; }
+# The agents declare `memory: project`, which Claude Code resolves from cwd. A store
+# anywhere but the project root means a launcher ran from the wrong directory and the
+# lessons written there are invisible to every other launcher.
+for stray in "$WS/.claude/agent-memory" "$TASKS"/.claude/agent-memory "$TASKS"/*/.claude/agent-memory; do
+  [ ! -d "$stray" ] || { echo "FAIL: agent memory forked into $stray — merge its files into $(dirname "$WS")/.claude/agent-memory and delete it" >&2; err=1; }
+done
```

**One-off human action, outside the diff:** merge the three bibbles stores into
`/home/agent/projects/bibbles/.claude/agent-memory/` (union of the topic files, both `MEMORY.md`
indexes concatenated) and delete the strays. `/retro` may not edit agent memory, so this cannot be
done from here — and until it is, preflight will (correctly) refuse.

## Risk

- `cd` in `loop.sh` changes cwd for everything the loop invokes. Audited: `loop.sh` and `lib.sh` use
  `$SCRIPTS`, `$WS` and `repo_path` absolutes throughout, and `find_workspace()` still resolves from
  the project root, so nothing relative breaks. A project whose `AFTER_DONE` hook assumed a
  `intentpipe/`-relative cwd would — the template's own example already passes
  `"$INTENTPIPE_WORKSPACE"` explicitly.
- The daemon change is a no-op for any registry entry not ending in `intentpipe`.
- The preflight check turns an existing fork into a hard PREFLIGHT FAILED, which will block the next
  build until a human merges the stores. That is the intent, but it means part 3 must not land before
  someone is available to do the merge.
- Merging two `MEMORY.md` indexes by hand can produce a duplicated or contradictory line; the topic
  files themselves are disjoint here (no filename collides across the three stores), so only the two
  index files need care.

## Confidence

**High.** The mechanism is verifiable end to end — the registry cwd, the fork dates matching the
trigger rollout, two disjoint stores with disjoint task eras, and a concrete downstream miss (0105
failing exactly the way the stranded 0104 feedback file warns about) — and the fix is three lines
plus a guard.
