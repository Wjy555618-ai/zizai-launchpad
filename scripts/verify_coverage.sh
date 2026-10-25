#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
RESULT_BUNDLE="${1:-$PROJECT_DIR/.artifacts.noindex/unit-tests.xcresult}"
COVERAGE_SCOPE="${2:-unit}"

[[ -d "$RESULT_BUNDLE" ]] || {
  echo "覆盖率门槛缺少 xcresult：$RESULT_BUNDLE" >&2
  exit 1
}

REPORT="$(/usr/bin/xcrun xccov view --report "$RESULT_BUNDLE")"

coverage_for() {
  local needle="$1"
  /usr/bin/awk -v needle="$needle" '
        index($0, needle) {
          if (match($0, /[0-9]+\.[0-9]+%/)) {
            value = substr($0, RSTART, RLENGTH)
            sub(/%$/, "", value)
            print value
            exit
          }
        }
      ' <<<"$REPORT"
}

require_at_least() {
  local label="$1"
  local needle="$2"
  local threshold="$3"
  local actual="$(coverage_for "$needle")"

  [[ -n "$actual" ]] || {
    echo "覆盖率门槛无法定位：$label ($needle)" >&2
    exit 1
  }

  if ! /usr/bin/awk -v actual="$actual" -v threshold="$threshold" \
    'BEGIN { exit !(actual + 0 >= threshold + 0) }'; then
    echo "覆盖率不足：$label 为 ${actual}%，要求至少 ${threshold}%" >&2
    exit 1
  fi

  echo "覆盖率通过  $label ${actual}%（门槛 ${threshold}%）"
}

coverage_counts_for() {
  local needle="$1"
  /usr/bin/awk -v needle="$needle" '
        index($0, needle) {
          value = $0
          sub(/^.*\(/, "", value)
          sub(/\).*$/, "", value)
          if (value ~ /^[0-9]+\/[0-9]+$/) {
            print value
            exit
          }
        }
      ' <<<"$REPORT"
}

report_coverage() {
  local label="$1"
  local needle="$2"
  local actual="$(coverage_for "$needle")"

  [[ -n "$actual" ]] || {
    echo "覆盖率报告无法定位：$label ($needle)" >&2
    exit 1
  }
  echo "覆盖率报告  $label ${actual}%"
}

require_weighted_at_least() {
  local label="$1"
  local threshold="$2"
  shift 2
  local covered=0
  local executable=0
  local counts

  for needle in "$@"; do
    counts="$(coverage_counts_for "$needle")"
    [[ -n "$counts" ]] || {
      echo "加权覆盖率门槛无法定位：$label ($needle)" >&2
      exit 1
    }
    covered=$((covered + ${counts%%/*}))
    executable=$((executable + ${counts##*/}))
  done

  local actual="$(/usr/bin/awk -v covered="$covered" -v executable="$executable" \
    'BEGIN { printf "%.2f", covered * 100 / executable }')"
  if ! /usr/bin/awk -v actual="$actual" -v threshold="$threshold" \
    'BEGIN { exit !(actual + 0 >= threshold + 0) }'; then
    echo "覆盖率不足：$label 为 ${actual}%（${covered}/${executable}），要求至少 ${threshold}%" >&2
    exit 1
  fi
  echo "覆盖率通过  $label ${actual}%（${covered}/${executable}，门槛 ${threshold}%）"
}

if [[ "$COVERAGE_SCOPE" == "ui" ]]; then
  require_at_least "真实 UI 应用目标" "自在启动台.app" 70
  require_at_least "空间画布真实交互" "Sources/CanvasView.swift" 70
  require_at_least "分组视图真实交互" "Sources/LibraryViews.swift" 85
  require_at_least "搜索视图真实交互" "Sources/SearchViews.swift" 85
  require_at_least "主窗口真实交互" "Sources/Views.swift" 75
  require_at_least "气泡窗口锚点适配" "Sources/TooltipWindowAnchor.swift" 90
  require_at_least "产品弹窗真实交互" "Sources/Sheets.swift" 50
  require_at_least "全部应用真实交互" "Sources/AllAppsViews.swift" 55
  echo "XCUITest 覆盖率硬门槛通过：应用整体与关键 SwiftUI/AppKit 交互由真实用户路径执行。"
  exit 0
fi

[[ "$COVERAGE_SCOPE" == "unit" ]] || {
  echo "未知覆盖率范围：$COVERAGE_SCOPE（仅支持 unit 或 ui）" >&2
  exit 1
}

# The target-wide number is reported for transparency, but SwiftUI body
# expansion is not treated as a business-logic quality signal. Primary views
# and sheets are gated by executable visual audits and real XCUITest paths.
report_coverage "应用目标整体行覆盖率（含声明式 UI）" "自在启动台.app"
require_weighted_at_least "核心行为加权覆盖率" 85 \
  "Sources/LauncherStore.swift" \
  "Sources/LauncherStore+Catalog.swift" \
  "Sources/LauncherStore+Library.swift" \
  "Sources/LauncherStore+Groups.swift" \
  "Sources/LauncherStore+Canvas.swift" \
  "Sources/LauncherStateHistory.swift" \
  "Sources/LauncherStateReconciler.swift" \
  "Sources/ApplicationCatalogLogic.swift" \
  "Sources/ApplicationSearchPolicy.swift" \
  "Sources/LoginItemSettings.swift" \
  "Sources/TooltipPresentation.swift" \
  "Sources/InteractionGeometry.swift" \
  "Sources/SpatialLayoutEngine.swift" \
  "Sources/StatePersistence.swift" \
  "Sources/ApplicationFolderAccess.swift" \
  "Sources/LaunchPresentation.swift"
require_at_least "状态聚合根" "Sources/LauncherStore.swift" 80
require_at_least "目录与查询命令" "Sources/LauncherStore+Catalog.swift" 80
require_at_least "应用放置事务" "Sources/LauncherStore+Library.swift" 85
require_at_least "分组生命周期事务" "Sources/LauncherStore+Groups.swift" 85
require_at_least "画布导航命令" "Sources/LauncherStore+Canvas.swift" 75
require_at_least "值语义撤销历史" "Sources/LauncherStateHistory.swift" 95
require_at_least "扫描状态对账" "Sources/LauncherStateReconciler.swift" 80
require_at_least "应用目录与搜索逻辑" "Sources/ApplicationCatalogLogic.swift" 85
require_at_least "应用搜索匹配策略" "Sources/ApplicationSearchPolicy.swift" 90
require_at_least "登录项核心" "Sources/LoginItemSettings.swift" 80
require_at_least "气泡生命周期" "Sources/TooltipPresentation.swift" 75
require_at_least "异步持久化写入" "Sources/StatePersistence.swift" 75
require_at_least "应用目录持久授权" "Sources/ApplicationFolderAccess.swift" 70
require_at_least "交互几何" "Sources/InteractionGeometry.swift" 90
require_at_least "空间布局引擎" "Sources/SpatialLayoutEngine.swift" 80

echo "覆盖率硬门槛通过；声明式界面不靠 body 展开抬高数字，真实 XCUITest 与深浅色视觉渲染由各自独立门槛验收。"
