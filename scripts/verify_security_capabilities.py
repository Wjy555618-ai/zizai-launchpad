#!/usr/bin/env python3
"""Validate the app's declared sandbox capabilities against its implementation.

This is the single source of truth for security-sensitive entitlements.  A
source-level feature cannot be declared safe merely because its plist parses:
the capability used by the code, the checked-in entitlement and (when
provided) the signed product must agree.
"""

from __future__ import annotations

import argparse
import plistlib
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
ENTITLEMENTS_PATH = ROOT / "Resources" / "ZizaiLaunchpad.entitlements"
FOLDER_ACCESS_PATH = ROOT / "Sources" / "ApplicationFolderAccess.swift"

APP_SANDBOX = "com.apple.security.app-sandbox"
USER_SELECTED_READ_ONLY = "com.apple.security.files.user-selected.read-only"
APP_SCOPED_BOOKMARKS = "com.apple.security.files.bookmarks.app-scope"
TEMPORARY_EXCEPTION_PREFIX = "com.apple.security.temporary-exception"


def fail(message: str) -> None:
    raise SystemExit(f"安全能力契约失败：{message}")


def read_plist(path: Path) -> dict[str, object]:
    try:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"无法读取 {path.relative_to(ROOT)}：{error}")
    if not isinstance(value, dict):
        fail(f"{path.relative_to(ROOT)} 不是 entitlement 字典")
    return value


def validate_entitlements(entitlements: dict[str, object], label: str) -> None:
    required = {
        APP_SANDBOX: "App Sandbox",
        USER_SELECTED_READ_ONLY: "用户选择只读文件夹",
        APP_SCOPED_BOOKMARKS: "持久 app-scoped security bookmark",
    }
    for key, capability in required.items():
        if entitlements.get(key) is not True:
            fail(f"{label} 缺少 {capability} entitlement：{key}")

    forbidden = sorted(
        key for key in entitlements if key.startswith(TEMPORARY_EXCEPTION_PREFIX)
    )
    if forbidden:
        fail(f"{label} 使用了 App Sandbox 临时例外：{', '.join(forbidden)}")


def signed_entitlements(app: Path) -> dict[str, object]:
    if not app.is_dir():
        fail(f"待验证 App 不存在：{app}")
    result = subprocess.run(
        ["/usr/bin/codesign", "-d", "--entitlements", ":-", str(app)],
        check=False,
        capture_output=True,
    )
    payload = result.stdout or result.stderr
    start = payload.find(b"<?xml")
    if result.returncode != 0 or start < 0:
        fail(f"无法读取构建产物签名权限：{app}")
    try:
        value = plistlib.loads(payload[start:])
    except plistlib.InvalidFileException as error:
        fail(f"构建产物 entitlement 不是有效 plist：{error}")
    if not isinstance(value, dict):
        fail("构建产物 entitlement 不是字典")
    return value


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, help="同时验证已签名或临时签名的 .app")
    args = parser.parse_args()

    source = FOLDER_ACCESS_PATH.read_text(encoding="utf-8")
    persistent_bookmark_markers = (
        ".withSecurityScope",
        ".securityScopeAllowOnlyReadAccess",
        "startAccessingSecurityScopedResource()",
        "stopAccessingSecurityScopedResource()",
    )
    missing_markers = [marker for marker in persistent_bookmark_markers if marker not in source]
    if missing_markers:
        fail("文件夹授权实现缺少完整的持久只读安全书签生命周期：" + ", ".join(missing_markers))

    declared = read_plist(ENTITLEMENTS_PATH)
    validate_entitlements(declared, "源码配置")

    if args.app:
        built = signed_entitlements(args.app.resolve())
        validate_entitlements(built, "构建产物")
        for key in (APP_SANDBOX, USER_SELECTED_READ_ONLY, APP_SCOPED_BOOKMARKS):
            if built.get(key) != declared.get(key):
                fail(f"源码配置与构建产物不一致：{key}")

    print("安全能力契约通过：沙盒、用户选择只读访问与持久 app-scoped bookmark 一致。")


if __name__ == "__main__":
    main()
