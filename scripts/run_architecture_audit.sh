#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
APP_BINARY="$ARTIFACT_DIR/自在启动台.app/Contents/MacOS/ZizaiLaunchpad"

[[ -x "$APP_BINARY" ]] || {
  echo "架构验收失败：缺少已构建的应用二进制文件" >&2
  exit 1
}

ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_BINARY")"
[[ "$ARCHITECTURES" == *"arm64"* && "$ARCHITECTURES" == *"x86_64"* ]] || {
  echo "架构验收失败：产物不是 Universal 2：$ARCHITECTURES" >&2
  exit 1
}

BUILD_INFO="$(/usr/bin/xcrun vtool -show-build "$APP_BINARY")"
[[ "$BUILD_INFO" == *"minos 13.0"* ]] || {
  echo "架构验收失败：二进制文件没有保持 macOS 13.0 部署目标" >&2
  exit 1
}

ZIZAI_AUDIT_ARCH=x86_64 ZIZAI_AUDIT_SCOPE=launch \
  /bin/zsh "$PROJECT_DIR/scripts/run_login_item_audit.sh" >/dev/null

/usr/bin/python3 "$PROJECT_DIR/scripts/verify_architecture_boundaries.py"

echo "架构验收通过：Universal 2（arm64 + x86_64）、macOS 13.0 部署目标，x86_64 核心设置与启动测试已在 Rosetta 下执行。"
