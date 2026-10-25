#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
PROJECT_FILE="$PROJECT_DIR/自在启动台.xcodeproj"
BUILD_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
APP_DIR="$BUILD_DIR/自在启动台.app"
APP_BINARY="$APP_DIR/Contents/MacOS/ZizaiLaunchpad"
DSYM_DIR="$BUILD_DIR/自在启动台.app.dSYM"
ENTITLEMENTS="$PROJECT_DIR/Resources/ZizaiLaunchpad.entitlements"
ICON_PROJECT="$PROJECT_DIR/Resources/AppIcon.icon"
XCRUN_BIN="${ZIZAI_XCRUN_PATH:-/usr/bin/xcrun}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
TEMP_ROOT=""
SOURCE_APP=""
SOURCE_DSYM=""

fail() {
  echo "构建停止：$1" >&2
  exit 1
}

cleanup_build() {
  local exit_code=$?
  if [[ -n "$SOURCE_APP" && -d "$SOURCE_APP" && -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -u "$SOURCE_APP" >/dev/null 2>&1 || true
  fi
  if [[ -n "$TEMP_ROOT" && "$TEMP_ROOT" == *"/zizai-xcode-build."* && -d "$TEMP_ROOT" ]]; then
    /bin/rm -rf "$TEMP_ROOT"
  fi
  return $exit_code
}
trap cleanup_build EXIT

[[ -x "$XCRUN_BIN" ]] || fail "未找到 Apple 开发工具：$XCRUN_BIN"
XCODEBUILD="$($XCRUN_BIN --find xcodebuild 2>/dev/null || true)"
[[ -n "$XCODEBUILD" && -x "$XCODEBUILD" ]] || fail "需要安装完整 Xcode，才能生成原生 AppIcon.icon 图标。"
[[ -d "$PROJECT_FILE" ]] || fail "缺少 Xcode 工程：$PROJECT_FILE"
[[ -d "$ICON_PROJECT" ]] || fail "缺少唯一正式图标源：$ICON_PROJECT"

/bin/mkdir -p "$BUILD_DIR"
TEMP_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/zizai-xcode-build.XXXXXX")"
DERIVED_DATA="$TEMP_ROOT/DerivedData"
BUILD_LOG="$TEMP_ROOT/xcodebuild.log"

if ! "$XCODEBUILD" \
  -project "$PROJECT_FILE" \
  -scheme "自在启动台" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build >"$BUILD_LOG" 2>&1; then
  /usr/bin/tail -n 120 "$BUILD_LOG" >&2
  fail "Xcode Release 构建失败。"
fi

if /usr/bin/grep -E '(^|:[[:space:]])warning:' "$BUILD_LOG" >/dev/null; then
  /usr/bin/grep -E '(^|:[[:space:]])warning:' "$BUILD_LOG" >&2
  fail "Xcode Release 构建仍包含警告。"
fi

SOURCE_APP="$DERIVED_DATA/Build/Products/Release/自在启动台.app"
SOURCE_DSYM="$DERIVED_DATA/Build/Products/Release/自在启动台.app.dSYM"
[[ -x "$SOURCE_APP/Contents/MacOS/ZizaiLaunchpad" ]] || fail "Xcode 未产生可执行应用。"
[[ -d "$SOURCE_DSYM" ]] || fail "Release 构建未产生 dSYM。"

SOURCE_ARCHITECTURES="$(/usr/bin/lipo -archs "$SOURCE_APP/Contents/MacOS/ZizaiLaunchpad")"
[[ "$SOURCE_ARCHITECTURES" == *"arm64"* && "$SOURCE_ARCHITECTURES" == *"x86_64"* ]] \
  || fail "Xcode 产物不是 Universal 2：$SOURCE_ARCHITECTURES"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$SOURCE_APP/Contents/Info.plist")" == "AppIcon" ]] \
  || fail "Xcode 产物未使用唯一的 AppIcon.icon。"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$SOURCE_APP/Contents/Info.plist")" == "AppIcon" ]] \
  || fail "Xcode 产物缺少 AppIcon 资产名。"
[[ -f "$SOURCE_APP/Contents/Resources/AppIcon.icns" ]] || fail "未生成 AppIcon.icns。"
[[ -f "$SOURCE_APP/Contents/Resources/Assets.car" ]] || fail "未生成 Liquid Glass 图标资产。"
[[ -f "$SOURCE_APP/Contents/Resources/BrandMarkForeground.svg" ]] \
  || fail "未包含界面品牌标识的透明前景素材。"
[[ ! -f "$SOURCE_APP/Contents/Resources/AppIcon-1024.png" ]] \
  || fail "正式 App Icon 位图不应再作为界面品牌素材打包。"

BUILD_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_APP/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SOURCE_APP/Contents/Info.plist")"
[[ -n "$BUILD_BUNDLE_ID" && "$BUILD_BUNDLE_ID" != *'$('* ]] || fail "Bundle ID 未被 Xcode 正确解析。"
[[ "$BUILD_VERSION" == "1.0.0" ]] || fail "App Store 首发版本必须是 1.0.0，当前为 $BUILD_VERSION。"
[[ "$BUILD_NUMBER" == "1" ]] || fail "App Store 首发 Build 必须是 1，当前为 $BUILD_NUMBER。"

# Xcode 会临时向 LaunchServices 注册 DerivedData 中的产物。复制前先注销，
# 防止“构建版”被 macOS 当成第二个可启动版本。
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -u "$SOURCE_APP" >/dev/null 2>&1 || true
  "$LSREGISTER" -u "$APP_DIR" >/dev/null 2>&1 || true
fi

/bin/rm -rf "$APP_DIR" "$DSYM_DIR"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl "$SOURCE_APP" "$APP_DIR"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl "$SOURCE_DSYM" "$DSYM_DIR"

/usr/bin/codesign \
  --force \
  --deep \
  --sign - \
  --entitlements "$ENTITLEMENTS" \
  "$APP_DIR" >/dev/null
/usr/bin/codesign --verify --deep --strict "$APP_DIR"

ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_BINARY")"
[[ "$ARCHITECTURES" == *"arm64"* && "$ARCHITECTURES" == *"x86_64"* ]] \
  || fail "最终产物不是 Universal 2：$ARCHITECTURES"

for architecture in arm64 x86_64; do
  APP_UUID="$(/usr/bin/dwarfdump --uuid "$APP_BINARY" | /usr/bin/awk -v arch="$architecture" '$0 ~ "\\(" arch "\\)" { print $2; exit }')"
  DSYM_UUID="$(/usr/bin/dwarfdump --uuid "$DSYM_DIR" | /usr/bin/awk -v arch="$architecture" '$0 ~ "\\(" arch "\\)" { print $2; exit }')"
  [[ -n "$APP_UUID" && "$APP_UUID" == "$DSYM_UUID" ]] \
    || fail "$architecture 的 dSYM UUID 与应用不匹配。"
done

echo "$APP_DIR"
