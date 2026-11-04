#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
VALIDATION_PROFILE="${1:-interactive}"

case "$VALIDATION_PROFILE" in
  interactive|hosted-ci) ;;
  *)
    echo "用法：verify_release_runtime.sh [interactive|hosted-ci]" >&2
    exit 2
    ;;
esac

/bin/zsh "$PROJECT_DIR/scripts/run_interaction_tests.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_tooltip_layering_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_canvas_interaction_performance_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_accessibility_render_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/verify_visual_reproducibility.sh"
if [[ "$VALIDATION_PROFILE" == "interactive" ]]; then
  /bin/zsh "$PROJECT_DIR/scripts/verify_app_store_assets.sh"
else
  echo "托管运行时门槛跳过已明确暂缓的 App Store 截图；默认交互式门槛和 audit_app_store.sh 仍会严格校验。"
fi
/usr/bin/python3 "$PROJECT_DIR/scripts/test_verify_saved_layout.py"
/usr/bin/python3 "$PROJECT_DIR/scripts/verify_product_truth.py"

if [[ "$VALIDATION_PROFILE" == "interactive" ]]; then
  echo "发布运行时门槛通过：交互、状态、性能、视觉可重复性、布局验证器、商店截图和产品事实均有效。"
else
  echo "托管发布运行时门槛通过：交互、状态、性能、视觉可重复性、布局验证器和产品事实均有效；商店截图保持独立阻断。"
fi
