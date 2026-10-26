#!/bin/zsh

# Shared source manifest for audit executables that compile the real SwiftUI
# product outside Xcode. Keeping this list in one place prevents an audit from
# silently compiling a different product graph than its sibling audits.
if [[ -z "${PROJECT_DIR:-}" ]]; then
  print -u2 "audit_source_manifest.zsh requires PROJECT_DIR"
  return 1
fi

typeset -ga ZIZAI_AUDIT_SOURCE_FILES=(
  "$PROJECT_DIR/Sources/AllAppsViews.swift"
  "$PROJECT_DIR/Sources/AppPresentationViews.swift"
  "$PROJECT_DIR/Sources/AppScanner.swift"
  "$PROJECT_DIR/Sources/ApplicationFolderAccess.swift"
  "$PROJECT_DIR/Sources/CanvasAppViews.swift"
  "$PROJECT_DIR/Sources/CanvasGroupViews.swift"
  "$PROJECT_DIR/Sources/Compatibility.swift"
  "$PROJECT_DIR/Sources/DesignSystem.swift"
  "$PROJECT_DIR/Sources/CanvasView.swift"
  "$PROJECT_DIR/Sources/InputCapture.swift"
  "$PROJECT_DIR/Sources/InteractionGeometry.swift"
  "$PROJECT_DIR/Sources/SpatialLayoutEngine.swift"
  "$PROJECT_DIR/Sources/StatePersistence.swift"
  "$PROJECT_DIR/Sources/ApplicationCatalogLogic.swift"
  "$PROJECT_DIR/Sources/ApplicationSearchPolicy.swift"
  "$PROJECT_DIR/Sources/LauncherStateReconciler.swift"
  "$PROJECT_DIR/Sources/LauncherStateHistory.swift"
  "$PROJECT_DIR/Sources/LauncherStore+Canvas.swift"
  "$PROJECT_DIR/Sources/LauncherStore+Catalog.swift"
  "$PROJECT_DIR/Sources/LauncherStore+Groups.swift"
  "$PROJECT_DIR/Sources/LauncherStore+Library.swift"
  "$PROJECT_DIR/Sources/LauncherStore.swift"
  "$PROJECT_DIR/Sources/LibraryAppViews.swift"
  "$PROJECT_DIR/Sources/LibraryGroupViews.swift"
  "$PROJECT_DIR/Sources/LibraryTooltipViews.swift"
  "$PROJECT_DIR/Sources/LibraryViews.swift"
  "$PROJECT_DIR/Sources/Models.swift"
  "$PROJECT_DIR/Sources/PrimaryLayerHosting.swift"
  "$PROJECT_DIR/Sources/LoginItemSettings.swift"
  "$PROJECT_DIR/Sources/SearchViews.swift"
  "$PROJECT_DIR/Sources/Sheets.swift"
  "$PROJECT_DIR/Sources/TooltipPresentation.swift"
  "$PROJECT_DIR/Sources/TopChromeViews.swift"
  "$PROJECT_DIR/Sources/TooltipWindowAnchor.swift"
  "$PROJECT_DIR/Sources/UITestSupport.swift"
  "$PROJECT_DIR/Sources/Views.swift"
)

# Headless audits exercise the real store without compiling view-only files.
# Keep this graph beside the complete UI graph so every store audit consumes
# the same state, search and spatial implementation after architectural splits.
typeset -ga ZIZAI_STORE_AUDIT_SOURCE_FILES=(
  "$PROJECT_DIR/Sources/Models.swift"
  "$PROJECT_DIR/Sources/InteractionGeometry.swift"
  "$PROJECT_DIR/Sources/SpatialLayoutEngine.swift"
  "$PROJECT_DIR/Sources/AppScanner.swift"
  "$PROJECT_DIR/Sources/StatePersistence.swift"
  "$PROJECT_DIR/Sources/ApplicationCatalogLogic.swift"
  "$PROJECT_DIR/Sources/ApplicationSearchPolicy.swift"
  "$PROJECT_DIR/Sources/LauncherStateReconciler.swift"
  "$PROJECT_DIR/Sources/LauncherStateHistory.swift"
  "$PROJECT_DIR/Sources/LauncherStore+Canvas.swift"
  "$PROJECT_DIR/Sources/LauncherStore+Catalog.swift"
  "$PROJECT_DIR/Sources/LauncherStore+Groups.swift"
  "$PROJECT_DIR/Sources/LauncherStore+Library.swift"
  "$PROJECT_DIR/Sources/LauncherStore.swift"
)
