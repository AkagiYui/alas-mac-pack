#!/bin/bash
# Step 3: ad-hoc sign the finished bundle, copy it to dist/, and build a DMG.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

[ -d "$APP_BUNDLE" ] || die "Nothing to package. Run steps 10 + 20 first."

mkdir -p "$DIST_DIR"
FINAL_APP="$DIST_DIR/$APP_NAME.app"

log "Staging bundle -> $FINAL_APP"
rm -rf "$FINAL_APP"
cp -Rc "$APP_BUNDLE" "$FINAL_APP" 2>/dev/null || cp -R "$APP_BUNDLE" "$FINAL_APP"

log "Clearing quarantine xattrs"
xattr -cr "$FINAL_APP" || true

# Re-seal the bundle after the payload was added. Ad-hoc ("-") signature, no
# hardened runtime — this is an UNSIGNED distribution, users approve on first
# launch (right-click > Open, or `xattr -cr`). We sign top-level only so the
# already-valid signatures of the bundled python/git/adb are left intact.
log "Ad-hoc signing (top-level re-seal)"
codesign --force --sign - --timestamp=none "$FINAL_APP" \
  || warn "codesign failed; app will still run after 'xattr -cr'"

log "Signature summary:"
codesign -dv "$FINAL_APP" 2>&1 | sed 's/^/    /' || true

# --- DMG --------------------------------------------------------------------
VER="${APP_VERSION:-$(date +%Y.%m.%d)}"
DMG_OUT="$DIST_DIR/${APP_NAME}-mac-${ARCH}-${VER}.dmg"
log "Building DMG -> $DMG_OUT"
rm -f "$DMG_OUT" "$DIST_DIR"/rw.*.dmg

BG_ARG=()
[ -f "$REPO_ROOT/assets/background.png" ] && BG_ARG=(--background "$REPO_ROOT/assets/background.png")

# Use the generated app icon (06-make-icons.sh) as the volume icon when present.
VOLICON_ARG=()
[ -f "$WEBAPP_BUILD/buildResources/icon.icns" ] && VOLICON_ARG=(--volicon "$WEBAPP_BUILD/buildResources/icon.icns")

# ULMO = LZMA-compressed dmg (much smaller than the create-dmg default UDZO/zlib),
# on an APFS filesystem — same as the original release_dmg.sh.
create-dmg \
  --volname "$APP_NAME" \
  "${VOLICON_ARG[@]}" \
  "${BG_ARG[@]}" \
  --format ULMO \
  --filesystem APFS \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 200 190 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 600 185 \
  --no-internet-enable \
  "$DMG_OUT" \
  "$FINAL_APP" \
  || die "create-dmg failed"

log "Step 3 done."
log "App: $FINAL_APP"
log "DMG: $DMG_OUT"
du -sh "$FINAL_APP" "$DMG_OUT"
