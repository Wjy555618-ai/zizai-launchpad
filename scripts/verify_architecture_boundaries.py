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

AUDIT_RUNNERS = (
    "run_interaction_tests.sh",
    "run_store_behavior_audit.sh",
    "run_async_work_performance_audit.sh",
    "run_canvas_interaction_performance_audit.sh",
    "run_tab_content_performance_audit.sh",
    "run_tab_switch_performance_audit.sh",
    "run_tooltip_layering_audit.sh",
    "run_visual_render_audit.sh",
    "run_scanner_audit.sh",
    "run_login_item_audit.sh",
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
    for runner_name in AUDIT_RUNNERS:
        runner = (ROOT / "scripts" / runner_name).read_text(encoding="utf-8")
        if 'source "$PROJECT_DIR/scripts/audit_toolchain.zsh"' not in runner:
            fail(f"{runner_name} 绕过共享审计工具链")
        if "-target arm64-apple" in runner or "-target x86_64-apple" in runner:
            fail(f"{runner_name} 硬编码了审计产物架构")
        if "zizai_run_audit_binary" not in runner:
            fail(f"{runner_name} 没有通过共享架构执行器启动产物")

    print(
        "架构边界验收通过：单一状态聚合根、五个职责模块、值语义撤销历史，"
        "且没有旧源码形状验收器或平行事实源。"
    )


if __name__ == "__main__":
    try:
        main()
    except OSError as error:
        fail(str(error))
