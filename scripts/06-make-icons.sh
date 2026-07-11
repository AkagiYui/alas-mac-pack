#!/bin/bash
# Step 0.6: generate the macOS app icon (dock) and the menu-bar (tray) icon from
# the upstream character art, and drop them where the Electron build expects:
#   - build/webapp/buildResources/icon.icns   (dock / .app icon, used by electron-builder)
#   - build/webapp/packages/main/public/tray.png + tray@2x.png  (menu-bar icon)
#
# Design (see app-store-preflight/icon-generator.md for the styling reference):
#   app icon = white squircle tile (80px margin, 230px radius on 1024) + top-left
#              lighting (gloss / inner shadow / edge highlight) + the portrait as
#              an inset card with a soft drop shadow; corners transparent.
#   tray icon = circular crop of the portrait, sized for the menu bar (@1x + @2x).
#
# Source art is extracted from the upstream repo by 05-build-payload.sh
# (build/icon-source.png). Requires: rsvg-convert (brew install librsvg), sips,
# iconutil (system).
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

SRC="${1:-$BUILD_DIR/icon-source.png}"
if [ ! -f "$SRC" ]; then
  warn "icon source not found ($SRC); keeping the existing buildResources/icon.icns"
  warn "run 05-build-payload.sh first (it extracts the icon from upstream), or pass a source path"
  exit 0
fi
command -v rsvg-convert >/dev/null || die "rsvg-convert missing (brew install librsvg)"
[ -d "$WEBAPP_BUILD" ] || die "run 00-prepare-webapp.sh first (missing $WEBAPP_BUILD)"

WORK="$BUILD_DIR/icons"
rm -rf "$WORK"; mkdir -p "$WORK"
log "Generating icons from $SRC"

# Upscale the 256px source a bit so the embedded raster is less soft.
sips -z 512 512 "$SRC" --out "$WORK/src.png" >/dev/null 2>&1 || cp "$SRC" "$WORK/src.png"
base64 -i "$WORK/src.png" | tr -d '\n' > "$WORK/src.b64"

# Emit the two SVGs (app icon + tray) with the source embedded as a data URI.
python3 - "$WORK" <<'PYEOF'
import os, sys
work = sys.argv[1]
b64 = open(os.path.join(work, "src.b64")).read().strip()
uri = f"data:image/png;base64,{b64}"

app_svg = f'''<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <defs>
    <linearGradient id="tile" x1="0.15" y1="0" x2="0.72" y2="1">
      <stop offset="0" stop-color="#ffffff"/><stop offset="0.55" stop-color="#f3f4f7"/><stop offset="1" stop-color="#e4e6ec"/>
    </linearGradient>
    <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.45"/><stop offset="0.42" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="shade" x1="0" y1="1" x2="0" y2="0">
      <stop offset="0" stop-color="#000000" stop-opacity="0.09"/><stop offset="0.34" stop-color="#000000" stop-opacity="0"/>
    </linearGradient>
    <clipPath id="tileClip"><rect x="80" y="80" width="864" height="864" rx="230" ry="230"/></clipPath>
    <clipPath id="portClip"><rect x="132" y="132" width="760" height="760" rx="172" ry="172"/></clipPath>
    <filter id="portShadow" x="-25%" y="-25%" width="150%" height="150%">
      <feDropShadow dx="0" dy="16" stdDeviation="22" flood-color="#1a1a2a" flood-opacity="0.30"/>
    </filter>
  </defs>
  <g clip-path="url(#tileClip)">
    <rect x="80" y="80" width="864" height="864" fill="url(#tile)"/>
    <g filter="url(#portShadow)"><rect x="132" y="132" width="760" height="760" rx="172" ry="172" fill="#ffffff"/></g>
    <g clip-path="url(#portClip)"><image x="132" y="132" width="760" height="760" preserveAspectRatio="xMidYMid slice" xlink:href="{uri}"/></g>
    <rect x="132" y="132" width="760" height="760" rx="172" ry="172" fill="none" stroke="#000000" stroke-opacity="0.10" stroke-width="2.5"/>
    <rect x="80" y="80" width="864" height="864" fill="url(#gloss)"/>
    <rect x="80" y="80" width="864" height="864" fill="url(#shade)"/>
  </g>
  <rect x="81.5" y="81.5" width="861" height="861" rx="228.5" ry="228.5" fill="none" stroke="#ffffff" stroke-opacity="0.65" stroke-width="3"/>
  <rect x="80" y="80" width="864" height="864" rx="230" ry="230" fill="none" stroke="#000000" stroke-opacity="0.10" stroke-width="2"/>
</svg>'''

tray_svg = f'''<svg width="44" height="44" viewBox="0 0 44 44" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <defs><clipPath id="c"><circle cx="22" cy="22" r="21.5"/></clipPath></defs>
  <g clip-path="url(#c)"><image x="0" y="0" width="44" height="44" preserveAspectRatio="xMidYMid slice" xlink:href="{uri}"/></g>
  <circle cx="22" cy="22" r="21" fill="none" stroke="#000000" stroke-opacity="0.12" stroke-width="1"/>
</svg>'''

open(os.path.join(work, "app-icon.svg"), "w").write(app_svg)
open(os.path.join(work, "tray.svg"), "w").write(tray_svg)
print("  wrote app-icon.svg + tray.svg")
PYEOF

# --- app icon -> iconset -> icns --------------------------------------------
log "Rendering app icon -> icon.icns"
rsvg-convert -w 1024 -h 1024 "$WORK/app-icon.svg" -o "$WORK/icon_1024.png"
ICONSET="$WORK/AppIcon.iconset"; mkdir -p "$ICONSET"
gen() { sips -z "$1" "$1" "$WORK/icon_1024.png" --out "$ICONSET/$2" >/dev/null; }
gen 16   icon_16x16.png;      gen 32  icon_16x16@2x.png
gen 32   icon_32x32.png;      gen 64  icon_32x32@2x.png
gen 128  icon_128x128.png;    gen 256 icon_128x128@2x.png
gen 256  icon_256x256.png;    gen 512 icon_256x256@2x.png
gen 512  icon_512x512.png;    cp "$WORK/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$WORK/icon.icns" || die "iconutil failed"

# --- tray icon (menu bar) ---------------------------------------------------
log "Rendering tray icon -> tray.png (@1x) + tray@2x.png"
rsvg-convert -w 44 -h 44 "$WORK/tray.svg" -o "$WORK/tray@2x.png"
rsvg-convert -w 22 -h 22 "$WORK/tray.svg" -o "$WORK/tray.png"

# --- dmg background (with the xattr un-quarantine instruction) ---------------
log "Rendering dmg background for $APP_NAME"
APP_NAME="$APP_NAME" python3 - "$WORK" <<'PYEOF'
import os, sys
work = sys.argv[1]
app = os.environ["APP_NAME"]
svg = f'''<svg width="800" height="400" viewBox="0 0 800 400" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6f7fb"/><stop offset="1" stop-color="#e9ebf2"/></linearGradient>
    <linearGradient id="cmd" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2b2d38"/><stop offset="1" stop-color="#1e2029"/></linearGradient>
  </defs>
  <rect width="800" height="400" fill="url(#bg)"/>
  <text x="400" y="56" text-anchor="middle" font-family="PingFang SC, Helvetica, sans-serif" font-size="26" font-weight="600" fill="#3a3d49">安装 {app}</text>
  <text x="400" y="84" text-anchor="middle" font-family="PingFang SC, Helvetica, sans-serif" font-size="14" fill="#8a8f9c">① 将左侧图标拖到右侧 Applications 文件夹</text>
  <g stroke="#b7bccb" stroke-width="7" fill="none" stroke-linecap="round" stroke-linejoin="round">
    <line x1="315" y1="190" x2="475" y2="190"/><polyline points="452,170 485,190 452,210"/>
  </g>
  <rect x="120" y="292" width="560" height="76" rx="16" fill="url(#cmd)"/>
  <circle cx="142" cy="312" r="5" fill="#ff5f57"/><circle cx="160" cy="312" r="5" fill="#febc2e"/><circle cx="178" cy="312" r="5" fill="#28c840"/>
  <text x="400" y="316" text-anchor="middle" font-family="PingFang SC, Helvetica, sans-serif" font-size="12" fill="#c9ccd6">② 首次打开前，在「终端」执行以下命令解除限制</text>
  <text x="400" y="350" text-anchor="middle" font-family="Menlo, monospace" font-size="16" fill="#5be07a">xattr -c /Applications/{app}.app</text>
</svg>'''
open(os.path.join(work, "dmg-bg.svg"), "w").write(svg)
PYEOF
rsvg-convert -w 1600 -h 800 "$WORK/dmg-bg.svg" -o "$WORK/dmg-background.png"   # 2x for Retina

# --- install into the build tree --------------------------------------------
cp "$WORK/dmg-background.png" "$BUILD_DIR/dmg-background.png"
cp "$WORK/icon.icns" "$WEBAPP_BUILD/buildResources/icon.icns"
mkdir -p "$WEBAPP_BUILD/packages/main/public"
cp "$WORK/tray.png"    "$WEBAPP_BUILD/packages/main/public/tray.png"
cp "$WORK/tray@2x.png" "$WEBAPP_BUILD/packages/main/public/tray@2x.png"

# also refresh the repo-tracked preview copy of the app icon (not committed here)
cp "$WORK/icon_1024.png" "$WORK/preview_1024.png"
log "Icons generated:"
log "  app  -> $WEBAPP_BUILD/buildResources/icon.icns"
log "  tray -> $WEBAPP_BUILD/packages/main/public/tray.png (+ @2x)"
