#!/bin/bash
# Step 0.5: build the payload from scratch (no prebuilt archive):
#   - clone the AzurLaneAutoScript repo               -> payload/app
#   - copy the conda env `alas`                       -> payload/miniforge3/envs/alas
#   - download Android platform-tools (adb)           -> payload/platform-tools
#
# The conda env `alas` must already exist (created from config/environment.yml
# via `conda env create`). In CI this is done by the setup-miniconda step; the
# script auto-detects the env prefix from `conda`.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

PAYLOAD="$BUILD_DIR/payload"
log "Building payload -> $PAYLOAD"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"

# --- 1. app repo ------------------------------------------------------------
log "Cloning $ALAS_REPO ($ALAS_BRANCH)"
git clone --depth 1 --branch "$ALAS_BRANCH" "$ALAS_REPO" "$PAYLOAD/app"
# keep .git — the in-app self-update needs a real checkout
"$PAYLOAD/app/.git" >/dev/null 2>&1 || true
[ -d "$PAYLOAD/app/.git" ] || die "cloned repo has no .git"
# Trim what the release build doesn't need.
rm -rf "$PAYLOAD/app/.github" "$PAYLOAD/app/webapp" "$PAYLOAD/app/log"

# --- 2. conda env -----------------------------------------------------------
prefix="$CONDA_ENV_PREFIX"
if [ -z "$prefix" ]; then
  command -v conda >/dev/null 2>&1 || die "conda not found and CONDA_ENV_PREFIX not set"
  prefix="$(conda env list | awk -v n="$CONDA_ENV_NAME" '$1==n {print $NF}')"
fi
[ -n "$prefix" ] && [ -x "$prefix/bin/python" ] || die "conda env '$CONDA_ENV_NAME' not found (prefix='$prefix')"
log "Copying conda env from $prefix"
mkdir -p "$PAYLOAD/miniforge3/envs"
# Follow symlinks so the env is self-contained inside the bundle.
cp -RL "$prefix" "$PAYLOAD/miniforge3/envs/$CONDA_ENV_NAME"
# Drop caches to shrink the payload.
find "$PAYLOAD/miniforge3" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
rm -rf "$PAYLOAD/miniforge3/envs/$CONDA_ENV_NAME/pkgs" 2>/dev/null || true

# --- 3. platform-tools (adb) ------------------------------------------------
log "Downloading platform-tools"
tmp="$BUILD_DIR/platform-tools.zip"
curl -fsSL "$PLATFORM_TOOLS_URL" -o "$tmp"
( cd "$BUILD_DIR" && rm -rf platform-tools && unzip -q "$tmp" )
mv "$BUILD_DIR/platform-tools" "$PAYLOAD/platform-tools"
rm -f "$tmp"
test -x "$PAYLOAD/platform-tools/adb" || die "adb not found after extract"

log "Payload built:"
du -sh "$PAYLOAD"/* 2>/dev/null || true
log "python: $("$PAYLOAD/miniforge3/envs/$CONDA_ENV_NAME/bin/python" -V 2>&1)"
if [ -x "$PAYLOAD/miniforge3/envs/$CONDA_ENV_NAME/bin/git" ]; then
  log "git (bundled): $("$PAYLOAD/miniforge3/envs/$CONDA_ENV_NAME/bin/git" --version)"
else
  warn "git not bundled in env — the app will fall back to system git"
fi
