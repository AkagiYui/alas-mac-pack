#!/bin/bash
# Step 0: copy the upstream Electron shell into the build workdir and overlay
# the small mac-specific patches. The upstream source is pulled from the cloned
# repo by 05-build-payload.sh (WEBAPP_SRC=build/webapp-upstream) — nothing
# upstream is stored in this repo.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

[ -d "$WEBAPP_SRC" ] || die "WEBAPP_SRC not found: $WEBAPP_SRC — run 05-build-payload.sh first (it extracts webapp/ from the upstream clone)"

log "Copying webapp source -> $WEBAPP_BUILD"
mkdir -p "$WEBAPP_BUILD"
rsync -a --delete \
  --exclude node_modules --exclude dist \
  "$WEBAPP_SRC"/ "$WEBAPP_BUILD"/

log "Applying overlay ($PROFILE): $OVERLAY_DIR"
# The overlay mirrors the webapp tree; anything under OVERLAY_DIR replaces the
# upstream file of the same path. Keeps patches robust (no diff fuzz).
rsync -a "$OVERLAY_DIR"/ "$WEBAPP_BUILD"/

# The app icon (buildResources/icon.icns) comes from upstream and is then
# replaced by 06-make-icons.sh with the generated squircle icon.
log "Step 0 done."
