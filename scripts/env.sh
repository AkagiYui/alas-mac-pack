#!/bin/bash
# Shared configuration for the alas-mac-pack build pipeline.
# Override any of these by exporting them before running build.sh.

set -euo pipefail

# Repo root (this file lives in <repo>/scripts/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Where the big source assets live. Defaults to the parent `lme` working copy.
LME_ROOT="${LME_ROOT:-$(cd "$REPO_ROOT/.." && pwd)}"

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

# --- Inputs -----------------------------------------------------------------
# Upstream Electron shell source (the vite-electron-builder `webapp/`), vendored
# into this repo for reproducible/hermetic builds (CI has no other copy).
WEBAPP_SRC="${WEBAPP_SRC:-$REPO_ROOT/webapp-src}"

# Payload: a directory that contains a working
#   app/                       (AzurLaneAutoScript git repo)
#   miniforge3/envs/alas/      (conda env: python + git)
#   platform-tools/adb
# Build it fresh with scripts/05-build-payload.sh (clones the repo, creates the
# conda env from config/environment.yml, downloads platform-tools) — this is
# what CI does. Locally you can instead point PAYLOAD_SRC at an existing
# Contents/Resources to reuse a prebuilt env.
PAYLOAD_SRC="${PAYLOAD_SRC:-$BUILD_DIR/payload}"

# Sources used by 05-build-payload.sh
ALAS_REPO="${ALAS_REPO:-https://github.com/LmeSzinc/AzurLaneAutoScript}"
ALAS_BRANCH="${ALAS_BRANCH:-master}"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-alas}"
# Absolute path to the created conda env (contains bin/python). Auto-detected
# from `conda` if left empty.
CONDA_ENV_PREFIX="${CONDA_ENV_PREFIX:-}"
PLATFORM_TOOLS_URL="${PLATFORM_TOOLS_URL:-https://dl.google.com/android/repository/platform-tools-latest-darwin.zip}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }
