#!/bin/zsh
set -u

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
BUILD_APP_DIR="$ARTIFACT_DIR/自在启动台.app"
INSTALLED_APP_DIR="${ZIZAI_INSTALL_DEST:-/Applications/自在启动台.app}"
APP_DIR="$BUILD_APP_DIR"
DSYM_DIR="$ARTIFACT_DIR/自在启动台.app.dSYM"
INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"
FAILED=0
source "$PROJECT_DIR/scripts/release_config.sh"

# The installer deliberately removes the repository's .app after an atomic
# install so LaunchServices can never index two active copies. Audit that sole
# installed copy when the transient build copy is absent; the matching dSYM is
# retained in build/ for crash-symbol validation.
if [[ ! -d "$APP_DIR" && -d "$INSTALLED_APP_DIR" ]]; then
  APP_DIR="$INSTALLED_APP_DIR"
fi

pass() {
  echo "通过  $1"
}

block() {
  echo "阻断  $1"
  FAILED=1
}

if [[ -d "/Applications/Xcode.app" ]] && /usr/bin/xcrun --find xcodebuild >/dev/null 2>&1; then
  pass "已安装完整 Xcode，可创建 Archive 并执行 Validate App"
else
  block "未安装完整 Xcode；当前只有命令行工具，不能生成或验证 Mac App Store Archive"
fi

if /usr/bin/find "$PROJECT_DIR" -maxdepth 2 \( -name '*.xcodeproj' -o -name '*.xcworkspace' \) | /usr/bin/grep -q .; then
  pass "存在可供 App Store 提交的 Xcode 工程"
else
  block "缺少 Xcode 工程；当前脚本构建只能用于本机体验和回归"
fi

BUNDLE_ID="$(zizai_release_setting "$PROJECT_DIR" PRODUCT_BUNDLE_IDENTIFIER 2>/dev/null || true)"
MARKETING_VERSION="$(zizai_release_setting "$PROJECT_DIR" MARKETING_VERSION 2>/dev/null || true)"
BUILD_NUMBER="$(zizai_release_setting "$PROJECT_DIR" CURRENT_PROJECT_VERSION 2>/dev/null || true)"

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null || true)" == '$(PRODUCT_BUNDLE_IDENTIFIER)' \
   && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || true)" == '$(MARKETING_VERSION)' \
   && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST" 2>/dev/null || true)" == '$(CURRENT_PROJECT_VERSION)' ]]; then
  pass "Info.plist 使用 Xcode 唯一发布配置源"
else
  block "Info.plist 仍存在写死的版本或标识，容易造成提交版本错乱"
fi

if [[ "$MARKETING_VERSION" == "1.0.0" && "$BUILD_NUMBER" == "1" ]]; then
  pass "App Store 首发版本已统一为 1.0.0 (1)"
else
  block "App Store 首发版本不一致：${MARKETING_VERSION:-未配置} (${BUILD_NUMBER:-未配置})"
fi

if [[ -n "$BUNDLE_ID" && "$BUNDLE_ID" != local.* ]]; then
  pass "已配置最终 Bundle ID：$BUNDLE_ID"
else
  block "Bundle ID 仍是本地占位符：${BUNDLE_ID:-未配置}"
fi

if [[ -d "$APP_DIR" ]]; then
  pass "已找到当前可验证应用产物：$APP_DIR"
  SIGNATURE="$(/usr/bin/codesign -dvv "$APP_DIR" 2>&1 || true)"
  if [[ "$SIGNATURE" == *"Signature=adhoc"* ]] || [[ "$SIGNATURE" == *"TeamIdentifier=not set"* ]]; then
    block "当前应用是临时签名，没有 Apple Developer Team 和 Mac App Distribution 签名"
  else
    pass "应用已使用正式开发者身份签名"
  fi
else
  block "尚未生成本地应用产物"
fi

if [[ -d "$APP_DIR" && -d "$DSYM_DIR" ]]; then
  DSYM_MATCHES=1
  for architecture in arm64 x86_64; do
    APP_UUID="$(/usr/bin/dwarfdump --uuid "$APP_DIR/Contents/MacOS/ZizaiLaunchpad" | /usr/bin/awk -v arch="$architecture" '$0 ~ "\\(" arch "\\)" { print $2; exit }')"
    DSYM_UUID="$(/usr/bin/dwarfdump --uuid "$DSYM_DIR" | /usr/bin/awk -v arch="$architecture" '$0 ~ "\\(" arch "\\)" { print $2; exit }')"
    [[ -n "$APP_UUID" && "$APP_UUID" == "$DSYM_UUID" ]] || DSYM_MATCHES=0
  done
  if [[ "$DSYM_MATCHES" -eq 1 ]]; then
    pass "Release dSYM 完整且与 Universal 2 二进制匹配"
  else
    block "Release dSYM UUID 与应用不匹配"
  fi
else
  block "缺少 Release dSYM，无法保证上线后崩溃报告可符号化"
fi

if /usr/bin/grep -q "com.apple.security.temporary-exception" "$PROJECT_DIR/Resources/ZizaiLaunchpad.entitlements"; then
  block "仍使用 App Sandbox 临时例外权限"
else
  pass "没有 App Sandbox 临时例外权限"
fi

if /usr/bin/grep -q "com.apple.security.files.user-selected.read-only" "$PROJECT_DIR/Resources/ZizaiLaunchpad.entitlements"; then
  pass "用户应用文件夹使用标准的用户选择只读权限"
else
  block "缺少用户选择只读权限，无法在沙盒中恢复用户应用文件夹"
fi

if /usr/bin/python3 "$PROJECT_DIR/scripts/verify_security_capabilities.py" >/dev/null; then
  pass "持久用户文件夹授权与 app-scoped security bookmark 权限一致"
else
  block "持久用户文件夹授权与沙盒 entitlement 不一致"
fi

if [[ -f "$PROJECT_DIR/APP_STORE_METADATA_ZH.md" && -f "$PROJECT_DIR/PRIVACY_POLICY_ZH.md" ]]; then
  pass "已准备中文商店元数据和隐私政策正文"
else
  block "商店元数据或隐私政策正文缺失"
fi

if /bin/zsh "$PROJECT_DIR/scripts/verify_app_store_assets.sh" >/dev/null; then
  pass "App Store 截图数量、尺寸和无 Alpha 规格通过"
else
  block "App Store 截图不符合 Apple 的 Mac 截图规格"
fi

if [[ "$FAILED" -eq 0 ]]; then
  echo "结论：工程已具备进入 App Store Connect 提交验证的本地条件。"
  exit 0
fi

echo "结论：产品本地体验可继续验收，但现在还不是可上传 App Store 的正式提交包。"
exit 1
