#!/bin/bash
# Step 0: copy the upstream Electron shell into the build workdir and overlay
# the small mac-specific patches (config.ts + electron-builder.config.js).
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

[ -d "$WEBAPP_SRC" ] || die "WEBAPP_SRC not found: $WEBAPP_SRC"

log "Copying webapp source -> $WEBAPP_BUILD"
mkdir -p "$WEBAPP_BUILD"
rsync -a --delete \
  --exclude node_modules --exclude dist \
  "$WEBAPP_SRC"/ "$WEBAPP_BUILD"/

log "Applying overlay (mac patches)"
# The overlay mirrors the webapp tree; anything under overlay/ replaces the
# vendored file of the same path. Keeps patches robust (no diff fuzz).
rsync -a "$REPO_ROOT/overlay"/ "$WEBAPP_BUILD"/

log "Ensuring icon.icns is present in buildResources"
cp "$REPO_ROOT/assets/icon.icns" "$WEBAPP_BUILD/buildResources/icon.icns"

log "Step 0 done."
