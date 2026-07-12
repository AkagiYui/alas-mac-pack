#!/bin/bash
# Step 4 (verify): end-to-end smoke test of the PACKAGED app on the real OS.
#
# Two checks, both against the finished .app:
#   1. the bundled python imports the native extensions (numpy/cv2/mxnet)
#      -> catches the macOS 15 duplicate-LC_RPATH dyld failure.
#   2. launch the actual Electron app and drive a real pywebio websocket
#      session (index() -> AlasGUI.run -> add_css) -> catches working-directory
#      / asset failures that a plain HTTP GET does not.
#
# Runs on a macos-15 runner so it validates on the same OS users have. If either
# check fails the build fails, so a broken artifact never ships.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

APP="$DIST_DIR/$APP_NAME.app"
[ -d "$APP" ] || APP="$APP_BUNDLE"
[ -d "$APP" ] || die "No .app to test. Run the build first."

PAYLOAD="$APP/Contents/Resources/payload"
PY="$PAYLOAD/$PY_REL"
PORT="$(grep -E '^\s*WebuiPort:' "$PAYLOAD/app/config/deploy.yaml" | grep -oE '[0-9]+' | head -1)"
PORT="${PORT:-$WEBUI_PORT}"
[ -x "$PY" ] || die "bundled python missing: $PY"

# --- 1. native imports ------------------------------------------------------
log "[1/3] Native extension imports ($SMOKE_IMPORTS) from the bundled python"
"$PY" -c "import ${SMOKE_IMPORTS// /}; print('  native imports OK: ${SMOKE_IMPORTS}')" \
  || die "native import failed — the scheduler would crash (see error above)"

# --- 2. launch the real Electron app and drive a session --------------------
log "[2/3] Launching the packaged Electron app and driving a pywebio session"
ELECTRON_BIN="$APP/Contents/MacOS/$APP_NAME"
[ -x "$ELECTRON_BIN" ] || die "electron binary missing: $ELECTRON_BIN"

# Launch from a neutral cwd (like Finder does) so the working-directory handling
# is exercised for real.
( cd "$HOME" && "$ELECTRON_BIN" >"$BUILD_DIR/electron-smoke.log" 2>&1 ) &
EPID=$!

SQPID=""   # set in check 3; declared here so cleanup() is safe under `set -u`
cleanup() {
  kill "${EPID:-}" 2>/dev/null || true
  kill -9 "${SQPID:-}" 2>/dev/null || true
  pkill -f "$APP_NAME.app/Contents/MacOS" 2>/dev/null || true
  pkill -f "payload/app/gui.py" 2>/dev/null || true
}
trap cleanup EXIT

log "Waiting for the webui on :$PORT (max 120s)..."
up=0
for i in $(seq 1 40); do
  if curl -fsS -o /dev/null --max-time 3 "http://127.0.0.1:$PORT/"; then up=1; break; fi
  sleep 3
done
[ "$up" = 1 ] || { echo "----- electron log -----"; tail -40 "$BUILD_DIR/electron-smoke.log" 2>/dev/null; die "webui never came up (electron failed to launch or spawn python)"; }

# Confirm the python worker's cwd is the repo root (the CSS bug = wrong cwd).
worker="$(pgrep -f 'payload/app/gui.py' | head -1)"
if [ -n "$worker" ]; then
  cwd="$(lsof -a -p "$worker" -d cwd -Fn 2>/dev/null | grep '^n' | cut -c2-)"
  log "python worker cwd: ${cwd:-unknown}"
fi

log "Opening a real pywebio session (runs index() -> add_css)"
"$PY" "$REPO_ROOT/scripts/webui-session-check.py" "$PORT"
rc=$?

if [ "$rc" != 0 ]; then
  echo "----- gui.py log -----"; grep -iE "error|traceback|FileNotFound|assets" "$BUILD_DIR/electron-smoke.log" 2>/dev/null | tail -20
  die "GUI session failed to render (rc=$rc) — the app would show an internal error on launch."
fi
log "  GUI session rendered OK"

# --- 3. stale-backend port reclaim (anti-hijack) ----------------------------
# Regression guard for the "./assets/gui/css/alas.css FileNotFoundError on
# launch" bug: when a previous / older instance leaves a server on the webui
# port, the app must kill it and serve from its OWN backend, not attach to the
# stale one (whose working directory may point at a moved/deleted bundle).
# Simulate a foreign squatter holding the port, relaunch, and require a clean
# render — this fails on the old "bind on address == ready" behaviour.
log "[3/3] Stale-backend port reclaim (anti-hijack)"
cleanup            # stop check-2's app so the port is free to squat
# Free the port for real: check-2's webui listener is a uvicorn multiprocessing
# child (python -c "...spawn_main...") that pkill-by-name misses, so kill
# whatever still holds the port until it's actually free.
for _ in $(seq 1 15); do
  pids=$(/usr/sbin/lsof -ti "tcp:$PORT" 2>/dev/null || true)
  [ -z "$pids" ] && break
  # shellcheck disable=SC2086
  kill -9 $pids 2>/dev/null || true
  sleep 1
done

# A foreign server: binds the port but never speaks HTTP/websocket. If the app
# wrongly attached to it (the old bug), the pywebio session can't render.
"$PY" -c "import socket,time
s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(('127.0.0.1',$PORT)); s.listen(16); time.sleep(180)" &
SQPID=$!
sleep 2
kill -0 "$SQPID" 2>/dev/null || die "test squatter failed to bind :$PORT"
log "  foreign squatter holding :$PORT (pid $SQPID)"

( cd "$HOME" && "$ELECTRON_BIN" >"$BUILD_DIR/electron-smoke-reclaim.log" 2>&1 ) &
EPID=$!            # let cleanup() (EXIT trap) also kill this relaunched app

log "  relaunched; app must reclaim :$PORT and render its own webui"
up=0
for _ in $(seq 1 40); do
  if "$PY" "$REPO_ROOT/scripts/webui-session-check.py" "$PORT" >/dev/null 2>&1; then up=1; break; fi
  sleep 3
done
kill -9 "$SQPID" 2>/dev/null || true; wait "$SQPID" 2>/dev/null || true
if [ "$up" != 1 ]; then
  echo "----- reclaim log -----"; grep -iE "bind|error|traceback|assets" "$BUILD_DIR/electron-smoke-reclaim.log" 2>/dev/null | tail -20
  die "app did NOT reclaim :$PORT from a stale backend — it would hijack the stale server and fail with the assets FileNotFoundError."
fi
log "  reclaimed the port and rendered its own webui"

log "Smoke test PASSED: native imports OK, GUI renders, and stale-port reclaim works."
