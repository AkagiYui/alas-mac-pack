#!/bin/bash
# alas-mac-pack — build a macOS (Apple Silicon) package of AzurLaneAutoScript
# as a normal Electron app.
#
# Usage:
#   ./build.sh              # full pipeline
#   ./build.sh shell        # only rebuild the Electron shell (steps 0+1)
#   ./build.sh assemble     # only re-copy payload + deploy.yaml (step 2)
#   ./build.sh package      # only sign + dmg (step 3)
#
# Override inputs via env, e.g.:
#   PAYLOAD_SRC=/path/to/Resources WEBAPP_SRC=/path/to/webapp ./build.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/scripts"

case "${1:-all}" in
  all)      bash "$S/00-prepare-webapp.sh"; bash "$S/10-build-shell.sh"; bash "$S/20-assemble.sh"; bash "$S/30-package.sh" ;;
  shell)    bash "$S/00-prepare-webapp.sh"; bash "$S/10-build-shell.sh" ;;
  assemble) bash "$S/20-assemble.sh" ;;
  package)  bash "$S/30-package.sh" ;;
  *) echo "unknown target: $1"; exit 1 ;;
esac
