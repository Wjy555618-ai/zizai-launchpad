#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
source "$PROJECT_DIR/scripts/audit_toolchain.zsh"
TEST_BINARY="$ARTIFACT_DIR/AsyncWorkPerformanceAudit-$ZIZAI_AUDIT_ARCH"
source "$PROJECT_DIR/scripts/audit_source_manifest.zsh"

mkdir -p "$ARTIFACT_DIR"

"$ZIZAI_SWIFTC" \
  -sdk "$ZIZAI_SDK" \
  -target "$ZIZAI_AUDIT_TARGET" \
  -O \
  -warnings-as-errors \
  -strict-concurrency=complete \
  -framework AppKit \
  -framework Combine \
  "$PROJECT_DIR/Sources/ApplicationFolderAccess.swift" \
  "${ZIZAI_STORE_AUDIT_SOURCE_FILES[@]}" \
  "$PROJECT_DIR/Tests/AsyncWorkPerformanceAudit.swift" \
  -o "$TEST_BINARY"

zizai_run_audit_binary "$TEST_BINARY"
