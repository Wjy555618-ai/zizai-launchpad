#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
MODE="execute"
if [[ "${1:-}" == "--build-only" && "$#" == 1 ]]; then
  MODE="build-only"
elif (( $# != 0 )); then
  echo "用法：run_ui_tests.sh [--build-only]" >&2
  exit 2
fi
NATIVE_ARCH="$(/usr/bin/uname -m)"
PUBLISHED_RESULT_BUNDLE="$ARTIFACT_DIR/ui-tests.xcresult"
TEST_LOG="$ARTIFACT_DIR/ui-tests.log"
/bin/mkdir -p "$ARTIFACT_DIR"
UI_RUNTIME_ROOT="${ZIZAI_UI_RUNTIME_ROOT:-${TMPDIR:-/tmp}/zizai-launchpad-ui-tests-$UID}"
DERIVED_DATA="$UI_RUNTIME_ROOT/DerivedData"
RESULT_BUNDLE="$UI_RUNTIME_ROOT/ui-tests.xcresult"
TEST_HOST_APP="$DERIVED_DATA/Build/Products/Debug/自在启动台.app"
TEST_RUNNER_APP="$DERIVED_DATA/Build/Products/Debug/自在启动台UITests-Runner.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
REMOVAL_FIXTURE="/Applications/ZizaiLaunchpadUITest-7.app"
REMOVAL_FIXTURE_MARKER="ZizaiLaunchpadRemovalMarker"

owned_removal_fixture_in_trash() {
  local candidate=""
  for candidate in "$HOME"/.Trash/ZizaiLaunchpadUITest-7*.app(N/); do
    if [[ -f "$candidate/$REMOVAL_FIXTURE_MARKER" ]]; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}

cleanup_removal_fixture() {
  local trashed_fixture=""
  if [[ -f "$REMOVAL_FIXTURE/$REMOVAL_FIXTURE_MARKER" ]]; then
    /bin/rm -rf -- "$REMOVAL_FIXTURE"
  fi
  trashed_fixture="$(owned_removal_fixture_in_trash || true)"
  if [[ -n "$trashed_fixture" && -f "$trashed_fixture/$REMOVAL_FIXTURE_MARKER" ]]; then
    /bin/rm -rf -- "$trashed_fixture"
  fi
}

prepare_removal_fixture() {
  if [[ -e "$REMOVAL_FIXTURE" ]]; then
    echo "专用 UI 回收夹具已存在；为避免覆盖未知内容，本次验收中止：$REMOVAL_FIXTURE" >&2
    exit 1
  fi
  if owned_removal_fixture_in_trash >/dev/null; then
    echo "废纸篓中仍有带标记的专用 UI 回收夹具；本次验收中止。" >&2
    exit 1
  fi
  /bin/mkdir -p "$REMOVAL_FIXTURE"
  /usr/bin/printf '%s\n' "zizai-launchpad-ui-removal-fixture" > \
    "$REMOVAL_FIXTURE/$REMOVAL_FIXTURE_MARKER"
}

cleanup_test_registration() {
  [[ -x "$LSREGISTER" ]] || return 0
  local test_app=""
  for test_app in "$TEST_HOST_APP" "$TEST_RUNNER_APP"; do
    if [[ -d "$test_app" ]]; then
      "$LSREGISTER" -u "$test_app" >/dev/null 2>&1 || true
    fi
  done
  cleanup_removal_fixture
}
trap cleanup_test_registration EXIT

/bin/mkdir -p "$UI_RUNTIME_ROOT"
/bin/rm -rf "$DERIVED_DATA" "$RESULT_BUNDLE"

if [[ "$MODE" == "build-only" ]]; then
  BUILD_LOG="$ARTIFACT_DIR/ui-tests-build.log"
  if ! /usr/bin/xcodebuild build-for-testing \
    -project "$PROJECT_DIR/自在启动台.xcodeproj" \
    -scheme "自在启动台-UI" \
    -testPlan "LaunchpadUITests" \
    -destination "platform=macOS,arch=$NATIVE_ARCH" \
    -derivedDataPath "$DERIVED_DATA" \
    -enableCodeCoverage YES >"$BUILD_LOG" 2>&1; then
    /usr/bin/tail -n 160 "$BUILD_LOG" >&2
    exit 1
  fi
  /usr/bin/python3 "$PROJECT_DIR/scripts/verify_test_log.py" "XCUITest 编译" "$BUILD_LOG"
  XCTESTRUN_COUNT="$(/usr/bin/find "$DERIVED_DATA/Build/Products" -type f -name '*.xctestrun' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
  DECLARED_COUNT="$(/usr/bin/grep -Ec '^[[:space:]]*func[[:space:]]+test[A-Za-z0-9_]*[[:space:]]*\(' "$PROJECT_DIR/Tests/XCUITests/LaunchpadUITests.swift")"
  if (( XCTESTRUN_COUNT < 1 || DECLARED_COUNT < 1 )); then
    echo "XCUITest 编译产物不完整：xctestrun=$XCTESTRUN_COUNT, declared=$DECLARED_COUNT" >&2
    exit 1
  fi
  echo "XCUITest 编译契约通过：$DECLARED_COUNT 项当前测试已进入可执行 xctestrun；未声称已执行。"
  exit 0
fi

prepare_removal_fixture

if ! /usr/bin/xcodebuild test \
  -project "$PROJECT_DIR/自在启动台.xcodeproj" \
  -scheme "自在启动台-UI" \
  -testPlan "LaunchpadUITests" \
  -destination "platform=macOS,arch=$NATIVE_ARCH" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -enableCodeCoverage YES \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 60 \
  -maximum-test-execution-time-allowance 90 >"$TEST_LOG" 2>&1; then
  /usr/bin/tail -n 160 "$TEST_LOG" >&2
  exit 1
fi

/usr/bin/python3 "$PROJECT_DIR/scripts/verify_test_log.py" XCUITest "$TEST_LOG"

if [[ -e "$REMOVAL_FIXTURE" ]]; then
  echo "真实回收验收失败：专用 App 仍留在 /Applications。" >&2
  exit 1
fi
TRASHED_REMOVAL_FIXTURE="$(owned_removal_fixture_in_trash || true)"
if [[ -z "$TRASHED_REMOVAL_FIXTURE" ]]; then
  echo "真实回收验收失败：废纸篓中未找到带标记的专用 App。" >&2
  exit 1
fi
echo "真实回收验收通过：一次授权后专用 App 已移入废纸篓。"

SUMMARY_JSON="$(/usr/bin/mktemp "$ARTIFACT_DIR/ui-tests-summary.XXXXXX")"
/usr/bin/xcrun xcresulttool get test-results summary \
  --path "$RESULT_BUNDLE" \
  --format json > "$SUMMARY_JSON"
/usr/bin/python3 - "$SUMMARY_JSON" "$PROJECT_DIR/Tests/XCUITests/LaunchpadUITests.swift" <<'PY'
import json
from pathlib import Path
import re
import sys

summary = json.load(open(sys.argv[1], encoding="utf-8"))
test_source = Path(sys.argv[2]).read_text(encoding="utf-8")
expected = len(re.findall(r"^\s*func\s+test[A-Za-z0-9_]*\s*\(", test_source, re.MULTILINE))
passed = int(summary.get("passedTests", 0))
failed = int(summary.get("failedTests", 0))
skipped = int(summary.get("skippedTests", 0))
warnings = summary.get("runtimeWarnings", [])
if expected == 0 or summary.get("result") != "Passed" or failed != 0 or skipped != 0 or passed != expected:
    raise SystemExit(
        f"XCUITest 证据不完整: result={summary.get('result')}, "
        f"declared={expected}, passed={passed}, failed={failed}, skipped={skipped}"
    )
if warnings:
    raise SystemExit(f"XCUITest 出现运行时警告: {warnings}")
print(f"XCUITest 真实执行通过: {passed} passed, 0 failed, 0 skipped")
PY
/bin/rm -f "$SUMMARY_JSON"
/bin/zsh "$PROJECT_DIR/scripts/verify_coverage.sh" "$RESULT_BUNDLE" ui

# UI test runners are ad-hoc helper apps. Keeping their executable and live
# result stream outside Documents avoids macOS Files & Folders prompts from
# interrupting pointer automation. Publish the finished immutable evidence
# only after the runner has exited.
/bin/rm -rf "$PUBLISHED_RESULT_BUNDLE"
/usr/bin/ditto "$RESULT_BUNDLE" "$PUBLISHED_RESULT_BUNDLE"

echo "XCUITest 结果证据：$PUBLISHED_RESULT_BUNDLE"
