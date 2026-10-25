#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
OUTPUT_DIR="$PROJECT_DIR/AppStore/Screenshots/zh-Hans"
TEMP_DIR="$ARTIFACT_DIR/app-store-screenshot-source"

/bin/mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"
VISUAL_AUDIT_COMPILED=0

render_screenshot() {
  local file_stem="$1"
  local layout="$2"
  local appearance="$3"
  local png="$TEMP_DIR/$file_stem.png"
  local jpg="$OUTPUT_DIR/$file_stem.jpg"

  ZIZAI_REUSE_VISUAL_AUDIT_BINARY="$VISUAL_AUDIT_COMPILED" \
    /bin/zsh "$PROJECT_DIR/scripts/run_visual_render_audit.sh" \
    "$png" "$layout" "$appearance" standard >/dev/null
  VISUAL_AUDIT_COMPILED=1
  /usr/bin/sips -s format jpeg -s formatOptions 92 "$png" --out "$jpg" >/dev/null
}

render_screenshot "01-groups" storeGroups dark
render_screenshot "02-space" storeSpace dark
render_screenshot "03-all-apps" storeAllApps dark
render_screenshot "04-search" storeSearch dark

SCREENSHOT_SOURCES=(
  "Tests/VisualRenderAudit.swift"
  "Sources/Views.swift"
  "Sources/AllAppsViews.swift"
  "Sources/SearchViews.swift"
  "Sources/CanvasView.swift"
  "Sources/LibraryViews.swift"
  "Sources/DesignSystem.swift"
  "Sources/Compatibility.swift"
  "Sources/Models.swift"
  "Sources/LauncherStateReconciler.swift"
  "Sources/LauncherStore.swift"
  "Sources/LauncherStateHistory.swift"
  "Sources/LauncherStore+Canvas.swift"
  "Sources/LauncherStore+Catalog.swift"
  "Sources/LauncherStore+Groups.swift"
  "Sources/LauncherStore+Library.swift"
  "Sources/ApplicationSearchPolicy.swift"
  "Sources/InteractionGeometry.swift"
  "Sources/SpatialLayoutEngine.swift"
  "Resources/BrandMarkForeground.svg"
  "scripts/run_visual_render_audit.sh"
  "scripts/audit_source_manifest.zsh"
  "scripts/verify_security_capabilities.py"
)
(
  cd "$PROJECT_DIR"
  /usr/bin/shasum -a 256 "${SCREENSHOT_SOURCES[@]}" > \
    "$OUTPUT_DIR/SOURCE_MANIFEST.sha256"
)

/bin/zsh "$PROJECT_DIR/scripts/verify_app_store_assets.sh"
