#!/bin/bash
# Step 0.5 (alas-pixi): SPIKE — build the alas payload with pixi instead of the
# conda/miniforge path (05-alas-build-payload.sh). Everything else in the
# pipeline is shared: this emits the python env at the SAME relative path
# (miniforge3/envs/alas) the conda builder uses, so 20-assemble / 30-package /
# 40-smoke-test and config/deploy-alas.mac.yaml all work unchanged (PY_REL is
# identical).
#
# Only the env-creation step differs:
#   conda:  setup-miniconda + `conda env create -f environment-alas.yml`
#   pixi :  `pixi init --import environment-alas.yml` + `pixi install`, then copy
#           the resolved prefix (.pixi/envs/default) into the payload.
#
# The point of this profile is to test — on GitHub Actions, on macos-15 — whether
# pixi (rattler resolver) can reproduce the same fully-pinned env (py38 + mxnet
# from the anaconda/defaults channel + Qt-linked opencv) and still pass the same
# native-import smoke test. A green run == the migration is viable.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

command -v pixi >/dev/null 2>&1 || die "pixi not found on PATH (install it before running this)"
command -v gh   >/dev/null 2>&1 || die "gh not found (needed to resolve the release tag)"

PAYLOAD="$BUILD_DIR/payload"
log "Building alas-pixi payload -> $PAYLOAD"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"

# --- 1. app repo (packaged from the latest RELEASE commit, not master HEAD) --
# Identical to the conda builder: clone at the release tag and seed origin/master
# so the in-app `git reset --hard origin/master` auto-update works.
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
git -C "$PAYLOAD/app" config remote.origin.fetch "+refs/heads/master:refs/remotes/origin/master"
git -C "$PAYLOAD/app" fetch --depth 1 origin master 2>/dev/null || warn "could not seed origin/master"
if [ -d "$PAYLOAD/app/webapp" ]; then
  rm -rf "$BUILD_DIR/webapp-upstream"
  cp -R "$PAYLOAD/app/webapp" "$BUILD_DIR/webapp-upstream"
  rm -rf "$BUILD_DIR/webapp-upstream/node_modules" "$BUILD_DIR/webapp-upstream/dist"
  log "Extracted Electron shell source -> $BUILD_DIR/webapp-upstream"
else
  die "upstream webapp/ not found in the clone — cannot build the Electron shell"
fi
if [ -f "$PAYLOAD/app/webapp/buildResources/icon.png" ]; then
  cp "$PAYLOAD/app/webapp/buildResources/icon.png" "$BUILD_DIR/icon-source.png"
  log "Extracted icon source -> $BUILD_DIR/icon-source.png"
else
  warn "upstream icon.png not found; icon generation will fall back to repo assets"
fi
rm -rf "$PAYLOAD/app/.github" "$PAYLOAD/app/webapp" "$PAYLOAD/app/log"

# --- 2. python env via pixi -------------------------------------------------
# Bootstrap a pixi workspace from the existing conda environment.yml. `--import`
# converts the conda deps + the pip: block into a pixi.toml; `pixi install`
# resolves them (writing a real pixi.lock) into .pixi/envs/default.
WS="$BUILD_DIR/pixi-ws"
rm -rf "$WS"
mkdir -p "$WS"
log "pixi init --import $REPO_ROOT/config/environment-alas.yml (platform osx-arm64)"
pixi init "$WS" --import "$REPO_ROOT/config/environment-alas.yml" --platform osx-arm64

# The env mixes the `anaconda` (main) and `conda-forge` channels and relied on
# conda's flexible resolution (e.g. ffmpeg from anaconda pulling aom from
# conda-forge). pixi defaults to STRICT channel priority, which excludes the
# lower-priority channel's package and makes the solve unsatisfiable. Disable
# strict priority to reproduce conda's mixing behaviour.
awk 'BEGIN{done=0}
     /^\[(workspace|project)\]/ && !done {print; print "channel-priority = \"disabled\""; done=1; next}
     {print}' "$WS/pixi.toml" > "$WS/pixi.toml.new" && mv "$WS/pixi.toml.new" "$WS/pixi.toml"
grep -q 'channel-priority' "$WS/pixi.toml" || warn "channel-priority not injected (manifest table header unexpected)"

log "Generated pixi.toml:"
sed 's/^/    /' "$WS/pixi.toml" 2>/dev/null || true

log "pixi install (resolve + link the env)"
pixi install --manifest-path "$WS/pixi.toml"

# Publish the generated manifest + lock as build artifacts so a green run can be
# promoted to committed files (config/pixi.toml + pixi.lock) without re-solving.
cp "$WS/pixi.toml" "$BUILD_DIR/pixi.toml.generated" 2>/dev/null || true
cp "$WS/pixi.lock" "$BUILD_DIR/pixi.lock.generated" 2>/dev/null || true

PIXI_ENV="$WS/.pixi/envs/default"
[ -x "$PIXI_ENV/bin/python" ] || die "pixi env python missing (prefix='$PIXI_ENV')"
log "pixi env: $("$PIXI_ENV/bin/python" -V 2>&1) at $PIXI_ENV"

# Copy into the SAME payload path the conda builder uses so all downstream steps
# (assemble/package/smoke + deploy.yaml PythonExecutable) are unchanged.
log "Copying pixi env -> $PAYLOAD/miniforge3/envs/$CONDA_ENV_NAME"
mkdir -p "$PAYLOAD/miniforge3/envs"
cp -RL "$PIXI_ENV" "$PAYLOAD/miniforge3/envs/$CONDA_ENV_NAME"
find "$PAYLOAD/miniforge3" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
rm -rf "$PAYLOAD/miniforge3/envs/$CONDA_ENV_NAME/pkgs" 2>/dev/null || true

# --- Slim + relocate the env (shared with the conda builder verbatim) --------
# See 05-alas-build-payload.sh for the rationale behind each cut. Keep CORE Qt
# (opencv here is the GUI build linking Qt5Widgets); drop only the big top-level
# Qt modules nothing links, LLVM/clang, and build-only dev files.
ENVDIR="$PAYLOAD/miniforge3/envs/$CONDA_ENV_NAME"
before="$(du -sh "$ENVDIR" 2>/dev/null | cut -f1)"
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
rm -f "$ENVDIR"/lib/libLLVM*.dylib "$ENVDIR"/lib/libclang*.dylib 2>/dev/null || true
rm -rf "$ENVDIR"/include "$ENVDIR"/lib/cmake "$ENVDIR"/lib/pkgconfig \
       "$ENVDIR"/share/man "$ENVDIR"/share/doc "$ENVDIR"/share/gtk-doc "$ENVDIR"/man 2>/dev/null || true
find "$ENVDIR" \( -name '*.a' -o -name '*.prl' -o -name '*.la' \) -delete 2>/dev/null || true
log "Slimmed env: ${before:-?} -> $(du -sh "$ENVDIR" 2>/dev/null | cut -f1)"

# macOS 15 dyld rejects duplicate LC_RPATH; de-duplicate + re-sign so the env
# loads on Sequoia (same fix the conda builder applies).
log "De-duplicating LC_RPATH in the env (macOS 15 compatibility)"
python3 "$REPO_ROOT/scripts/fix-env-rpaths.py" "$ENVDIR"

log "Verifying the env imports its native extensions (after slimming)"
"$ENVDIR/bin/python" - <<'PYEOF'
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

# --- 4. git (self-contained, relocatable) -----------------------------------
bash "$REPO_ROOT/scripts/bundle-git.sh" "$PAYLOAD"

log "Payload built:"
du -sh "$PAYLOAD"/* 2>/dev/null || true
log "python: $("$ENVDIR/bin/python" -V 2>&1)"
