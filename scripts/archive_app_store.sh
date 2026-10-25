#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
ARCHIVE_PATH="${ZIZAI_ARCHIVE_PATH:-$ARTIFACT_DIR/自在启动台-AppStore.xcarchive}"
TEAM_ID="${ZIZAI_DEVELOPMENT_TEAM:-}"
BUNDLE_ID="${ZIZAI_BUNDLE_IDENTIFIER:-}"

[[ -n "$TEAM_ID" ]] || {
  echo "缺少 ZIZAI_DEVELOPMENT_TEAM；不得伪造 Apple Developer Team。" >&2
  exit 1
}
[[ -n "$BUNDLE_ID" && "$BUNDLE_ID" != local.* ]] || {
  echo "缺少最终 ZIZAI_BUNDLE_IDENTIFIER，且不能使用 local.* 占位符。" >&2
  exit 1
}

if [[ -d "$ARCHIVE_PATH" ]]; then
  /bin/rm -rf "$ARCHIVE_PATH"
fi

/usr/bin/xcodebuild archive \
  -project "$PROJECT_DIR/自在启动台.xcodeproj" \
  -scheme "自在启动台" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Distribution"

/usr/bin/codesign --verify --deep --strict "$ARCHIVE_PATH/Products/Applications/自在启动台.app"
echo "正式 App Store Archive 已生成：$ARCHIVE_PATH"
