#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
RESULT_BUNDLE="${1:-$PROJECT_DIR/.artifacts.noindex/unit-tests.xcresult}"

[[ -d "$RESULT_BUNDLE" ]] || {
  echo "覆盖率门槛缺少 xcresult：$RESULT_BUNDLE" >&2
  exit 1
}

REPORT="$(/usr/bin/xcrun xccov view --report "$RESULT_BUNDLE")"

coverage_for() {
  local needle="$1"
  /usr/bin/printf '%s\n' "$REPORT" \
    | /usr/bin/awk -v needle="$needle" '
        index($0, needle) {
          if (match($0, /[0-9]+\.[0-9]+%/)) {
            value = substr($0, RSTART, RLENGTH)
            sub(/%$/, "", value)
            print value
            exit
          }
        }
      '
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

require_at_least "应用目标" "自在启动台.app" 70
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
require_at_least "画布交互" "Sources/CanvasView.swift" 60
require_at_least "交互几何" "Sources/InteractionGeometry.swift" 90
require_at_least "空间布局引擎" "Sources/SpatialLayoutEngine.swift" 80

echo "覆盖率硬门槛通过；纯界面声明文件不以行覆盖率替代端到端与视觉验收。"
