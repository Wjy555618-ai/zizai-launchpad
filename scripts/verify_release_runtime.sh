#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"

/bin/zsh "$PROJECT_DIR/scripts/run_interaction_tests.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_tooltip_layering_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_canvas_interaction_performance_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/run_accessibility_render_audit.sh"
/bin/zsh "$PROJECT_DIR/scripts/verify_visual_reproducibility.sh"
/bin/zsh "$PROJECT_DIR/scripts/verify_app_store_assets.sh"
/usr/bin/python3 "$PROJECT_DIR/scripts/verify_saved_layout.py"
/usr/bin/python3 "$PROJECT_DIR/scripts/verify_product_truth.py"

echo "发布运行时门槛通过：交互、状态、性能、视觉可重复性、布局、商店截图和产品事实均有效。"
