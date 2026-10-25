#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
PACKAGE_NAME="自在启动台-AppStore首发版项目接力包"
ROOT_NAME="自在启动台-AppStore首发版"
DEST_DIR="${ZIZAI_HANDOFF_DEST:-$HOME/Downloads}"
ZIP_PATH="$DEST_DIR/$PACKAGE_NAME.zip"
ZIP_SUM_PATH="$ZIP_PATH.sha256"
TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/zizai-app-store-handoff-test.XXXXXX")"
EXTRACT_ROOT="$TEST_ROOT/extracted"
EXTRACTED_PACKAGE="$EXTRACT_ROOT/$ROOT_NAME"
RELEASE_LOG="$TEST_ROOT/release-verification.log"

cleanup_test() {
  local exit_code=$?
  if [[ "$TEST_ROOT" == *"/zizai-app-store-handoff-test."* && -d "$TEST_ROOT" ]]; then
    /bin/rm -rf "$TEST_ROOT"
  fi
  return $exit_code
}
trap cleanup_test EXIT

/bin/zsh "$PROJECT_DIR/scripts/package_app_store_handoff.sh" >/dev/null
[[ -s "$ZIP_PATH" && -s "$ZIP_SUM_PATH" ]]
(
  cd "${ZIP_PATH:h}"
  /usr/bin/shasum -a 256 -c "${ZIP_SUM_PATH:t}" >/dev/null
)

/bin/mkdir -p "$EXTRACT_ROOT"
/usr/bin/ditto -x -k "$ZIP_PATH" "$EXTRACT_ROOT"
[[ -d "$EXTRACTED_PACKAGE" ]]

EXPECTED_TOP_LEVEL=(
  .swift-format
  APP_STORE_HANDOFF_MANIFEST.json
  AppStore
  LICENSE
  Resources
  SHA256SUMS
  Sources
  Tests
  evidence
  scripts
  自在启动台.xcodeproj
)
EXPECTED_TOP_LEVEL+=(
  "${(@f)$(/usr/bin/find "$PROJECT_DIR" -maxdepth 1 -type f -name '*.md' -print \
    | /usr/bin/sed 's#^.*/##')}"
)
EXPECTED_TOP_LEVEL=("${(@f)$(/usr/bin/printf '%s\n' "${EXPECTED_TOP_LEVEL[@]}" | /usr/bin/sort)}")
ACTUAL_TOP_LEVEL=("${(@f)$(/usr/bin/find "$EXTRACTED_PACKAGE" -mindepth 1 -maxdepth 1 -print | /usr/bin/sed 's#^.*/##' | /usr/bin/sort)}")
[[ "${(j:|:)ACTUAL_TOP_LEVEL}" == "${(j:|:)EXPECTED_TOP_LEVEL}" ]]

(
  cd "$EXTRACTED_PACKAGE"
  /usr/bin/shasum -a 256 -c SHA256SUMS >/dev/null
  /usr/bin/python3 -m json.tool APP_STORE_HANDOFF_MANIFEST.json >/dev/null
  /usr/bin/plutil -lint Resources/Info.plist Resources/ZizaiLaunchpad.entitlements Resources/PrivacyInfo.xcprivacy >/dev/null
)

# Check the extracted artifact before invoking Xcode: xcodebuild may legitimately
# recreate project.xcworkspace during validation, but it must not be shipped.
if /usr/bin/find "$EXTRACTED_PACKAGE" \
  \( -name 'xcuserdata' -o -name '*.xcuserstate' -o -name 'project.xcworkspace' \) \
  -print | /usr/bin/grep -q .; then
  echo "接力包混入 Xcode 本机用户状态或自动生成的工作区" >&2
  exit 1
fi

source "$EXTRACTED_PACKAGE/scripts/release_config.sh"
MARKETING_VERSION="$(zizai_require_release_setting "$EXTRACTED_PACKAGE" MARKETING_VERSION)"
BUILD_NUMBER="$(zizai_require_release_setting "$EXTRACTED_PACKAGE" CURRENT_PROJECT_VERSION)"
[[ "$MARKETING_VERSION" == "1.0.0" && "$BUILD_NUMBER" == "1" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$EXTRACTED_PACKAGE/Resources/Info.plist")" == '$(PRODUCT_BUNDLE_IDENTIFIER)' ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXTRACTED_PACKAGE/Resources/Info.plist")" == '$(MARKETING_VERSION)' ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXTRACTED_PACKAGE/Resources/Info.plist")" == '$(CURRENT_PROJECT_VERSION)' ]]

if /usr/bin/find "$EXTRACTED_PACKAGE" \
  \( -name '*.app' -o -name '*.zip' -o -name '*.dmg' -o -name '*.pkg' -o -name 'build' -o -name '.spec-to-demo' \) \
  -print | /usr/bin/grep -q .; then
  echo "接力包混入构建产物、归档包或历史工作目录" >&2
  exit 1
fi

for FORBIDDEN_PATH in \
  RELEASE_MANIFEST.json \
  START_HERE.md \
  scripts/install_on_mac.sh \
  scripts/package_codex_installer.sh \
  scripts/verify_codex_installer.sh \
  handoff \
  .DS_Store; do
  [[ ! -e "$EXTRACTED_PACKAGE/$FORBIDDEN_PATH" ]] || {
    echo "接力包混入禁止内容：$FORBIDDEN_PATH" >&2
    exit 1
  }
done

if /usr/bin/grep -R -I -E '0\.3\.0|0\.3\.1|自在启动台-Codex安装包' "$EXTRACTED_PACKAGE" >/dev/null; then
  echo "接力包仍包含旧开发版本号或旧安装包名称" >&2
  exit 1
fi

if /usr/bin/find "$EXTRACTED_PACKAGE" -type f \
  \( -name '*0.3.0*' -o -name '*0.3.1*' -o -name '*Codex安装包*' \) \
  -print | /usr/bin/grep -q .; then
  echo "接力包文件名仍包含旧版本痕迹" >&2
  exit 1
fi

if /usr/bin/find "$EXTRACTED_PACKAGE" -type f \
  \( -name '布局.json' -o -name '布局.backup.json' -o -name '*.p12' -o -name '*.cer' \
     -o -name '*.mobileprovision' -o -name '*.provisionprofile' -o -name '*.keychain' \
     -o -name '.env' -o -name 'id_rsa' -o -name 'id_ed25519' \) \
  -print | /usr/bin/grep -q .; then
  echo "接力包混入个人布局、签名证书或账号凭据文件" >&2
  exit 1
fi

(
  cd "$EXTRACTED_PACKAGE"
  /bin/zsh ./scripts/verify_release.sh >"$RELEASE_LOG"
)

ZIP_HASH="$(/usr/bin/shasum -a 256 "$ZIP_PATH" | /usr/bin/awk '{print $1}')"
PACKAGE_FILE_COUNT="$(/usr/bin/wc -l < "$EXTRACTED_PACKAGE/SHA256SUMS" | /usr/bin/tr -d ' ')"

echo "APP_STORE_HANDOFF_VERIFICATION_OK"
echo "ZIP_PATH=$ZIP_PATH"
echo "ZIP_SHA256=$ZIP_HASH"
echo "PACKAGE_FILE_COUNT=$PACKAGE_FILE_COUNT"
echo "CLEAN_EXTRACTION=PASS"
echo "FILE_HASHES=PASS"
echo "APP_STORE_INITIAL_VERSION=1.0.0(1)"
echo "PREVIOUS_PACKAGES_EXCLUDED=PASS"
echo "PREBUILT_APPS_EXCLUDED=PASS"
echo "PERSONAL_DATA_EXCLUDED=PASS"
echo "CLEAN_EXTRACT_SOURCE_VERIFICATION=PASS"
