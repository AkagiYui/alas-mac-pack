#!/bin/bash
# Shared configuration for the alas-mac-pack build pipeline.
# Override any of these by exporting them before running build.sh.
#
# Two build profiles, selected with PROFILE=alas (default) or PROFILE=src:
#   alas -> AzurLaneAutoScript, conda env (config/environment.yml)
#   src  -> StarRailCopilot,    python-build-standalone + pip (requirements.txt)

set -euo pipefail

# Repo root (this file lives in <repo>/scripts/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
LME_ROOT="${LME_ROOT:-$(cd "$REPO_ROOT/.." && pwd)}"

PROFILE="${PROFILE:-alas}"
ARCH="arm64"

# --- Per-profile settings ---------------------------------------------------
case "$PROFILE" in
  alas)
    APP_NAME_DEFAULT="AzurLaneAutoScript"
    UPSTREAM_DEFAULT="LmeSzinc/AzurLaneAutoScript"
    OVERLAY_DIR="$REPO_ROOT/overlay"
    DEPLOY_TEMPLATE="$REPO_ROOT/config/deploy.mac.yaml"
    BUILDER_CONFIG="electron-builder.config.js"
    WEBUI_PORT_DEFAULT=22267
    PY_REL="miniforge3/envs/alas/bin/python"          # python inside the payload
    SMOKE_IMPORTS="numpy, cv2, mxnet"
    PAYLOAD_BUILDER="05-build-payload.sh"
    ;;
  src)
    APP_NAME_DEFAULT="StarRailCopilot"
    UPSTREAM_DEFAULT="LmeSzinc/StarRailCopilot"
    OVERLAY_DIR="$REPO_ROOT/overlay-src"
    DEPLOY_TEMPLATE="$REPO_ROOT/config/deploy-src.mac.yaml"
    BUILDER_CONFIG=".electron-builder.config.js"
    WEBUI_PORT_DEFAULT=22367
    PY_REL="python/bin/python3"
    SMOKE_IMPORTS="numpy, cv2, onnxruntime"
    PAYLOAD_BUILDER="05-src-build-payload.sh"
    ;;
  *) echo "unknown PROFILE: $PROFILE (use alas|src)" >&2; exit 1 ;;
esac

# --- Product ----------------------------------------------------------------
APP_NAME="${APP_NAME:-$APP_NAME_DEFAULT}"
APP_VERSION="${APP_VERSION:-}"      # empty -> electron-builder date-based version
WEBUI_PORT="${WEBUI_PORT:-$WEBUI_PORT_DEFAULT}"

# --- Work dirs (per-profile so alas/src don't clobber each other) -----------
BUILD_DIR="$REPO_ROOT/build/$PROFILE"
WEBAPP_BUILD="$BUILD_DIR/webapp"                       # patched copy we compile
SHELL_OUT="$WEBAPP_BUILD/dist/mac-$ARCH"               # electron-builder --dir output
APP_BUNDLE="$SHELL_OUT/$APP_NAME.app"
DIST_DIR="$REPO_ROOT/dist"                             # final .app + .dmg land here

# --- Inputs -----------------------------------------------------------------
# Nothing upstream is vendored: 05*-build-payload.sh extracts webapp/ from the
# cloned repo into build/<profile>/webapp-upstream and 00-prepare layers OVERLAY_DIR.
WEBAPP_SRC="${WEBAPP_SRC:-$BUILD_DIR/webapp-upstream}"
PAYLOAD_SRC="${PAYLOAD_SRC:-$BUILD_DIR/payload}"

# Upstream repo to package (owner/repo). Ref empty => latest RELEASE tag.
UPSTREAM="${UPSTREAM:-$UPSTREAM_DEFAULT}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/$UPSTREAM}"
UPSTREAM_REF="${UPSTREAM_REF:-}"
# Back-compat aliases used by the alas payload builder.
ALAS_UPSTREAM="$UPSTREAM"; ALAS_REPO="$UPSTREAM_URL"; ALAS_REF="$UPSTREAM_REF"

# alas (conda) settings
CONDA_ENV_NAME="${CONDA_ENV_NAME:-alas}"
CONDA_ENV_PREFIX="${CONDA_ENV_PREFIX:-}"

# src (python-build-standalone) settings — resolved by 05-src-build-payload.sh.
# SRC's requirements are pip-compiled for Python 3.10, and the pinned
# onnxruntime==1.14.1 only ships arm64 wheels up to cp310 — so bundle 3.10.
PBS_PY_VERSION="${PBS_PY_VERSION:-3.10}"     # cpython minor to bundle

PLATFORM_TOOLS_URL="${PLATFORM_TOOLS_URL:-https://dl.google.com/android/repository/platform-tools-latest-darwin.zip}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }
