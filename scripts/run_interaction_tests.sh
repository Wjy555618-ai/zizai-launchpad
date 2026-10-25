#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
TEST_BINARY="$ARTIFACT_DIR/InteractionModelTests"
XCRUN_BIN="${ZIZAI_XCRUN_PATH:-/usr/bin/xcrun}"
SWIFTC="$($XCRUN_BIN --find swiftc)"
SDK="$($XCRUN_BIN --sdk macosx --show-sdk-path)"

mkdir -p "$ARTIFACT_DIR"

"$SWIFTC" \
  -sdk "$SDK" \
  -target arm64-apple-macosx13.0 \
  -warnings-as-errors \
  "$PROJECT_DIR/Sources/InteractionGeometry.swift" \
  "$PROJECT_DIR/Sources/ApplicationSearchPolicy.swift" \
  "$PROJECT_DIR/Tests/InteractionModelTests.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"

/bin/zsh "$PROJECT_DIR/scripts/run_scanner_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_store_behavior_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_tab_switch_performance_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_tab_content_performance_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_async_work_performance_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_login_item_audit.sh"
