#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
TEST_BINARY="$ARTIFACT_DIR/ScannerAudit"
XCRUN_BIN="${ZIZAI_XCRUN_PATH:-/usr/bin/xcrun}"
SWIFTC="$($XCRUN_BIN --find swiftc)"
SDK="$($XCRUN_BIN --sdk macosx --show-sdk-path)"

mkdir -p "$ARTIFACT_DIR"

"$SWIFTC" \
  -sdk "$SDK" \
  -target arm64-apple-macosx13.0 \
  -warnings-as-errors \
  -framework AppKit \
  "$PROJECT_DIR/Sources/Models.swift" \
  "$PROJECT_DIR/Sources/AppScanner.swift" \
  "$PROJECT_DIR/Tests/ScannerAudit.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"
