#!/bin/zsh

# The four UI runtime audits exercise the same production source graph. Compile
# that graph once per architecture and source revision, then dispatch distinct
# behavioral commands through one optimized executable. This keeps CI truthful
# without paying four independent full SwiftUI optimization passes.
if [[ -z "${PROJECT_DIR:-}" || -z "${ARTIFACT_DIR:-}" ]]; then
  print -u2 "ui_runtime_audit_harness.zsh requires PROJECT_DIR and ARTIFACT_DIR"
  return 1
fi

source "$PROJECT_DIR/scripts/audit_toolchain.zsh"
source "$PROJECT_DIR/scripts/audit_source_manifest.zsh"

typeset -ga ZIZAI_UI_RUNTIME_AUDIT_FILES=(
  "$PROJECT_DIR/Tests/UIRuntimeAuditMain.swift"
  "$PROJECT_DIR/Tests/TabContentPerformanceAudit.swift"
  "$PROJECT_DIR/Tests/TooltipLayeringAudit.swift"
  "$PROJECT_DIR/Tests/CanvasInteractionPerformanceAudit.swift"
  "$PROJECT_DIR/Tests/VisualRenderAudit.swift"
)

ZIZAI_UI_RUNTIME_AUDIT_BINARY="$ARTIFACT_DIR/UIRuntimeAudit-$ZIZAI_AUDIT_ARCH"
ZIZAI_UI_RUNTIME_AUDIT_STAMP="$ZIZAI_UI_RUNTIME_AUDIT_BINARY.sha256"

zizai_ui_runtime_audit_digest() {
  {
    print -r -- "$ZIZAI_AUDIT_TARGET"
    "$ZIZAI_SWIFTC" --version 2>&1
    /usr/bin/shasum -a 256 \
      "$PROJECT_DIR/scripts/ui_runtime_audit_harness.zsh" \
      "${ZIZAI_AUDIT_SOURCE_FILES[@]}" \
      "${ZIZAI_UI_RUNTIME_AUDIT_FILES[@]}"
  } | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

zizai_ensure_ui_runtime_audit_binary() {
  /bin/mkdir -p "$ARTIFACT_DIR"
  local expected_digest
  expected_digest="$(zizai_ui_runtime_audit_digest)"
  if [[ -x "$ZIZAI_UI_RUNTIME_AUDIT_BINARY" \
    && -f "$ZIZAI_UI_RUNTIME_AUDIT_STAMP" \
    && "$(<"$ZIZAI_UI_RUNTIME_AUDIT_STAMP")" == "$expected_digest" ]]; then
    return 0
  fi

  local temporary_binary="$ZIZAI_UI_RUNTIME_AUDIT_BINARY.tmp"
  local temporary_stamp="$ZIZAI_UI_RUNTIME_AUDIT_STAMP.tmp"
  /bin/rm -f "$temporary_binary" "$temporary_stamp"
  "$ZIZAI_SWIFTC" \
    -sdk "$ZIZAI_SDK" \
    -target "$ZIZAI_AUDIT_TARGET" \
    -D ZIZAI_VISUAL_AUDIT \
    -O \
    -warnings-as-errors \
    -framework AppKit \
    -framework SwiftUI \
    -framework Combine \
    "${ZIZAI_AUDIT_SOURCE_FILES[@]}" \
    "${ZIZAI_UI_RUNTIME_AUDIT_FILES[@]}" \
    -o "$temporary_binary"
  print -r -- "$expected_digest" >"$temporary_stamp"
  /bin/mv -f "$temporary_binary" "$ZIZAI_UI_RUNTIME_AUDIT_BINARY"
  /bin/mv -f "$temporary_stamp" "$ZIZAI_UI_RUNTIME_AUDIT_STAMP"
}

zizai_run_ui_runtime_audit() {
  zizai_ensure_ui_runtime_audit_binary
  zizai_run_audit_binary "$ZIZAI_UI_RUNTIME_AUDIT_BINARY" "$@"
}
