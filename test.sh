#!/bin/bash
# 运行 swift-testing 测试套件。
# 与 build.sh 相同的原因：CLT 环境需用 macOS 26.x SDK 规避 SwiftUIMacros 插件缺失；
# 另外 CLT 不带 XCTest，测试使用 swift-testing，需显式指定其框架搜索路径。
set -euo pipefail
cd "$(dirname "$0")"

TESTFW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1 || true)

if [ -z "${SDK:-}" ]; then
  echo "错误：未找到 MacOSX26*.sdk。" >&2
  exit 1
fi

swift test --build-system native \
  -Xswiftc -sdk -Xswiftc "$SDK" \
  -Xswiftc -F -Xswiftc "$TESTFW" \
  -Xlinker -F -Xlinker "$TESTFW"
