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

# --- 1. app repo (packaged from the latest RELEASE commit, not master HEAD) --
ref="$ALAS_REF"
if [ -z "$ref" ]; then
  log "Resolving latest release tag of $ALAS_UPSTREAM"
  ref="$(gh release view --repo "$ALAS_UPSTREAM" --json tagName -q .tagName)"
  [ -n "$ref" ] || die "could not resolve latest release tag (is gh authenticated?)"
fi
log "Cloning $ALAS_REPO at release ref: $ref"
git clone --depth 1 --branch "$ref" "$ALAS_REPO" "$PAYLOAD/app"
[ -d "$PAYLOAD/app/.git" ] || die "cloned repo has no .git"
log "Packaged commit: $(git -C "$PAYLOAD/app" rev-parse --short HEAD) (release $ref)"
# Extract the app-icon source art from the upstream repo (used by 06-make-icons.sh),
# before trimming webapp/ away.
if [ -f "$PAYLOAD/app/webapp/buildResources/icon.png" ]; then
  cp "$PAYLOAD/app/webapp/buildResources/icon.png" "$BUILD_DIR/icon-source.png"
  log "Extracted icon source -> $BUILD_DIR/icon-source.png"
else
  warn "upstream icon.png not found; icon generation will fall back to repo assets"
fi
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

# Slim the env: remove what alas never loads at runtime.
# NOTE: opencv here is the GUI build (cv2 links libQt5Widgets), so keep CORE Qt
# (Core/Gui/Widgets/DBus/Svg/... + plugins). Only the big top-level Qt modules
# that nothing links (WebEngine/WebKit/3D/Quick/Qml/Multimedia — there are no
# PyQt/PySide bindings) and build-only dev files are removed. The verify below
# imports cv2/mxnet/... so a bad cut fails the build here, not on the user.
ENVDIR="$PAYLOAD/miniforge3/envs/$CONDA_ENV_NAME"
before="$(du -sh "$ENVDIR" 2>/dev/null | cut -f1)"
# unused heavy Qt modules (consumers, not deps of Qt5Widgets)
for mod in WebEngine WebEngineCore WebEngineWidgets WebView WebKit WebKitWidgets \
           3DCore 3DRender 3DInput 3DLogic 3DAnimation 3DExtras 3DQuick \
           Quick Quick3D QuickWidgets QuickControls2 QuickTemplates2 QuickTest QuickShapes \
           Qml QmlModels QmlWorkerScript Multimedia MultimediaWidgets MultimediaQuick \
           Designer DesignerComponents Help Location Purchasing Sensors \
           Charts DataVisualization RemoteObjects Scxml; do
  rm -f "$ENVDIR"/lib/libQt5${mod}.*dylib 2>/dev/null || true
done
rm -rf "$ENVDIR"/translations "$ENVDIR"/resources "$ENVDIR"/libexec/QtWebEngineProcess* \
       "$ENVDIR"/lib/qt5/libexec 2>/dev/null || true
# LLVM/clang: only libclang links libLLVM, and that's a dev/tooling lib nothing
# loads at runtime (cv2 links Qt5Widgets, not LLVM).
rm -f "$ENVDIR"/lib/libLLVM*.dylib "$ENVDIR"/lib/libclang*.dylib 2>/dev/null || true
# build-only dev files (safe)
rm -rf "$ENVDIR"/include "$ENVDIR"/lib/cmake "$ENVDIR"/lib/pkgconfig \
       "$ENVDIR"/share/man "$ENVDIR"/share/doc "$ENVDIR"/share/gtk-doc "$ENVDIR"/man 2>/dev/null || true
find "$ENVDIR" \( -name '*.a' -o -name '*.prl' -o -name '*.la' \) -delete 2>/dev/null || true
log "Slimmed env: ${before:-?} -> $(du -sh "$ENVDIR" 2>/dev/null | cut -f1)"

# macOS 15 (Sequoia) dyld rejects Mach-O with duplicate LC_RPATH entries, which
# several conda arm64 libs (libopenblas, libgfortran, numpy .so, ...) ship. This
# breaks `import numpy` at runtime (not caught on macos-14 CI). De-duplicate and
# re-sign so the env loads on Sequoia.
log "De-duplicating LC_RPATH in the env (macOS 15 compatibility)"
python3 "$REPO_ROOT/scripts/fix-env-rpaths.py" "$PAYLOAD/miniforge3/envs/$CONDA_ENV_NAME"

log "Verifying the env imports its native extensions (after slimming)"
"$PAYLOAD/miniforge3/envs/$CONDA_ENV_NAME/bin/python" - <<'PYEOF'
import numpy, cv2, mxnet, scipy, av, lxml
from PIL import Image
import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as _
print(f"  numpy {numpy.__version__}, cv2 {cv2.__version__}, mxnet {mxnet.__version__}, "
      f"scipy {scipy.__version__}, mpl {matplotlib.get_backend()} — OK")
PYEOF

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
