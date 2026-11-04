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

UI_MODULE_LIMITS = {
    "Views.swift": 600,
    "PrimaryLayerHosting.swift": 280,
    "TopChromeViews.swift": 160,
    "AppPresentationViews.swift": 340,
    "CanvasView.swift": 280,
    "CanvasGroupViews.swift": 580,
    "CanvasAppViews.swift": 340,
    "LibraryViews.swift": 300,
    "LibraryGroupViews.swift": 380,
    "LibraryAppViews.swift": 220,
    "LibraryTooltipViews.swift": 200,
    "ApplicationManagementViews.swift": 190,
    "ApplicationManagementChrome.swift": 150,
    "ApplicationManagementJiggle.swift": 150,
    "ApplicationManagementLifecycle.swift": 190,
    "ApplicationManagementMotion.swift": 140,
    "ApplicationManagementTopChrome.swift": 140,
}

CAPABILITY_MODULE_LIMITS = {
    "ApplicationManagementPermission.swift": 100,
    "ApplicationFolderAccess.swift": 430,
    "ApplicationRemoval.swift": 360,
    "ApplicationRemovalCompletion.swift": 120,
    "ApplicationRemovalAuthorizationPresenter.swift": 180,
    "ApplicationRemovalAuthorizationScope.swift": 100,
    "ApplicationRemovalCoordinator+Management.swift": 180,
    "ApplicationRemovalServices.swift": 180,
    "ApplicationTrashMover.swift": 140,
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

    for name, limit in UI_MODULE_LIMITS.items():
        content = source_text(name)
        line_count = len(content.splitlines())
        if line_count > limit:
            fail(f"{name} 为 {line_count} 行，超过界面职责边界 {limit} 行")
        if project.count(f"/* {name}") < 2:
            fail(f"{name} 未同时加入 Xcode 文件组与应用 Sources 阶段")
        if f'"$PROJECT_DIR/Sources/{name}"' not in manifest:
            fail(f"{name} 未进入完整界面审计源图")

    management_views = source_text("ApplicationManagementViews.swift")
    if "removalChromeProgress" in management_views or "DispatchQueue.main.async" in management_views:
        fail("删除按钮不得依赖临时挂载后的异步首帧或逐卡片进度状态")
    if "return Alert(" in management_views or "-> Alert" in management_views:
        fail("应用移除弹窗不得恢复会触发旧式 NSAlert 桥接诊断的 Alert 返回值")
    if "func makeAlertActions" not in management_views:
        fail("应用移除弹窗必须由统一的现代 SwiftUI alert actions 构建")

    root_views = source_text("Views.swift")
    for alert_contract in (
        "presenting: removalCoordinator.dialog",
        "dialog.makeAlertActions(coordinator: removalCoordinator)",
    ):
        if alert_contract not in root_views:
            fail(f"应用移除弹窗没有接入统一的现代呈现契约；缺少 {alert_contract}")

    management_chrome = source_text("ApplicationManagementChrome.swift")
    for stable_badge_contract in (
        "private struct ApplicationRemovalBadgeModifier",
        "content.overlayPreferenceValue(ApplicationIconAnchorPreferenceKey.self)",
        "if let anchor, isVisible",
        ".transition(transition)",
        "value: isVisible",
    ):
        if stable_badge_contract not in management_chrome:
            fail(f"删除按钮必须在稳定图标容器内完成插入和移除转场；缺少 {stable_badge_contract}")
    for icon_source_name in ("AppPresentationViews.swift", "SearchViews.swift"):
        icon_source = source_text(icon_source_name)
        if ".applicationIconAnchor()" not in icon_source:
            fail(f"{icon_source_name} 的真实图标没有提供统一删除按钮定位锚点")

    if ".launchpadRemovalChrome(for: app)" not in management_views:
        fail("应用卡片外层没有接入独立可点击的统一删除按钮转场")

    management_tile_sources = "\n".join(
        source_text(name)
        for name in (
            "ApplicationManagementMotion.swift",
            "ApplicationManagementViews.swift",
            "ApplicationManagementJiggle.swift",
        )
    )
    for prohibited_frame_source in ("TimelineView(", ".repeatForever(", ".rotationEffect("):
        if prohibited_frame_source in management_tile_sources:
            fail(
                "应用管理图标重新引入持续逐帧动画源 "
                f"{prohibited_frame_source}，会在真实目录密度下阻塞主线程"
            )

    jiggle_source = source_text("ApplicationManagementJiggle.swift")
    for required_compositor_contract in (
        "CAAnimationGroup()",
        'CAKeyframeAnimation(keyPath: "transform.rotation.z")',
        "animation.repeatCount = .infinity",
    ):
        if required_compositor_contract not in jiggle_source:
            fail(
                "应用管理抖动必须由 Core Animation 合成层持续驱动，"
                f"缺少 {required_compositor_contract}"
            )

    for name, limit in CAPABILITY_MODULE_LIMITS.items():
        content = source_text(name)
        line_count = len(content.splitlines())
        if line_count > limit:
            fail(f"{name} 为 {line_count} 行，超过能力模块职责边界 {limit} 行")
        if project.count(f"/* {name}") < 2:
            fail(f"{name} 未同时加入 Xcode 文件组与应用 Sources 阶段")
        if f'"$PROJECT_DIR/Sources/{name}"' not in manifest:
            fail(f"{name} 未进入完整产品审计源图")

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
    if "audit_public_repo.sh" not in release_gate:
        fail("发布总门槛没有统一编排公开仓库候选审计")
    release_core = RELEASE_CORE.read_text(encoding="utf-8")
    release_runtime = RELEASE_RUNTIME.read_text(encoding="utf-8")
    if "run_ui_tests.sh" not in release_core or "run_architecture_audit.sh" not in release_core:
        fail("core 阶段没有独占构建、XCUITest 编译和产物架构责任")
    for required_runner in (
        "run_interaction_tests.sh",
        "run_accessibility_render_audit.sh",
        "verify_visual_reproducibility.sh",
        "verify_app_store_assets.sh",
        "test_verify_saved_layout.py",
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
        "架构边界验收通过：单一状态聚合根、领域职责模块、界面组成边界与值语义撤销历史，"
        "界面审计复用单一整模块优化产物，且没有旧源码形状验收器或平行事实源。"
    )


if __name__ == "__main__":
    try:
        main()
    except OSError as error:
        fail(str(error))
