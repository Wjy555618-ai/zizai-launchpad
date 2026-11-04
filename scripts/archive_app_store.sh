#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
ARCHIVE_PATH="$ARTIFACT_DIR/自在启动台-AppStore.xcarchive"
EXPORT_PATH="$ARTIFACT_DIR/AppStoreExport"
EXPORT_OPTIONS="$PROJECT_DIR/AppStore/ExportOptions.plist"
source "$PROJECT_DIR/scripts/release_config.sh"

TEAM_ID="$(zizai_require_release_setting "$PROJECT_DIR" DEVELOPMENT_TEAM)"
BUNDLE_ID="$(zizai_require_release_setting "$PROJECT_DIR" PRODUCT_BUNDLE_IDENTIFIER)"

[[ -n "$BUNDLE_ID" && "$BUNDLE_ID" != local.* ]] || {
  echo "Release Bundle ID 仍是本地占位符：$BUNDLE_ID" >&2
  exit 1
}
[[ -f "$EXPORT_OPTIONS" ]] || {
  echo "缺少 App Store 导出配置：$EXPORT_OPTIONS" >&2
  exit 1
}

/bin/mkdir -p "$ARTIFACT_DIR"
[[ ! -d "$ARCHIVE_PATH" ]] || /bin/rm -rf "$ARCHIVE_PATH"
[[ ! -d "$EXPORT_PATH" ]] || /bin/rm -rf "$EXPORT_PATH"

/usr/bin/xcodebuild archive \
  -project "$PROJECT_DIR/自在启动台.xcodeproj" \
  -scheme "自在启动台" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO

APP_PATH="$ARCHIVE_PATH/Products/Applications/自在启动台.app"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"

/usr/bin/xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

PACKAGE_PATH="$EXPORT_PATH/自在启动台.pkg"
SUMMARY_PATH="$EXPORT_PATH/DistributionSummary.plist"
[[ -f "$PACKAGE_PATH" && -f "$SUMMARY_PATH" ]]

SUMMARY_TEAM="$(/usr/libexec/PlistBuddy -c 'Print :自在启动台.pkg:0:team:id' "$SUMMARY_PATH")"
SUMMARY_APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :自在启动台.pkg:0:entitlements:com.apple.application-identifier' "$SUMMARY_PATH")"
SUMMARY_CERTIFICATE="$(/usr/libexec/PlistBuddy -c 'Print :自在启动台.pkg:0:certificate:type' "$SUMMARY_PATH")"
[[ "$SUMMARY_TEAM" == "$TEAM_ID" ]]
[[ "$SUMMARY_APP_ID" == "$TEAM_ID.$BUNDLE_ID" ]]
[[ "$SUMMARY_CERTIFICATE" == *"Apple Distribution"* ]]
/usr/sbin/pkgutil --check-signature "$PACKAGE_PATH" >/dev/null

echo "正式 App Store Archive 已生成：$ARCHIVE_PATH"
echo "正式 App Store 安装包已导出：$PACKAGE_PATH"
