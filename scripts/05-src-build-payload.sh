#!/bin/bash
# Step 0.5 (src): build the StarRailCopilot payload from scratch:
#   - clone the repo at its latest RELEASE tag        -> payload/app
#   - download python-build-standalone (cpython arm64) + pip install requirements
#                                                      -> payload/python
#   - download Android platform-tools (adb)           -> payload/platform-tools
# No conda: SRC's deps are plain pip wheels (onnxruntime, opencv-python, ...).
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

command -v gh >/dev/null || die "gh not found (needed to resolve the release tag)"

PAYLOAD="$BUILD_DIR/payload"
log "Building SRC payload -> $PAYLOAD"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"

# --- 1. app repo (latest RELEASE tag, not master HEAD) ----------------------
ref="$UPSTREAM_REF"
if [ -z "$ref" ]; then
  log "Resolving latest release tag of $UPSTREAM"
  ref="$(gh release view --repo "$UPSTREAM" --json tagName -q .tagName)"
  [ -n "$ref" ] || die "could not resolve latest release tag (is gh authenticated?)"
fi
log "Cloning $UPSTREAM_URL at release ref: $ref"
git clone --depth 1 --branch "$ref" "$UPSTREAM_URL" "$PAYLOAD/app"
[ -d "$PAYLOAD/app/.git" ] || die "cloned repo has no .git"
log "Packaged commit: $(git -C "$PAYLOAD/app" rev-parse --short HEAD) (release $ref)"

# Pull the Electron shell + icon art out of the clone before trimming.
if [ -d "$PAYLOAD/app/webapp" ]; then
  rm -rf "$BUILD_DIR/webapp-upstream"
  cp -R "$PAYLOAD/app/webapp" "$BUILD_DIR/webapp-upstream"
  rm -rf "$BUILD_DIR/webapp-upstream/node_modules" "$BUILD_DIR/webapp-upstream/dist"
  log "Extracted Electron shell source -> $BUILD_DIR/webapp-upstream"
else
  die "upstream webapp/ not found in the clone"
fi
[ -f "$PAYLOAD/app/webapp/buildResources/icon.png" ] \
  && cp "$PAYLOAD/app/webapp/buildResources/icon.png" "$BUILD_DIR/icon-source.png" \
  && log "Extracted icon source -> $BUILD_DIR/icon-source.png"
rm -rf "$PAYLOAD/app/.github" "$PAYLOAD/app/webapp" "$PAYLOAD/app/log"

# --- 2. python-build-standalone + pip deps ----------------------------------
log "Resolving python-build-standalone (cpython-$PBS_PY_VERSION arm64, install_only)"
# Note: browser_download_url URL-encodes the '+' before the build date as %2B,
# so match with .* between the version and the arch triple.
asset_url="$(gh api repos/astral-sh/python-build-standalone/releases/latest \
  --jq '.assets[].browser_download_url' 2>/dev/null \
  | grep -E "cpython-${PBS_PY_VERSION//./\\.}\.[0-9]+.*-aarch64-apple-darwin-install_only\.tar\.gz$" \
  | sort -V | tail -1 || true)"
[ -n "$asset_url" ] || die "no python-build-standalone $PBS_PY_VERSION arm64 install_only asset found"
log "Downloading $asset_url"
curl -fsSL "$asset_url" -o "$BUILD_DIR/python.tar.gz"
( cd "$BUILD_DIR" && rm -rf python && tar -xzf python.tar.gz )   # extracts to ./python
mv "$BUILD_DIR/python" "$PAYLOAD/python"
rm -f "$BUILD_DIR/python.tar.gz"
PY="$PAYLOAD/python/bin/python3"
test -x "$PY" || die "bundled python missing after extract: $PY"
log "Bundled python: $("$PY" --version 2>&1)"

log "Installing SRC requirements with pip (this pulls wheels)"
"$PY" -m pip install --upgrade pip >/dev/null
"$PY" -m pip install --no-input --disable-pip-version-check -r "$PAYLOAD/app/requirements.txt"

# --- 3. platform-tools (adb) ------------------------------------------------
log "Downloading platform-tools (adb)"
curl -fsSL "$PLATFORM_TOOLS_URL" -o "$BUILD_DIR/platform-tools.zip"
( cd "$BUILD_DIR" && rm -rf platform-tools && unzip -q platform-tools.zip )
mv "$BUILD_DIR/platform-tools" "$PAYLOAD/platform-tools"
rm -f "$BUILD_DIR/platform-tools.zip"
test -x "$PAYLOAD/platform-tools/adb" || die "adb not found after extract"

# --- 4. slim + verify -------------------------------------------------------
log "Slimming the python env"
find "$PAYLOAD/python" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
rm -rf "$PAYLOAD/python/lib/python${PBS_PY_VERSION}"*/test \
       "$PAYLOAD/python/lib/python${PBS_PY_VERSION}"*/site-packages/pip/_vendor/*/tests 2>/dev/null || true

log "Verifying imports (numpy / cv2 / onnxruntime / av)"
"$PY" - <<'PYEOF'
import numpy, cv2, onnxruntime, av
from PIL import Image
print(f"  numpy {numpy.__version__}, cv2 {cv2.__version__}, onnxruntime {onnxruntime.__version__} — OK")
PYEOF

log "SRC payload built:"
du -sh "$PAYLOAD"/* 2>/dev/null || true
