#!/bin/bash
# Step 2: copy the payload (repo + python + adb) into the .app bundle and write
# the profile's mac deploy.yaml.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

[ -d "$APP_BUNDLE" ] || die "Build the shell first (10-build-shell.sh). Missing: $APP_BUNDLE"
[ -d "$PAYLOAD_SRC/app" ] || die "PAYLOAD_SRC/app not found: $PAYLOAD_SRC/app (run $PAYLOAD_BUILDER)"

RES="$APP_BUNDLE/Contents/Resources"
PAYLOAD="$RES/payload"

log "Copying payload -> $PAYLOAD"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"
# Copy whatever the payload builder produced (app/, python or miniforge3/,
# platform-tools/, optionally git/).
for src in "$PAYLOAD_SRC"/*; do
  item="$(basename "$src")"
  log "  - $item"
  cp -Rc "$src" "$PAYLOAD/$item" 2>/dev/null || cp -R "$src" "$PAYLOAD/$item"
done

log "Verifying the repo is a real git checkout (needed for self-update)"
[ -d "$PAYLOAD/app/.git" ] || warn "payload/app/.git missing — in-app git update will re-init the repo on first run"

log "Writing mac deploy.yaml ($DEPLOY_TEMPLATE)"
[ -f "$DEPLOY_TEMPLATE" ] || die "deploy template not found: $DEPLOY_TEMPLATE"
cp "$DEPLOY_TEMPLATE" "$PAYLOAD/app/config/deploy.yaml"

log "Sanity-checking bundled python: payload/$PY_REL"
test -x "$PAYLOAD/$PY_REL" || die "bundled python missing/not executable: $PAYLOAD/$PY_REL"
test -x "$PAYLOAD/platform-tools/adb" || warn "bundled adb missing/not executable"
# both profiles bundle a relocatable git at payload/git (GitExecutable=../git/git)
if [ -d "$PAYLOAD/git" ]; then
  test -x "$PAYLOAD/git/git" || warn "bundled git wrapper missing/not executable: payload/git/git"
else
  warn "payload/git missing — self-update will fall back to system git"
fi

log "Step 2 done. Bundle size:"
du -sh "$APP_BUNDLE"
