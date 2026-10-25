#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
source "$PROJECT_DIR/scripts/audit_toolchain.zsh"
TEST_BINARY="$ARTIFACT_DIR/ScannerAudit-$ZIZAI_AUDIT_ARCH"

mkdir -p "$ARTIFACT_DIR"

"$ZIZAI_SWIFTC" \
  -sdk "$ZIZAI_SDK" \
  -target "$ZIZAI_AUDIT_TARGET" \
  -warnings-as-errors \
  -framework AppKit \
  "$PROJECT_DIR/Sources/Models.swift" \
  "$PROJECT_DIR/Sources/AppScanner.swift" \
  "$PROJECT_DIR/Tests/ScannerAudit.swift" \
  -o "$TEST_BINARY"

zizai_run_audit_binary "$TEST_BINARY"
