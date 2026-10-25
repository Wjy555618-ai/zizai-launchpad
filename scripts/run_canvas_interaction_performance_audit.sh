#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
TEST_BINARY="$ARTIFACT_DIR/CanvasInteractionPerformanceAudit"
XCRUN_BIN="${ZIZAI_XCRUN_PATH:-/usr/bin/xcrun}"
SWIFTC="$($XCRUN_BIN --find swiftc)"
SDK="$($XCRUN_BIN --sdk macosx --show-sdk-path)"
source "$PROJECT_DIR/scripts/audit_source_manifest.zsh"

mkdir -p "$ARTIFACT_DIR"

"$SWIFTC" \
  -sdk "$SDK" \
  -target arm64-apple-macosx13.0 \
  -warnings-as-errors \
  -O \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  "${ZIZAI_AUDIT_SOURCE_FILES[@]}" \
  "$PROJECT_DIR/Tests/CanvasInteractionPerformanceAudit.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"
