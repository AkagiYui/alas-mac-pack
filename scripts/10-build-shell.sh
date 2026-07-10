#!/bin/bash
# Step 1: install deps, bundle the vite packages, and produce the .app shell
# (no payload yet) via electron-builder --dir.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

cd "$WEBAPP_BUILD"

if [ ! -d node_modules ]; then
  log "Installing npm dependencies (this downloads Electron, takes a while)"
  npm install --no-audit --no-fund
else
  log "node_modules present, skipping npm install"
fi

log "Bundling main/preload/renderer (vite, production)"
cross_env=""
MODE=production npm run build

log "Packaging .app shell (electron-builder --dir, $ARCH)"
[ -n "$APP_VERSION" ] && export VITE_APP_VERSION="$APP_VERSION"
npx electron-builder build --config electron-builder.config.js --dir --arm64

[ -d "$APP_BUNDLE" ] || die "Expected app bundle not found: $APP_BUNDLE"
log "Step 1 done -> $APP_BUNDLE"
