#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
source "$PROJECT_DIR/scripts/ui_runtime_audit_harness.zsh"

zizai_run_ui_runtime_audit canvas
