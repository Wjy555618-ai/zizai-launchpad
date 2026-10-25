#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
source "$PROJECT_DIR/scripts/audit_toolchain.zsh"
TEST_BINARY="$ARTIFACT_DIR/InteractionModelTests-$ZIZAI_AUDIT_ARCH"

mkdir -p "$ARTIFACT_DIR"

"$ZIZAI_SWIFTC" \
  -sdk "$ZIZAI_SDK" \
  -target "$ZIZAI_AUDIT_TARGET" \
  -warnings-as-errors \
  "$PROJECT_DIR/Sources/InteractionGeometry.swift" \
  "$PROJECT_DIR/Sources/ApplicationSearchPolicy.swift" \
  "$PROJECT_DIR/Tests/InteractionModelTests.swift" \
  -o "$TEST_BINARY"

zizai_run_audit_binary "$TEST_BINARY"

/bin/zsh "$PROJECT_DIR/scripts/run_scanner_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_store_behavior_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_tab_switch_performance_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_tab_content_performance_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_async_work_performance_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_login_item_audit.sh"
