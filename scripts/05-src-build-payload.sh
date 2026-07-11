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
# A --branch <tag> clone is detached with no origin/master ref, so the in-app
# git update (`git reset --hard origin/master`) would fail. Configure the remote
# fetch refspec and seed origin/master so on-demand updates work.
git -C "$PAYLOAD/app" config remote.origin.fetch "+refs/heads/master:refs/remotes/origin/master"
git -C "$PAYLOAD/app" fetch --depth 1 origin master 2>/dev/null || warn "could not seed origin/master"

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
# python-build-standalone (install_only) ships pip but not setuptools; adbutils
# imports pkg_resources (from setuptools). Pin <81 which still provides it.
"$PY" -m pip install "setuptools<81" wheel >/dev/null
# av==10.0.0 has no macOS wheel (would build from source and need ffmpeg). Bump
# to 12.3.0, which ships a prebuilt arm64 wheel with ffmpeg bundled. SRC only
# uses av's stable CodecContext / InvalidDataError (scrcpy method). Done on a
# temp copy so the bundled repo's requirements.txt is left untouched.
SRC_AV_VERSION="${SRC_AV_VERSION:-12.3.0}"
sed "s/^av==10\.0\.0/av==$SRC_AV_VERSION/" "$PAYLOAD/app/requirements.txt" > "$BUILD_DIR/requirements.txt"
"$PY" -m pip install --no-input --disable-pip-version-check -r "$BUILD_DIR/requirements.txt"

# --- 3. platform-tools (adb) ------------------------------------------------
log "Downloading platform-tools (adb)"
curl -fsSL "$PLATFORM_TOOLS_URL" -o "$BUILD_DIR/platform-tools.zip"
( cd "$BUILD_DIR" && rm -rf platform-tools && unzip -q platform-tools.zip )
mv "$BUILD_DIR/platform-tools" "$PAYLOAD/platform-tools"
rm -f "$BUILD_DIR/platform-tools.zip"
test -x "$PAYLOAD/platform-tools/adb" || die "adb not found after extract"

# --- 4. slim + verify -------------------------------------------------------
log "Slimming the python env"
STD="$PAYLOAD/python/lib/python${PBS_PY_VERSION}"
SP="$STD/site-packages"
before="$(du -sh "$PAYLOAD/python" 2>/dev/null | cut -f1)"

# pynput + pyobjc: pynput is imported only by dev_tools/screenshot.py (a dev
# tool, not the bot runtime) and drags in the whole pyobjc stack (~60MB).
"$PY" -m pip freeze 2>/dev/null | grep -iE "^(pynput|pyobjc)" | cut -d= -f1 \
  | xargs -r "$PY" -m pip uninstall -y >/dev/null 2>&1 || true

# __pycache__ + package test suites (numpy/scipy/sympy/... never import their tests)
find "$PAYLOAD/python" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$SP" -type d \( -name tests -o -name test \) -prune -exec rm -rf {} + 2>/dev/null || true

# stdlib we never use in a headless bot (no Tk/GUI, no dev tooling)
rm -rf "$STD"/test "$STD"/idlelib "$STD"/tkinter "$STD"/turtledemo "$STD"/lib2to3 \
       "$STD"/ensurepip "$STD"/lib-dynload/_tkinter*.so 2>/dev/null || true
rm -rf "$PAYLOAD/python/lib"/tcl8* "$PAYLOAD/python/lib"/tk8* "$PAYLOAD/python/lib"/Tk* \
       "$PAYLOAD/python/lib"/itcl* "$PAYLOAD/python/lib"/libtcl*.dylib "$PAYLOAD/python/lib"/libtk*.dylib 2>/dev/null || true

# platform-tools: keep only adb (+ its libs); drop fastboot & flashing tools
for f in fastboot sqlite3 mke2fs mke2fs.conf etc1tool make_f2fs make_f2fs_casefold \
         dmtracedump hprof-conv; do
  rm -rf "$PAYLOAD/platform-tools/$f" 2>/dev/null || true
done
log "Slimmed python: ${before:-?} -> $(du -sh "$PAYLOAD/python" 2>/dev/null | cut -f1)"

log "Verifying imports (numpy / cv2 / onnxruntime / av / scipy / adbutils)"
"$PY" - <<'PYEOF'
import numpy, cv2, onnxruntime, av, scipy, adbutils
from PIL import Image
print(f"  numpy {numpy.__version__}, cv2 {cv2.__version__}, "
      f"onnxruntime {onnxruntime.__version__}, scipy {scipy.__version__} — OK")
PYEOF

log "SRC payload built:"
du -sh "$PAYLOAD"/* 2>/dev/null || true
