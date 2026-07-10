#!/bin/bash
# Step 1: install deps, bundle the vite packages, and produce the .app shell
# (no payload yet) via electron-builder --dir.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

# This 2023-era toolchain (vite 2, electron-builder 22) needs Node <= 18.
# Node >= 20 fails with a JSON import-attribute error. Locally we hop to a
# fnm-managed Node 18; CI pins Node 18 via actions/setup-node so this is a no-op.
NODE_MAJOR="$(node -v 2>/dev/null | sed 's/v\([0-9]*\).*/\1/')"
if [ "${NODE_MAJOR:-0}" -ge 20 ]; then
  if command -v fnm >/dev/null 2>&1; then
    warn "Node $NODE_MAJOR is too new for this toolchain; re-running under fnm Node 18"
    exec fnm exec --using=18 bash "$0" "$@"
  fi
  die "Need Node <= 18 to build (current: $(node -v)). Install Node 18 or run in CI."
fi

cd "$WEBAPP_BUILD"

if [ ! -d node_modules ]; then
  log "Installing npm dependencies (downloads Electron, takes a while)"
  npm install --no-audit --no-fund
else
  log "node_modules present, skipping npm install"
fi

log "Bundling main/preload/renderer (vite, production)"
MODE=production npm run build

log "Packaging .app shell (electron-builder --dir, $ARCH)"
[ -n "$APP_VERSION" ] && export VITE_APP_VERSION="$APP_VERSION"
npx electron-builder build --config electron-builder.config.js --dir --arm64

[ -d "$APP_BUNDLE" ] || die "Expected app bundle not found: $APP_BUNDLE"
log "Step 1 done -> $APP_BUNDLE"
