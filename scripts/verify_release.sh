#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
VALIDATION_PROFILE="interactive"
VALIDATION_STAGE="all"

case "${1:-}" in
  "") ;;
  --hosted-ci)
    VALIDATION_PROFILE="hosted-ci"
    ;;
  --hosted-ci-core)
    VALIDATION_PROFILE="hosted-ci"
    VALIDATION_STAGE="core"
    ;;
  --hosted-ci-runtime)
    VALIDATION_PROFILE="hosted-ci"
    VALIDATION_STAGE="runtime"
    ;;
  *)
    echo "用法：verify_release.sh [--hosted-ci|--hosted-ci-core|--hosted-ci-runtime]" >&2
    exit 2
    ;;
esac
(( $# <= 1 )) || {
  echo "用法：verify_release.sh [--hosted-ci|--hosted-ci-core|--hosted-ci-runtime]" >&2
  exit 2
}

# A new complete local attempt must never leave an older all-green evidence
# file behind. Hosted stages never create or promote interactive evidence.
if [[ "$VALIDATION_PROFILE" == "interactive" ]]; then
  /bin/rm -f "$ARTIFACT_DIR/quality-evidence.json"
fi

if [[ "$VALIDATION_STAGE" == "all" || "$VALIDATION_STAGE" == "core" ]]; then
  /bin/zsh "$PROJECT_DIR/scripts/verify_release_core.sh" "$VALIDATION_PROFILE"
fi
if [[ "$VALIDATION_STAGE" == "all" || "$VALIDATION_STAGE" == "runtime" ]]; then
  /bin/zsh "$PROJECT_DIR/scripts/verify_release_runtime.sh"
fi

if [[ "$VALIDATION_PROFILE" == "interactive" ]]; then
  /usr/bin/python3 "$PROJECT_DIR/scripts/generate_quality_evidence.py" "$ARTIFACT_DIR"
  echo "完整交互式工程门槛通过：核心构建与真实 XCUITest、统一界面运行时审计、视觉和发布资产均有效。"
elif [[ "$VALIDATION_STAGE" == "all" ]]; then
  echo "GitHub 托管工程门槛通过：核心与运行时两个职责阶段均有效。"
  echo "边界：托管配置没有生成真实 XCUITest 通过结论；发布仍要求受信任交互式 macOS 会话执行默认门槛。"
else
  echo "GitHub 托管 $VALIDATION_STAGE 阶段通过；完整远程结论要求同一提交的 core 与 runtime 矩阵全部通过。"
fi
echo "注意：这不代替真实用户研究、专项硬件矩阵或 Apple 人工审核。"
