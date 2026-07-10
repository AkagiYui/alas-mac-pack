#!/bin/bash
# alas-mac-pack — build a macOS (Apple Silicon) package of AzurLaneAutoScript
# as a normal Electron app.
#
# Usage:
#   ./build.sh              # full pipeline (reuses an existing PAYLOAD_SRC)
#   ./build.sh payload      # build the payload from scratch (needs conda env `alas`)
#   ./build.sh shell        # only rebuild the Electron shell (steps 0+1)
#   ./build.sh assemble     # only re-copy payload + deploy.yaml (step 2)
#   ./build.sh package      # only sign + dmg (step 3)
#   ./build.sh smoke        # headless python + webui check (step 4)
#
# `all` reuses whatever PAYLOAD_SRC points at (default: build/payload). To build
# that payload first, run `./build.sh payload` (CI does this via conda) or point
# PAYLOAD_SRC at an existing Contents/Resources:
#   PAYLOAD_SRC=/path/to/Resources ./build.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/scripts"

case "${1:-all}" in
  all)      bash "$S/00-prepare-webapp.sh"; bash "$S/06-make-icons.sh"; bash "$S/10-build-shell.sh"; bash "$S/20-assemble.sh"; bash "$S/30-package.sh" ;;
  payload)  bash "$S/05-build-payload.sh" ;;
  icons)    bash "$S/06-make-icons.sh" ;;
  shell)    bash "$S/00-prepare-webapp.sh"; bash "$S/06-make-icons.sh"; bash "$S/10-build-shell.sh" ;;
  assemble) bash "$S/20-assemble.sh" ;;
  package)  bash "$S/30-package.sh" ;;
  smoke)    bash "$S/40-smoke-test.sh" ;;
  *) echo "unknown target: $1"; exit 1 ;;
esac
