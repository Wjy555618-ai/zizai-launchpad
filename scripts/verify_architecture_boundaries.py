#!/usr/bin/env python3
"""Stable architectural boundary checks.

This script verifies module ownership and dependency direction only. Product
behavior belongs to XCTest/XCUITest and executable audits; visual correctness
belongs to render audits. Keeping those evidence types separate prevents a
source-string check from masquerading as runtime proof.
"""

from __future__ import annotations

import pathlib
import sys


ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
PROJECT = ROOT / "自在启动台.xcodeproj" / "project.pbxproj"
MANIFEST = ROOT / "scripts" / "audit_source_manifest.zsh"
AUDIT_TOOLCHAIN = ROOT / "scripts" / "audit_toolchain.zsh"
UI_RUNTIME_HARNESS = ROOT / "scripts" / "ui_runtime_audit_harness.zsh"
RELEASE_GATE = ROOT / "scripts" / "verify_release.sh"
RELEASE_CORE = ROOT / "scripts" / "verify_release_core.sh"
RELEASE_RUNTIME = ROOT / "scripts" / "verify_release_runtime.sh"
VISUAL_REPRODUCIBILITY = ROOT / "scripts" / "verify_visual_reproducibility.sh"
QUALITY_WORKFLOW = ROOT / ".github" / "workflows" / "quality.yml"

NATIVE_AUDIT_RUNNERS = (
    "run_interaction_tests.sh",
    "run_store_behavior_audit.sh",
    "run_async_work_performance_audit.sh",
    "run_tab_switch_performance_audit.sh",
    "run_scanner_audit.sh",
    "run_login_item_audit.sh",
)

UI_RUNTIME_AUDIT_RUNNERS = (
    "run_canvas_interaction_performance_audit.sh",
    "run_tab_content_performance_audit.sh",
    "run_tooltip_layering_audit.sh",
    "run_visual_render_audit.sh",
)

STORE_MODULE_LIMITS = {
    "LauncherStore.swift": 320,
    "LauncherStore+Catalog.swift": 420,
    "LauncherStore+Library.swift": 450,
    "LauncherStore+Groups.swift": 350,
    "LauncherStore+Canvas.swift": 240,
    "LauncherStateHistory.swift": 120,
}


def fail(message: str) -> None:
    raise SystemExit(f"架构边界验收失败：{message}")


def source_text(name: str) -> str:
    path = SOURCES / name
    if not path.is_file():
        fail(f"缺少领域模块 {name}")
    return path.read_text(encoding="utf-8")


def main() -> None:
    project = PROJECT.read_text(encoding="utf-8")
    manifest = MANIFEST.read_text(encoding="utf-8")
    combined = "\n".join(source_text(name) for name in STORE_MODULE_LIMITS)

    for name, limit in STORE_MODULE_LIMITS.items():
        content = source_text(name)
        line_count = len(content.splitlines())
        if line_count > limit:
            fail(f"{name} 为 {line_count} 行，超过职责边界 {limit} 行")
        if project.count(f"/* {name}") < 2:
            fail(f"{name} 未同时加入 Xcode 文件组与应用 Sources 阶段")
        if f'"$PROJECT_DIR/Sources/{name}"' not in manifest:
            fail(f"{name} 未进入独立审计的共享源码清单")

    for pure_module in (
        "LauncherStateHistory.swift",
        "SpatialLayoutEngine.swift",
        "ApplicationSearchPolicy.swift",
        "LauncherStateReconciler.swift",
    ):
        content = source_text(pure_module)
        if "import AppKit" in content or "import SwiftUI" in content:
            fail(f"纯领域模块 {pure_module} 反向依赖 UI 框架")

    if "undoOperations" in combined or "[() -> Void]" in combined:
        fail("仍存在依赖视图生命周期的闭包式撤销栈")
    if "LauncherStateHistory" not in source_text("LauncherStore.swift"):
        fail("聚合根没有使用值语义状态修订历史")
    if (ROOT / "scripts" / "verify_ux.py").exists():
        fail("旧源码形状验收器 verify_ux.py 仍未清理")
    if (ROOT / ".spec-to-demo").exists():
        fail("失效的平行验收事实源 .spec-to-demo 重新出现")

    toolchain = AUDIT_TOOLCHAIN.read_text(encoding="utf-8")
    if 'ZIZAI_AUDIT_ARCH="${ZIZAI_AUDIT_ARCH:-$ZIZAI_HOST_ARCH}"' not in toolchain:
        fail("独立审计没有默认跟随当前主机架构")
    for runner_name in NATIVE_AUDIT_RUNNERS:
        runner = (ROOT / "scripts" / runner_name).read_text(encoding="utf-8")
        if 'source "$PROJECT_DIR/scripts/audit_toolchain.zsh"' not in runner:
            fail(f"{runner_name} 绕过共享审计工具链")
        if "-target arm64-apple" in runner or "-target x86_64-apple" in runner:
            fail(f"{runner_name} 硬编码了审计产物架构")
        if "zizai_run_audit_binary" not in runner:
            fail(f"{runner_name} 没有通过共享架构执行器启动产物")

    ui_harness = UI_RUNTIME_HARNESS.read_text(encoding="utf-8")
    if 'source "$PROJECT_DIR/scripts/audit_toolchain.zsh"' not in ui_harness:
        fail("界面运行时审计绕过共享架构工具链")
    if '"${ZIZAI_AUDIT_SOURCE_FILES[@]}"' not in ui_harness:
        fail("界面运行时审计没有编译统一产品源图")
    if "-whole-module-optimization" not in ui_harness:
        fail("界面运行时审计没有使用有界的整模块发布编译")
    if 'build_started_at="$(/bin/date +%s)"' not in ui_harness:
        fail("界面运行时审计的发布编译阶段不可观测")
    if "zizai_run_audit_binary" not in ui_harness:
        fail("界面运行时审计没有通过共享架构执行器启动")
    for runner_name in UI_RUNTIME_AUDIT_RUNNERS:
        runner = (ROOT / "scripts" / runner_name).read_text(encoding="utf-8")
        if 'source "$PROJECT_DIR/scripts/ui_runtime_audit_harness.zsh"' not in runner:
            fail(f"{runner_name} 绕过统一界面运行时审计")
        if "ZIZAI_SWIFTC" in runner or "ZIZAI_AUDIT_SOURCE_FILES" in runner:
            fail(f"{runner_name} 重复编译了完整 SwiftUI 产品源图")
        if "zizai_run_ui_runtime_audit" not in runner:
            fail(f"{runner_name} 没有通过统一界面运行时入口执行")
        if "|| exit $?" not in runner:
            fail(f"{runner_name} 没有显式传播统一审计入口的失败状态")

    release_gate = RELEASE_GATE.read_text(encoding="utf-8")
    if "verify_release_core.sh" not in release_gate or "verify_release_runtime.sh" not in release_gate:
        fail("发布总门槛没有统一编排 core/runtime 职责阶段")
    release_core = RELEASE_CORE.read_text(encoding="utf-8")
    release_runtime = RELEASE_RUNTIME.read_text(encoding="utf-8")
    if "run_ui_tests.sh" not in release_core or "run_architecture_audit.sh" not in release_core:
        fail("core 阶段没有独占构建、XCUITest 编译和产物架构责任")
    for required_runner in (
        "run_interaction_tests.sh",
        "run_accessibility_render_audit.sh",
        "verify_visual_reproducibility.sh",
        "verify_app_store_assets.sh",
    ):
        if required_runner not in release_runtime:
            fail(f"runtime 阶段缺少 {required_runner}")
    visual_reproducibility = VISUAL_REPRODUCIBILITY.read_text(encoding="utf-8")
    for required_contract in (
        "run_visual_render_audit.sh",
        "reducedMotion",
        "/usr/bin/cmp",
    ):
        if required_contract not in visual_reproducibility:
            fail(f"视觉可重复性门槛缺少 {required_contract}")
    workflow = QUALITY_WORKFLOW.read_text(encoding="utf-8")
    for xcode in ("26.2", "26.6"):
        for stage, runner in (
            ("core", "macos-26-intel"),
            ("runtime", "macos-26"),
        ):
            matrix_entry = (
                f'- xcode: "{xcode}"\n'
                f"            stage: {stage}\n"
                f"            runner: {runner}"
            )
            if matrix_entry not in workflow:
                fail(
                    "GitHub Actions 缺少"
                    f" {stage} / Xcode {xcode} / {runner} 责任矩阵"
                )
    if "runs-on: ${{ matrix.runner }}" not in workflow:
        fail("GitHub Actions 没有按职责矩阵选择受支持的运行架构")
    if "--hosted-ci-${{ matrix.stage }}" not in workflow:
        fail("GitHub Actions 没有通过统一发布入口执行分阶段门槛")

    print(
        "架构边界验收通过：单一状态聚合根、五个职责模块、值语义撤销历史，"
        "界面审计复用单一整模块优化产物，且没有旧源码形状验收器或平行事实源。"
    )


if __name__ == "__main__":
    try:
        main()
    except OSError as error:
        fail(str(error))
