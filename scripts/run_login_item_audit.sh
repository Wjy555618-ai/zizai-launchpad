#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
source "$PROJECT_DIR/scripts/audit_toolchain.zsh"
TEST_BINARY="$ARTIFACT_DIR/LoginItemSettingsAudit-$ZIZAI_AUDIT_ARCH"

mkdir -p "$ARTIFACT_DIR"

"$ZIZAI_SWIFTC" \
  -sdk "$ZIZAI_SDK" \
  -target "$ZIZAI_AUDIT_TARGET" \
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
  "$PROJECT_DIR/Tests/XCTest/TestApplicationFolderAuthorizationService.swift" \
  "$PROJECT_DIR/Tests/LoginItemSettingsAudit.swift" \
  -o "$TEST_BINARY"

zizai_run_audit_binary "$TEST_BINARY"
