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
PY="$PAYLOAD/miniforge3/envs/alas/bin/python"
PORT="$(grep -E '^\s*WebuiPort:' "$PAYLOAD/app/config/deploy.yaml" | grep -oE '[0-9]+' | head -1)"
PORT="${PORT:-22267}"
[ -x "$PY" ] || die "bundled python missing: $PY"

# --- 1. native imports ------------------------------------------------------
log "[1/2] Native extension imports (numpy / cv2 / mxnet) from the bundled python"
"$PY" -c "import numpy, cv2, mxnet; print(f'  numpy {numpy.__version__}, cv2 {cv2.__version__}, mxnet {mxnet.__version__} OK')" \
  || die "native import failed — the scheduler would crash (see dyld error above)"

# --- 2. launch the real Electron app and drive a session --------------------
log "[2/2] Launching the packaged Electron app and driving a pywebio session"
ELECTRON_BIN="$APP/Contents/MacOS/$APP_NAME"
[ -x "$ELECTRON_BIN" ] || die "electron binary missing: $ELECTRON_BIN"

# Launch from a neutral cwd (like Finder does) so the working-directory handling
# is exercised for real.
( cd "$HOME" && "$ELECTRON_BIN" >"$BUILD_DIR/electron-smoke.log" 2>&1 ) &
EPID=$!

cleanup() {
  kill "$EPID" 2>/dev/null || true
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

if [ "$rc" = 0 ]; then
  log "Smoke test PASSED: native imports OK and the GUI session rendered without errors."
else
  echo "----- gui.py log -----"; grep -iE "error|traceback|FileNotFound|assets" "$BUILD_DIR/electron-smoke.log" 2>/dev/null | tail -20
  die "GUI session failed to render (rc=$rc) — the app would show an internal error on launch."
fi
