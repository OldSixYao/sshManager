#!/bin/bash
# 从 1024 母版生成 Resources/AppIcon.icns
# 母版修改后运行: swift Scripts/make_icon.swift Resources/icon_1024.png && ./Scripts/make_icns.sh
set -euo pipefail
cd "$(dirname "$0")/.."

MASTER="Resources/icon_1024.png"
[ -f "$MASTER" ] || { echo "缺少 $MASTER，先运行 make_icon.swift 生成" >&2; exit 1; }

ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"

sips -z 16 16     "$MASTER" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32     "$MASTER" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$MASTER" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64     "$MASTER" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$MASTER" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256   "$MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$MASTER" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512   "$MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$MASTER" --out "$ICONSET/icon_512x512.png"    >/dev/null
sips -z 1024 1024 "$MASTER" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "已生成: Resources/AppIcon.icns"
