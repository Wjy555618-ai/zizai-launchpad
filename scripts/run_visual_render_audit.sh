#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
OUTPUT="${1:-/tmp/zizai-visual-audit.png}"
LAYOUT_MODE="${2:-space}"
APPEARANCE="${3:-dark}"
ACCESSIBILITY_MODE="${4:-standard}"
source "$PROJECT_DIR/scripts/ui_runtime_audit_harness.zsh"

case "$ACCESSIBILITY_MODE" in
  standard)
    FORCE_REDUCED_MOTION=0
    FORCE_REDUCED_TRANSPARENCY=0
    ;;
  reduced)
    FORCE_REDUCED_MOTION=1
    FORCE_REDUCED_TRANSPARENCY=1
    ;;
  reducedMotion)
    FORCE_REDUCED_MOTION=1
    FORCE_REDUCED_TRANSPARENCY=0
    ;;
  *)
    print -u2 "Unsupported accessibility render mode: $ACCESSIBILITY_MODE"
    exit 2
    ;;
esac

ZIZAI_ICON_PATH="$PROJECT_DIR/Resources/AppIcon-1024.png" \
ZIZAI_BRAND_MARK_PATH="$PROJECT_DIR/Resources/BrandMarkForeground.svg" \
ZIZAI_FORCE_REDUCED_MOTION="$FORCE_REDUCED_MOTION" \
ZIZAI_FORCE_REDUCED_TRANSPARENCY="$FORCE_REDUCED_TRANSPARENCY" \
  zizai_run_ui_runtime_audit render \
  "$OUTPUT" "$LAYOUT_MODE" "$APPEARANCE" "$ACCESSIBILITY_MODE" || exit $?
