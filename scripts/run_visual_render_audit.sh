#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
OUTPUT="${1:-/tmp/zizai-visual-audit.png}"
LAYOUT_MODE="${2:-space}"
APPEARANCE="${3:-dark}"
ACCESSIBILITY_MODE="${4:-standard}"
source "$PROJECT_DIR/scripts/audit_toolchain.zsh"
TEST_BINARY="$ARTIFACT_DIR/VisualRenderAudit-$ZIZAI_AUDIT_ARCH"
source "$PROJECT_DIR/scripts/audit_source_manifest.zsh"

mkdir -p "$ARTIFACT_DIR"

if [[ "${ZIZAI_REUSE_VISUAL_AUDIT_BINARY:-0}" != 1 || ! -x "$TEST_BINARY" ]]; then
  "$ZIZAI_SWIFTC" \
    -sdk "$ZIZAI_SDK" \
    -target "$ZIZAI_AUDIT_TARGET" \
    -D ZIZAI_VISUAL_AUDIT \
    -warnings-as-errors \
    -framework AppKit \
    -framework SwiftUI \
    -framework Combine \
    "${ZIZAI_AUDIT_SOURCE_FILES[@]}" \
    "$PROJECT_DIR/Tests/VisualRenderAudit.swift" \
    -o "$TEST_BINARY"
fi

ZIZAI_ICON_PATH="$PROJECT_DIR/Resources/AppIcon-1024.png" \
ZIZAI_BRAND_MARK_PATH="$PROJECT_DIR/Resources/BrandMarkForeground.svg" \
ZIZAI_FORCE_REDUCED_EFFECTS="$([[ "$ACCESSIBILITY_MODE" == "reduced" ]] && echo 1 || echo 0)" \
  zizai_run_audit_binary "$TEST_BINARY" "$OUTPUT" "$LAYOUT_MODE" "$APPEARANCE" "$ACCESSIBILITY_MODE"
