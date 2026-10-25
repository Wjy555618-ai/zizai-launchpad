#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
AUDIT_ARCH="${ZIZAI_AUDIT_ARCH:-arm64}"
TEST_BINARY="$ARTIFACT_DIR/LoginItemSettingsAudit-$AUDIT_ARCH"
XCRUN_BIN="${ZIZAI_XCRUN_PATH:-/usr/bin/xcrun}"
SWIFTC="$($XCRUN_BIN --find swiftc)"
SDK="$($XCRUN_BIN --sdk macosx --show-sdk-path)"

mkdir -p "$ARTIFACT_DIR"

"$SWIFTC" \
  -sdk "$SDK" \
  -target "$AUDIT_ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  -framework AppKit \
  -framework Combine \
  -framework CoreServices \
  -framework ServiceManagement \
  -framework SwiftUI \
  -framework UniformTypeIdentifiers \
  "$PROJECT_DIR/Sources/Models.swift" \
  "$PROJECT_DIR/Sources/AppScanner.swift" \
  "$PROJECT_DIR/Sources/ApplicationFolderAccess.swift" \
  "$PROJECT_DIR/Sources/LaunchPresentation.swift" \
  "$PROJECT_DIR/Sources/LoginItemSettings.swift" \
  "$PROJECT_DIR/Tests/LoginItemSettingsAudit.swift" \
  -o "$TEST_BINARY"

if [[ "$AUDIT_ARCH" == "x86_64" && "$(/usr/bin/uname -m)" == "arm64" ]]; then
  /usr/bin/arch -x86_64 "$TEST_BINARY"
else
  "$TEST_BINARY"
fi
