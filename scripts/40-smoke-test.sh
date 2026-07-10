#!/bin/bash
# Step 4 (verify): headless check that the bundled python + payload actually work.
# Launches gui.py exactly like the Electron PyShell does and confirms the webui
# answers on the configured port. No GUI / Electron needed, so it runs on a
# headless CI runner.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

# Prefer the freshly packaged bundle in dist/, fall back to the build output.
APP="$DIST_DIR/$APP_NAME.app"
[ -d "$APP" ] || APP="$APP_BUNDLE"
[ -d "$APP" ] || die "No .app to test. Run the build first."

PAYLOAD="$APP/Contents/Resources/payload"
PY="$PAYLOAD/miniforge3/envs/alas/bin/python"
PORT="$(grep -E '^\s*WebuiPort:' "$PAYLOAD/app/config/deploy.yaml" | grep -oE '[0-9]+' | head -1)"
PORT="${PORT:-22267}"

[ -x "$PY" ] || die "bundled python missing: $PY"
log "Using python: $($PY -V 2>&1)  port: $PORT"

LOG="$BUILD_DIR/smoke.log"
( cd "$PAYLOAD/app" && "$PY" -u gui.py --port "$PORT" --electron > "$LOG" 2>&1 ) &
GPID=$!

log "Waiting for webui to come up (max 90s)..."
ok=0
for i in $(seq 1 45); do
  if curl -fsS -o /dev/null --max-time 3 "http://127.0.0.1:$PORT/"; then ok=1; break; fi
  # bail early if the python already died
  kill -0 "$GPID" 2>/dev/null || { pgrep -f "gui.py --port $PORT" >/dev/null || break; }
  sleep 2
done

code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$PORT/" || true)"
log "HTTP status from webui: ${code:-none}"

log "Deploy module resolves bundled executables:"
( cd "$PAYLOAD/app" && "$PY" - <<'PYEOF'
from deploy.Windows.config import DeployConfig
import os
c = DeployConfig()
for name, val in (("git", c.git), ("python", c.python), ("adb", c.adb)):
    print(f"  {name:6} -> {val}  (exists={os.path.exists(val)})")
PYEOF
)

# cleanup
pkill -P "$GPID" 2>/dev/null || true
kill "$GPID" 2>/dev/null || true
pkill -f "gui.py --port $PORT" 2>/dev/null || true

if [ "$ok" = 1 ] && [ "$code" = "200" ]; then
  log "Smoke test PASSED (webui served HTTP 200)."
else
  echo "----- gui.py log -----"; tail -40 "$LOG" 2>/dev/null || true
  die "Smoke test FAILED (webui did not return 200)."
fi
