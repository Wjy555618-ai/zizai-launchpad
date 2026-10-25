#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
ARCHIVE_PATH="$ARTIFACT_DIR/自在启动台-unsigned.xcarchive"

if [[ -d "$ARCHIVE_PATH" ]]; then
  /bin/rm -rf "$ARCHIVE_PATH"
fi

/usr/bin/xcodebuild archive \
  -project "$PROJECT_DIR/自在启动台.xcodeproj" \
  -scheme "自在启动台" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO >/dev/null

APP_PATH="$ARCHIVE_PATH/Products/Applications/自在启动台.app"
[[ -x "$APP_PATH/Contents/MacOS/ZizaiLaunchpad" ]]
[[ -d "$ARCHIVE_PATH/dSYMs/自在启动台.app.dSYM" ]]
ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_PATH/Contents/MacOS/ZizaiLaunchpad")"
[[ "$ARCHITECTURES" == *"arm64"* && "$ARCHITECTURES" == *"x86_64"* ]]

echo "未签名 Archive 结构验证通过：$ARCHIVE_PATH"
echo "注意：该产物只证明代码侧 Archive 链路；上传仍需要发布者的正式 Bundle ID、Team、分发证书和描述文件。"
