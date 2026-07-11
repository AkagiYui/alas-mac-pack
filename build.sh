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
# Select the app with PROFILE=alas (default) or PROFILE=src, e.g.:
#   PROFILE=src ./build.sh payload
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/scripts"
# Resolve the profile's payload builder (05-build-payload.sh | 05-src-build-payload.sh)
PAYLOAD_BUILDER="$(cd "$S" && source ./env.sh >/dev/null 2>&1; echo "$PAYLOAD_BUILDER")"

case "${1:-all}" in
  all)      bash "$S/00-prepare-webapp.sh"; bash "$S/06-make-icons.sh"; bash "$S/10-build-shell.sh"; bash "$S/20-assemble.sh"; bash "$S/30-package.sh" ;;
  payload)  bash "$S/$PAYLOAD_BUILDER" ;;
  icons)    bash "$S/06-make-icons.sh" ;;
  shell)    bash "$S/00-prepare-webapp.sh"; bash "$S/06-make-icons.sh"; bash "$S/10-build-shell.sh" ;;
  assemble) bash "$S/20-assemble.sh" ;;
  package)  bash "$S/30-package.sh" ;;
  smoke)    bash "$S/40-smoke-test.sh" ;;
  *) echo "unknown target: $1"; exit 1 ;;
esac
