#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
OUTPUT_DIR="$ARTIFACT_DIR/accessibility-render-audit"
/bin/mkdir -p "$OUTPUT_DIR"

render_case() {
  local name="$1"
  local layout="$2"
  local appearance="$3"
  local effects="$4"
  local output="$OUTPUT_DIR/$name.png"

  /bin/zsh "$PROJECT_DIR/scripts/run_visual_render_audit.sh" \
    "$output" "$layout" "$appearance" "$effects" >/dev/null
  [[ -s "$output" ]] || {
    echo "辅助功能视觉验收失败：$name 没有生成快照" >&2
    exit 1
  }
}

render_case "groups-light-standard" groups light standard
render_case "groups-dark-reduced-effects" groups dark reduced
render_case "groups-dark-to-light-transition" appearanceTransitionGroups light standard
render_case "space-light-standard" space light standard
render_case "space-dark-reduced-effects" space dark reduced
render_case "space-dark-to-light-transition" appearanceTransitionSpace light standard
render_case "all-apps-light-reduced-effects" allApps light reduced
render_case "all-apps-dark-standard" allApps dark standard
render_case "all-apps-dark-to-light-transition" appearanceTransitionAllApps light standard
render_case "compact-window-light-standard" compactWindow light standard
render_case "compact-window-dark-reduced-effects" compactWindow dark reduced
render_case "search-light-standard" search light standard
render_case "search-dark-reduced-effects" search dark reduced
render_case "welcome-sheet-light-standard" sheetWelcome light standard
render_case "welcome-sheet-dark-reduced-effects" sheetWelcome dark reduced
render_case "help-sheet-light-standard" sheetHelp light standard
render_case "help-sheet-dark-reduced-effects" sheetHelp dark reduced
render_case "group-editor-light-standard" sheetGroupEditor light standard
render_case "group-editor-dark-reduced-effects" sheetGroupEditor dark reduced
render_case "alias-editor-light-standard" sheetAliasEditor light standard
render_case "alias-editor-dark-reduced-effects" sheetAliasEditor dark reduced

echo "辅助功能视觉门槛通过：分组、空间、全部应用、搜索、紧凑窗口以及欢迎、帮助、分组编辑、别名编辑页的深浅色均已渲染；三个主页已通过同一窗口的深色到浅色切换；应用名称、顶部控件、底部导航、缩放区与产品弹窗通过像素对比度和语义前景检测。"
