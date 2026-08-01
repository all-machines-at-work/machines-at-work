#!/usr/bin/env bash
# Inbound comms seam (mirror of notify.sh's outbound leg). The scaffold owns
# both legs of its own Telegram topic. It cannot hold the inbound stream itself:
# a shared bot's getUpdates is single-consumer and the plugin has no always-on
# process, so a separate server-side orchestrator is the one persistent consumer.
# That orchestrator demuxes by topic and drops each raw message for this project
# into <workspace>/updates/.inbox/ — the whole cross-project contract. This
# script turns those raw messages into updates/ intent notes — and any image
# dropped alongside (a photo texted into the topic) into a permanent file under
# resources/, with the note's reference rewritten to point at it. Note naming
# and format are the plugin's business, not the server's. Tolerant by design:
# no workspace, no inbox, nothing queued → no-op, never fails its caller.
set -euo pipefail
shopt -s nullglob

# Find the workspace (dir holding agents.env — directly or in an
# intentpipe/ child), same walk-up as notify.sh.
dir="$PWD"; ws=""
while [ "$dir" != "/" ]; do
  if [ -f "$dir/agents.env" ]; then ws="$dir"; break; fi
  if [ -f "$dir/intentpipe/agents.env" ]; then ws="$dir/intentpipe"; break; fi
  dir="$(dirname "$dir")"
done
[ -n "$ws" ] || { echo "[inbound] no workspace found; nothing to drain" >&2; exit 0; }

inbox="$ws/updates/.inbox"
[ -d "$inbox" ] || exit 0   # server has delivered nothing

# Where a session (running at the project root) reaches resources/ from: the
# workspace is either an intentpipe/ child of the project or the project
# root itself.
case "$(basename "$ws")" in
  intentpipe) rel="intentpipe/resources" ;;
  *)          rel="resources" ;;
esac

# Images first: the server drops a photo as <epoch>-<msgid>.<ext> next to its
# caption note, which references it by bare basename ([image: <basename>]).
# Images become permanent resources (notes are deleted once planned; the tasks
# they spawn keep pointing at the image), so they move to resources/, and each
# note's reference is rewritten to the path a session actually reads.
img=0
for f in "$inbox"/*; do
  [ -f "$f" ] || continue
  case "$f" in *.md) continue ;; esac
  mkdir -p "$ws/resources"
  mv "$f" "$ws/resources/tg-$(basename "$f")"
  img=$((img + 1))
done

# Oldest first (server names files <epoch>-<msgid>.md, so lexical = chronological)
# so a multi-message intent keeps its order. Move, don't copy: a drained message
# is a note now, and re-draining must not duplicate it. Only bare-basename image
# references are rewritten (no slash) — an already-pathed reference stays as-is.
n=0
for f in "$inbox"/*.md; do
  sed -i "s|\[image: \([^]/]*\)\]|[image: $rel/tg-\1]|g" "$f"
  mv "$f" "$ws/updates/tg-$(basename "$f")"
  n=$((n + 1))
done
[ "$((n + img))" -gt 0 ] && echo "[inbound] drained $n message(s), $img image(s) into updates/"
exit 0
