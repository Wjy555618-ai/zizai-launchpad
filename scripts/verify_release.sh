#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
VALIDATION_PROFILE="interactive"
if [[ "${1:-}" == "--hosted-ci" && "$#" == 1 ]]; then
  VALIDATION_PROFILE="hosted-ci"
elif (( $# != 0 )); then
  echo "用法：verify_release.sh [--hosted-ci]" >&2
  exit 2
fi
NATIVE_ARCH="$(/usr/bin/uname -m)"
APP_DIR="$ARTIFACT_DIR/自在启动台.app"
TEST_DERIVED_DATA="$ARTIFACT_DIR/DerivedData-Tests"
TEST_RESULT_BUNDLE="$ARTIFACT_DIR/unit-tests.xcresult"
TEST_LOG="$ARTIFACT_DIR/unit-tests.log"
TEST_HOST_APP="$TEST_DERIVED_DATA/Build/Products/Debug/自在启动台.app"
ANALYZE_DERIVED_DATA="$ARTIFACT_DIR/DerivedData-Analyze"
ANALYZE_LOG="$ARTIFACT_DIR/static-analysis.log"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cleanup_test_registration() {
  [[ -x "$LSREGISTER" ]] || return 0
  local test_app=""
  for test_app in "$TEST_HOST_APP"; do
    if [[ -d "$test_app" ]]; then
      "$LSREGISTER" -u "$test_app" >/dev/null 2>&1 || true
    fi
  done
}
trap cleanup_test_registration EXIT

# A new attempt must never leave an older all-green evidence file behind. Only
# the interactive profile recreates it after every required gate has passed.
/bin/rm -f "$ARTIFACT_DIR/quality-evidence.json"

/usr/bin/xcrun swift-format lint --strict --recursive "$PROJECT_DIR/Sources" "$PROJECT_DIR/Tests"
/bin/zsh "$PROJECT_DIR/scripts/build.sh" >/dev/null
/usr/bin/codesign --verify --deep --strict "$APP_DIR"

# Keep local and remote release decisions on one gate. A separate CI-only
# analyzer would let a local evidence file claim success before the same source
# reaches the analyzer on GitHub.
if ! /usr/bin/xcodebuild analyze \
  -project "$PROJECT_DIR/自在启动台.xcodeproj" \
  -scheme "自在启动台" \
  -configuration Release \
  -destination "platform=macOS,arch=$NATIVE_ARCH" \
  -derivedDataPath "$ANALYZE_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO >"$ANALYZE_LOG" 2>&1; then
  /usr/bin/tail -n 160 "$ANALYZE_LOG" >&2
  exit 1
fi
/usr/bin/python3 "$PROJECT_DIR/scripts/verify_test_log.py" 静态分析 "$ANALYZE_LOG"

if [[ -d "$TEST_RESULT_BUNDLE" ]]; then
  /bin/rm -rf "$TEST_RESULT_BUNDLE"
fi

# Application-hosted XCTest must be signed by Xcode's local ad-hoc identity.
# Disabling signing leaves the Hardened Runtime host unable to load XCTest on a
# clean CI machine, even though a developer-authorized workstation may tolerate
# that invalid combination.
if ! /usr/bin/xcodebuild test \
  -project "$PROJECT_DIR/自在启动台.xcodeproj" \
  -scheme "自在启动台" \
  -destination "platform=macOS,arch=$NATIVE_ARCH" \
  -derivedDataPath "$TEST_DERIVED_DATA" \
  -enableCodeCoverage YES \
  -resultBundlePath "$TEST_RESULT_BUNDLE" \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 30 \
  -maximum-test-execution-time-allowance 60 >"$TEST_LOG" 2>&1; then
  /usr/bin/tail -n 160 "$TEST_LOG" >&2
  exit 1
fi
/usr/bin/python3 "$PROJECT_DIR/scripts/verify_test_log.py" XCTest "$TEST_LOG"
/bin/zsh "$PROJECT_DIR/scripts/verify_coverage.sh" "$TEST_RESULT_BUNDLE"
cleanup_test_registration

# macOS UI automation needs a trusted, interactive Accessibility session.
# Developer workstations execute the real application and enforce UI coverage;
# ephemeral GitHub-hosted desktops prove that the exact UI suite still builds,
# while the remaining deterministic gates continue below. Build-only evidence
# is intentionally never promoted to an XCUITest pass or quality-evidence.json.
if [[ "$VALIDATION_PROFILE" == "interactive" ]]; then
  /bin/zsh "$PROJECT_DIR/scripts/run_ui_tests.sh"
else
  /bin/zsh "$PROJECT_DIR/scripts/run_ui_tests.sh" --build-only
fi

ENTITLEMENTS="$(/usr/bin/codesign -d --entitlements :- "$APP_DIR" 2>/dev/null)"
[[ "$ENTITLEMENTS" == *"com.apple.security.app-sandbox"* ]]
[[ "$ENTITLEMENTS" == *"<true/>"* ]]
[[ "$ENTITLEMENTS" == *"com.apple.security.files.user-selected.read-only"* ]]
[[ "$ENTITLEMENTS" == *"com.apple.security.files.bookmarks.app-scope"* ]]
[[ "$ENTITLEMENTS" != *"com.apple.security.temporary-exception"* ]]
/usr/bin/python3 "$PROJECT_DIR/scripts/verify_security_capabilities.py" --app "$APP_DIR"

/usr/bin/plutil -lint "$PROJECT_DIR/Resources/Info.plist" >/dev/null
/usr/bin/plutil -lint "$PROJECT_DIR/Resources/PrivacyInfo.xcprivacy" >/dev/null
/usr/bin/plutil -lint "$PROJECT_DIR/Resources/ZizaiLaunchpad.entitlements" >/dev/null
/usr/bin/python3 -m json.tool "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json" >/dev/null
/bin/zsh "$PROJECT_DIR/Resources/IconComposer/verify_package.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_interaction_tests.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_tooltip_layering_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_canvas_interaction_performance_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_architecture_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_accessibility_render_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/verify_app_store_assets.sh"
/usr/bin/python3 "$PROJECT_DIR/scripts/verify_saved_layout.py"
/usr/bin/python3 "$PROJECT_DIR/scripts/verify_product_truth.py"

[[ ! "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PROJECT_DIR/Resources/Info.plist" 2>/dev/null || true)" ]]
[[ -d "$PROJECT_DIR/Resources/AppIcon.icon" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP_DIR/Contents/Info.plist")" == "AppIcon" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP_DIR/Contents/Info.plist")" == "AppIcon" ]]
[[ -f "$APP_DIR/Contents/Resources/AppIcon.icns" ]]
[[ -f "$APP_DIR/Contents/Resources/Assets.car" ]]
[[ ! -e "$APP_DIR/Contents/Resources/ZizaiAppIcon.icns" ]]

ICON_SVG="$PROJECT_DIR/Resources/AppIcon-Source.svg"
/usr/bin/grep -q 'width="1024" height="1024" viewBox="0 0 1024 1024"' "$ICON_SVG"
/usr/bin/grep -q 'id="foreground" transform="translate(-7 -5)"' "$ICON_SVG"
if /usr/bin/grep -E '<(script|foreignObject|image|filter|mask)([[:space:]>])' "$ICON_SVG" >/dev/null; then
  echo "图标 SVG 含有不允许的脚本、外链图像或预制遮罩/滤镜" >&2
  exit 1
fi

BRAND_MARK_SVG="$PROJECT_DIR/Resources/BrandMarkForeground.svg"
[[ -f "$BRAND_MARK_SVG" ]]
/usr/bin/grep -q 'width="1024" height="1024" viewBox="170 170 700 700"' "$BRAND_MARK_SVG"
if /usr/bin/grep -E '<(script|foreignObject|image|filter|mask)([[:space:]>])' "$BRAND_MARK_SVG" >/dev/null; then
  echo "界面品牌素材含有不允许的脚本、外链图像或预制遮罩/滤镜" >&2
  exit 1
fi
if /usr/bin/grep -E '<rect[^>]+(width="1024"|fill="(white|#FFF|#FFFFFF)")' "$BRAND_MARK_SVG" >/dev/null; then
  echo "界面品牌前景不得包含任何固化画布底色" >&2
  exit 1
fi

ICON_INFO="$(/usr/bin/sips -g pixelWidth -g pixelHeight -g hasAlpha "$PROJECT_DIR/Resources/AppIcon-1024.png" 2>/dev/null)"
[[ "$ICON_INFO" == *"pixelWidth: 1024"* ]]
[[ "$ICON_INFO" == *"pixelHeight: 1024"* ]]
[[ "$ICON_INFO" == *"hasAlpha: yes"* ]]

MAIN_ICON_HASH="$(/usr/bin/shasum -a 256 "$PROJECT_DIR/Resources/AppIcon-1024.png" | /usr/bin/awk '{print $1}')"
CATALOG_ICON_HASH="$(/usr/bin/shasum -a 256 "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" | /usr/bin/awk '{print $1}')"
[[ "$MAIN_ICON_HASH" == "$CATALOG_ICON_HASH" ]]

ICON_FILE_COUNT="$(/usr/bin/find "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset" -maxdepth 1 -type f -name '*.png' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
[[ "$ICON_FILE_COUNT" == "10" ]]

if [[ -f "$PROJECT_DIR/handoff/assets/app-icon-source.png" ]]; then
  HANDOFF_ICON_HASH="$(/usr/bin/shasum -a 256 "$PROJECT_DIR/handoff/assets/app-icon-source.png" | /usr/bin/awk '{print $1}')"
  [[ "$MAIN_ICON_HASH" == "$HANDOFF_ICON_HASH" ]]
fi

if /usr/bin/grep -R -E "NSWorkspace\.shared\.recycle|AuthorizationExecuteWithPrivileges|URLSession|Sparkle|SUUpdater" "$PROJECT_DIR/Sources" >/dev/null; then
  echo "发现不允许的高风险能力" >&2
  exit 1
fi

# This product intentionally has no App Intents. Skip that metadata phase at
# task-planning time instead of running the extractor and filtering its
# predictable "no dependency" warning. If AppIntents is introduced later, the
# source guard below forces the setting and documentation to be revisited.
/usr/bin/grep -q "LM_SKIP_METADATA_EXTRACTION = YES;" "$PROJECT_DIR/自在启动台.xcodeproj/project.pbxproj"
if /usr/bin/grep -R -E '^[[:space:]]*import[[:space:]]+AppIntents([[:space:]]|$)' "$PROJECT_DIR/Sources" >/dev/null; then
  echo "已引入 AppIntents；必须移除 LM_SKIP_METADATA_EXTRACTION 并恢复元数据提取。" >&2
  exit 1
fi

/usr/bin/grep -q "SMAppService.mainApp" "$PROJECT_DIR/Sources/LoginItemSettings.swift"
/usr/bin/grep -q "try service.unregister()" "$PROJECT_DIR/Sources/LoginItemSettings.swift"

if [[ "$VALIDATION_PROFILE" == "interactive" ]]; then
  /usr/bin/python3 "$PROJECT_DIR/scripts/generate_quality_evidence.py" "$ARTIFACT_DIR"
  echo "完整交互式工程门槛通过：构建、静态分析、临时签名、XCTest、真实 XCUITest、沙盒、隐私清单、交互模型、截图规格和图标资产均有效。"
else
  echo "GitHub 托管工程门槛通过：构建、静态分析、XCTest、XCUITest 编译、沙盒、隐私、交互、视觉和发布资产均有效。"
  echo "边界：托管配置没有生成真实 XCUITest 通过结论；发布仍要求受信任交互式 macOS 会话执行默认门槛。"
fi
echo "注意：这不代替真实用户研究、专项硬件矩阵或 Apple 人工审核。"
