#!/bin/bash
# 构建 SSH Manager.app：swift build release + 手工组装 bundle + ad-hoc 签名
#
# 环境说明：仅有 Command Line Tools（无完整 Xcode）时，macOS 27 SDK 中 SwiftUI
# 的 @State 等属性包装器已改为宏实现，而 CLT 不随附 SwiftUIMacros 插件，直接构建
# 会报 "plugin for module 'SwiftUIMacros' not found"。因此这里显式改用
# macOS 26.x SDK（@State 仍是普通属性包装器）+ native 构建系统。
# 安装了完整 Xcode 后本脚本会自动走默认构建，无需改动。
set -euo pipefail
cd "$(dirname "$0")"

SWIFT_ARGS=()
if [ ! -d "/Applications/Xcode.app" ]; then
  SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1 || true)
  if [ -z "${SDK:-}" ]; then
    echo "错误：未安装完整 Xcode，也未找到 MacOSX26*.sdk，无法规避 SwiftUIMacros 插件缺失问题。" >&2
    echo "请安装 Xcode，或安装 macOS 26.x Command Line Tools。" >&2
    exit 1
  fi
  echo "CLT 环境，使用 SDK: $SDK"
  SWIFT_ARGS=(--build-system native -Xswiftc -sdk -Xswiftc "$SDK")
fi

swift build -c release "${SWIFT_ARGS[@]}"

APP="dist/SSHManager.app"
BIN=".build/release/SSHManager"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SSHManager"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SSH Manager</string>
    <key>CFBundleDisplayName</key><string>SSH Manager</string>
    <key>CFBundleExecutable</key><string>SSHManager</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.sshmanager.app</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

echo "构建完成: $PWD/$APP"
echo "运行: open '$PWD/$APP'"
