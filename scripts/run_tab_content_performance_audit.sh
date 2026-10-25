#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
source "$PROJECT_DIR/scripts/audit_toolchain.zsh"
TEST_BINARY="$ARTIFACT_DIR/TabContentPerformanceAudit-$ZIZAI_AUDIT_ARCH"
source "$PROJECT_DIR/scripts/audit_source_manifest.zsh"

mkdir -p "$ARTIFACT_DIR"

"$ZIZAI_SWIFTC" \
  -sdk "$ZIZAI_SDK" \
  -target "$ZIZAI_AUDIT_TARGET" \
  -O \
  -warnings-as-errors \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  "${ZIZAI_AUDIT_SOURCE_FILES[@]}" \
  "$PROJECT_DIR/Tests/TabContentPerformanceAudit.swift" \
  -o "$TEST_BINARY"

zizai_run_audit_binary "$TEST_BINARY"
