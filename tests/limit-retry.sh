#!/usr/bin/env bash
# Functional test: loop.sh must ride out a usage-limit exit (park WIP, wait,
# retry the same task) instead of blocking it. Uses a fake `claude` on PATH
# that dies with a limit message mid-task, then finishes the task on retry.
set -euo pipefail
INTENTPIPE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "LIMIT-RETRY FAIL: $*" >&2; exit 1; }

WS="$TMP/ws"; mkdir -p "$WS/app" "$WS/intentpipe/tasks"
git -C "$WS" init -qb main && git -C "$WS" config user.email t@t && git -C "$WS" config user.name t
git -C "$WS/app" init -qb main
git -C "$WS/app" -c user.email=t@t -c user.name=t commit -qm init --allow-empty
cat > "$WS/intentpipe/agents.env" <<'EOF'
PROJECT_NAME=limitretry
DEFAULT_BRANCH=main
REPOS="app"
REPO_app=../app
VERIFY_app="test -f ok.txt"
EOF
echo ok > "$WS/app/ok.txt"
git -C "$WS/app" add . && git -C "$WS/app" -c user.email=t@t -c user.name=t commit -qm "add ok"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<EOF
#!/usr/bin/env bash
FAKE_DIR="$TMP" INTENTPIPE="$INTENTPIPE" exec bash "$TMP/fake-claude-body.sh"
EOF
cat > "$TMP/fake-claude-body.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
n=$(cat "$FAKE_DIR/count" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$FAKE_DIR/count"
if [ "$n" -eq 1 ]; then
  # simulate /build: start task, leave tracked + untracked WIP, die on a usage limit
  "$INTENTPIPE/scripts/task.sh" start 0001 >/dev/null
  echo "wip line" >> app/wip.txt
  echo "tracked change" >> app/ok.txt   # tracked dirt: must be parked or retry fails preflight
  echo "Claude AI usage limit reached|9999999999"   # absurd epoch -> fallback backoff path
  exit 1
fi
# retry: tree must be clean (loop parked WIP) and task resumable
git -C app diff --quiet || { echo "RETRY SAW DIRTY TREE" >&2; exit 3; }
"$INTENTPIPE/scripts/task.sh" start 0001 >/dev/null    # resume in-progress
git -C app add -A
git -C app -c user.email=t@t -c user.name=t commit -qm "finish work" 2>/dev/null || true
"$INTENTPIPE/scripts/task.sh" done 0001 >/dev/null
echo '{"total_cost_usd": 0.05}'
EOF
chmod +x "$TMP/bin/claude"

cd "$WS"
"$INTENTPIPE/scripts/task.sh" new "Limit retry feature" >/dev/null

out=$(PATH="$TMP/bin:$PATH" LIMIT_BACKOFF=2 MAX_TASKS=3 bash "$INTENTPIPE/scripts/loop.sh" 2>&1) || fail "loop.sh exited nonzero: $out"

[ "$(cat "$TMP/count")" = 2 ] || fail "expected 2 claude calls, got $(cat "$TMP/count")"
echo "$out" | grep -q "usage limit on 0001" || fail "no limit-retry log line: $out"
grep -q "Status: done" intentpipe/tasks/0001-*/task.md || fail "task not done after retry"
[ ! -s intentpipe/NEEDS_HUMAN.md ] || fail "task was escalated: $(cat intentpipe/NEEDS_HUMAN.md)"
git -C app log -1 main --format=%B | grep -q "Task-Id: 0001" || fail "no squash commit on main"
git -C app show main:wip.txt | grep -q "wip line" || fail "untracked WIP lost"
git -C app show main:ok.txt | grep -q "tracked change" || fail "parked tracked WIP lost"

# --- A limit that never clears must be BOUNDED and QUIET. Unbounded retries polled
# one task for 3.5h and pinged Telegram on all seven attempts. The cap turns that
# into a decision the human can act on, and the notification budget is two: the
# first wait (explains a stalled loop) and giving up. TELEGRAM_ENV is pointed at a
# missing file so notify.sh prints without sending anything anywhere.
WS2="$TMP/ws2"; mkdir -p "$WS2/app" "$WS2/intentpipe/tasks"
git -C "$WS2" init -qb main && git -C "$WS2" config user.email t@t && git -C "$WS2" config user.name t
git -C "$WS2/app" init -qb main
git -C "$WS2/app" -c user.email=t@t -c user.name=t commit -qm init --allow-empty
sed "s|../app|../app|" "$WS/intentpipe/agents.env" > "$WS2/intentpipe/agents.env"
echo ok > "$WS2/app/ok.txt"
git -C "$WS2/app" add . && git -C "$WS2/app" -c user.email=t@t -c user.name=t commit -qm "add ok"

mkdir -p "$TMP/bin2"
cat > "$TMP/bin2/claude" <<EOF
#!/usr/bin/env bash
FAKE_DIR="$TMP" INTENTPIPE="$INTENTPIPE" exec bash "$TMP/always-limit.sh"
EOF
cat > "$TMP/always-limit.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
n=$(cat "$FAKE_DIR/count2" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$FAKE_DIR/count2"
"$INTENTPIPE/scripts/task.sh" start 0001 >/dev/null 2>&1 || true
echo "Claude AI usage limit reached|9999999999"   # absurd epoch -> fallback backoff path
exit 1
EOF
chmod +x "$TMP/bin2/claude"

cd "$WS2"
"$INTENTPIPE/scripts/task.sh" new "Never clears" >/dev/null
rc=0
out2=$(PATH="$TMP/bin2:$PATH" TELEGRAM_ENV=/nonexistent LIMIT_BACKOFF=1 MAX_LIMIT_RETRIES=3 MAX_TASKS=3 \
       bash "$INTENTPIPE/scripts/loop.sh" 2>&1) || rc=$?
[ "$rc" -eq 5 ] || fail "expected exit 5 (limit not clearing), got $rc: $out2"
# 3 retries = 3 sessions that hit the limit, then the 4th refuses to wait again.
[ "$(cat "$TMP/count2")" = 4 ] || fail "expected 4 claude calls, got $(cat "$TMP/count2")"
echo "$out2" | grep -q "usage limit on 0001 (1/3)" || fail "retries must be counted: $out2"
echo "$out2" | grep -q "still not cleared after 3 retries" || fail "no give-up line: $out2"
pings=$(echo "$out2" | grep -c "\[notify\].*usage limit" || true)
[ "$pings" -eq 2 ] || fail "expected 2 usage-limit notifications (first + give-up), got $pings: $out2"
echo "LIMIT-RETRY OK"
