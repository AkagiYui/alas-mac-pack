#!/bin/bash
# Step 2: copy the payload (repo + python + git + adb) into the .app bundle and
# write the mac deploy.yaml.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

[ -d "$APP_BUNDLE" ] || die "Build the shell first (10-build-shell.sh). Missing: $APP_BUNDLE"
[ -d "$PAYLOAD_SRC/app" ] || die "PAYLOAD_SRC/app not found: $PAYLOAD_SRC/app"

RES="$APP_BUNDLE/Contents/Resources"
PAYLOAD="$RES/payload"

log "Copying payload -> $PAYLOAD (large, ~2GB)"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"
for item in app miniforge3 git platform-tools; do
  [ -e "$PAYLOAD_SRC/$item" ] || die "Missing payload item: $PAYLOAD_SRC/$item"
  log "  - $item"
  cp -Rc "$PAYLOAD_SRC/$item" "$PAYLOAD/$item" 2>/dev/null \
    || cp -R "$PAYLOAD_SRC/$item" "$PAYLOAD/$item"
done

log "Verifying the repo is a real git checkout (needed for self-update)"
[ -d "$PAYLOAD/app/.git" ] || warn "payload/app/.git missing — in-app git update will re-init the repo on first run"

log "Writing mac deploy.yaml"
cp "$REPO_ROOT/config/deploy.mac.yaml" "$PAYLOAD/app/config/deploy.yaml"

log "Sanity-checking bundled executables"
test -x "$PAYLOAD/miniforge3/envs/alas/bin/python" || die "bundled python missing/not executable"
test -x "$PAYLOAD/git/bin/git"                      || die "bundled git missing/not executable"
test -x "$PAYLOAD/platform-tools/adb"               || warn "bundled adb missing/not executable"

log "Step 2 done. Bundle size:"
du -sh "$APP_BUNDLE"
