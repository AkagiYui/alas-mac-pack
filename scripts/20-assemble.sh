#!/bin/bash
# Step 2: copy the payload (repo + conda env + adb) into the .app bundle and
# write the mac deploy.yaml.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

[ -d "$APP_BUNDLE" ] || die "Build the shell first (10-build-shell.sh). Missing: $APP_BUNDLE"
[ -d "$PAYLOAD_SRC/app" ] || die "PAYLOAD_SRC/app not found: $PAYLOAD_SRC/app (run 05-build-payload.sh)"

RES="$APP_BUNDLE/Contents/Resources"
PAYLOAD="$RES/payload"

log "Copying payload -> $PAYLOAD (large, ~2GB)"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"
# `git` is an optional legacy component (normally it lives inside the conda env).
for item in app miniforge3 platform-tools git; do
  if [ ! -e "$PAYLOAD_SRC/$item" ]; then
    [ "$item" = git ] && { log "  - (no separate git/, using env git)"; continue; }
    die "Missing payload item: $PAYLOAD_SRC/$item"
  fi
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
if [ -x "$PAYLOAD/miniforge3/envs/alas/bin/git" ]; then
  log "  bundled git: $("$PAYLOAD/miniforge3/envs/alas/bin/git" --version 2>&1)"
else
  warn "no bundled git in env — self-update will use system git"
fi
test -x "$PAYLOAD/platform-tools/adb" || warn "bundled adb missing/not executable"

log "Step 2 done. Bundle size:"
du -sh "$APP_BUNDLE"
