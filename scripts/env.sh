#!/bin/bash
# Shared configuration for the alas-mac-pack build pipeline.
# Override any of these by exporting them before running build.sh.

set -euo pipefail

# Repo root (this file lives in <repo>/scripts/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Where the big source assets live. Defaults to the parent `lme` working copy.
LME_ROOT="${LME_ROOT:-$(cd "$REPO_ROOT/.." && pwd)}"

# --- Inputs -----------------------------------------------------------------
# Upstream Electron shell source (the vite-electron-builder `webapp/`).
WEBAPP_SRC="${WEBAPP_SRC:-$LME_ROOT/origin_not_modified/azurlaneautoscript/webapp}"

# Prebuilt payload: a directory that already contains a working
#   app/            (AzurLaneAutoScript git repo)
#   miniforge3/     (python env with all deps for env `alas`)
#   git/bin/git
#   platform-tools/adb
# The current Platypus .app's Contents/Resources is exactly this.
PAYLOAD_SRC="${PAYLOAD_SRC:-$LME_ROOT/alas/AzurLaneAutoScript.app/Contents/Resources}"

# --- Product ----------------------------------------------------------------
APP_NAME="${APP_NAME:-AzurLaneAutoScript}"
APP_VERSION="${APP_VERSION:-}"      # empty -> electron-builder date-based version
ARCH="arm64"

# --- Work dirs --------------------------------------------------------------
BUILD_DIR="$REPO_ROOT/build"
WEBAPP_BUILD="$BUILD_DIR/webapp"                       # patched copy we compile
SHELL_OUT="$WEBAPP_BUILD/dist/mac-$ARCH"               # electron-builder --dir output
APP_BUNDLE="$SHELL_OUT/$APP_NAME.app"
DIST_DIR="$REPO_ROOT/dist"                             # final .app + .dmg land here

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }
