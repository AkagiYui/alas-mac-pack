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

# Do NOT re-seal the whole bundle. A valid top-level code signature seals the
# payload (incl. app/config/deploy.yaml) into CodeResources; on macOS 13+
# (App Management protection) the app can no longer replace those sealed files
# from inside its own bundle, so changing the language / editing config / the
# git self-update all fail with `PermissionError: Operation not permitted` on
# os.replace(). ALAS is a "green" app — all state lives inside the .app — so the
# bundle must stay un-sealed, exactly like the original release_dmg.sh (which
# never ran codesign). The electron-builder shell already carries the adhoc
# signatures arm64 needs to launch (identity:null), and the payload binaries
# (python/git/adb, re-signed by fix-env-rpaths.py) keep their own signatures.
# Users approve the unsigned app on first launch (right-click > Open, or the
# `xattr -c` shown on the DMG background).
log "Skipping top-level re-seal (keeps the bundle writable for in-app config + self-update)"
log "Signature summary (electron-builder shell, unsealed bundle):"
codesign -dv "$FINAL_APP" 2>&1 | sed 's/^/    /' || true

# --- DMG --------------------------------------------------------------------
VER="${APP_VERSION:-$(date +%Y.%m.%d)}"
DMG_OUT="$DIST_DIR/${APP_NAME}-mac-${ARCH}-${VER}.dmg"
log "Building DMG -> $DMG_OUT"
rm -f "$DMG_OUT" "$DIST_DIR"/rw.*.dmg

BG_ARG=()
[ -f "$BUILD_DIR/dmg-background.png" ] && BG_ARG=(--background "$BUILD_DIR/dmg-background.png")

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
