#!/usr/bin/env python3
"""Write machine-readable evidence only after every local quality gate passed."""

from __future__ import annotations

import datetime as dt
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
arguments = sys.argv[1:]
verify_current = "--verify-current" in arguments
arguments = [argument for argument in arguments if argument != "--verify-current"]
if len(arguments) > 1:
    raise SystemExit("用法：generate_quality_evidence.py [artifact-directory] [--verify-current]")
ARTIFACTS = Path(arguments[0]).resolve() if arguments else ROOT / ".artifacts.noindex"
UNIT_RESULT = ARTIFACTS / "unit-tests.xcresult"
UI_RESULT = ARTIFACTS / "ui-tests.xcresult"
BUILT_INFO = ARTIFACTS / "自在启动台.app" / "Contents" / "Info.plist"
STATIC_ANALYSIS_LOG = ARTIFACTS / "static-analysis.log"
TEST_DECLARATION = re.compile(r"^\s*func\s+test[A-Za-z0-9_]*\s*\(", re.MULTILINE)


def command(*arguments: str) -> str:
    return subprocess.check_output(arguments, text=True).strip()


def result_summary(path: Path) -> dict[str, object]:
    if not path.is_dir():
        raise SystemExit(f"缺少测试证据：{path}")
    raw = command(
        "/usr/bin/xcrun",
        "xcresulttool",
        "get",
        "test-results",
        "summary",
        "--path",
        str(path),
        "--format",
        "json",
    )
    summary = json.loads(raw)
    if (
        summary.get("result") != "Passed"
        or int(summary.get("failedTests", 0)) != 0
        or int(summary.get("skippedTests", 0)) != 0
    ):
        raise SystemExit(f"测试证据不是全绿：{path}")
    warnings = summary.get("runtimeWarnings", [])
    if warnings:
        raise SystemExit(f"测试证据含有运行时警告：{path}")
    return {
        "result": summary["result"],
        "passed": int(summary.get("passedTests", 0)),
        "failed": int(summary.get("failedTests", 0)),
        "skipped": int(summary.get("skippedTests", 0)),
        "environment": summary.get("environmentDescription", ""),
        "runtime_warnings": len(warnings),
    }


def evidence_files() -> list[Path]:
    paths: set[Path] = set()
    for pattern in (
        "Sources/**/*.swift",
        "Tests/**/*.swift",
        "Tests/Plans/*.xctestplan",
        "scripts/*",
        "自在启动台.xcodeproj/project.pbxproj",
        "自在启动台.xcodeproj/xcshareddata/xcschemes/*.xcscheme",
        "Resources/**/*",
        "AppStore/Screenshots/zh-Hans/*",
        "CURRENT_PRODUCT_BASELINE.md",
    ):
        paths.update(path for path in ROOT.glob(pattern) if path.is_file())
    return sorted(paths, key=lambda path: path.relative_to(ROOT).as_posix())


def source_digest(paths: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in paths:
        relative = path.relative_to(ROOT).as_posix().encode()
        digest.update(len(relative).to_bytes(4, "big"))
        digest.update(relative)
        content = path.read_bytes()
        digest.update(len(content).to_bytes(8, "big"))
        digest.update(content)
    return digest.hexdigest()


unit = result_summary(UNIT_RESULT)
ui = result_summary(UI_RESULT)
expected_unit_tests = sum(
    len(TEST_DECLARATION.findall(path.read_text(encoding="utf-8")))
    for path in (ROOT / "Tests" / "XCTest").glob("*.swift")
)
expected_ui_tests = len(
    TEST_DECLARATION.findall(
        (ROOT / "Tests" / "XCUITests" / "LaunchpadUITests.swift").read_text(encoding="utf-8")
    )
)
for label, result, expected in (
    ("XCTest", unit, expected_unit_tests),
    ("XCUITest", ui, expected_ui_tests),
):
    if expected == 0 or int(result["passed"]) != expected:
        raise SystemExit(
            f"{label} 执行数量与当前源码声明不一致："
            f"声明 {expected}，通过 {result['passed']}"
        )
    result["declared_tests"] = expected

if not BUILT_INFO.is_file():
    raise SystemExit(f"缺少已构建产品信息：{BUILT_INFO}")
if not STATIC_ANALYSIS_LOG.is_file() or STATIC_ANALYSIS_LOG.stat().st_size == 0:
    raise SystemExit(f"缺少当前门槛的 Xcode 静态分析日志：{STATIC_ANALYSIS_LOG}")

with BUILT_INFO.open("rb") as handle:
    info = plistlib.load(handle)

product_identity = {
    "name": info.get("CFBundleDisplayName", ""),
    "version": info.get("CFBundleShortVersionString", ""),
    "build": info.get("CFBundleVersion", ""),
}
if any(not isinstance(value, str) or not value or "$(" in value for value in product_identity.values()):
    raise SystemExit(f"构建产物身份未完整展开：{product_identity}")

files = evidence_files()
payload = {
    "schema": 1,
    "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    "product": product_identity,
    "source": {
        "sha256": source_digest(files),
        "file_count": len(files),
        "contract": "CURRENT_PRODUCT_BASELINE.md",
    },
    "environment": {
        "macos": command("/usr/bin/sw_vers", "-productVersion"),
        "architecture": command("/usr/bin/uname", "-m"),
        "xcode": command("/usr/bin/xcodebuild", "-version").replace("\n", " | "),
    },
    "gates": {
        "release_gate": "passed",
        "xcode_static_analysis": "passed",
        "unit_tests": unit,
        "ui_tests": ui,
        "visual_and_accessibility_render": "passed",
        "app_store_assets": "passed",
        "sandbox_and_privacy": "passed",
        "interaction_and_performance_audits": "passed",
        "saved_layout_validator_contract": "passed",
        "public_repository_candidate": "passed",
        "product_truth": "passed",
    },
    "claim_boundary": {
        "apple_distribution_identity": "not_evaluated",
        "app_store_connect_validation": "not_evaluated",
        "hardware_matrix": [
            "macOS 13 physical Mac",
            "Intel Mac",
            "VoiceOver manual session",
            "multiple displays",
            "sleep-wake and long-running session",
        ],
        "installed_user_layout": "not_evaluated_without_an_explicit_state_file",
    },
}

ARTIFACTS.mkdir(parents=True, exist_ok=True)
output = ARTIFACTS / "quality-evidence.json"
if verify_current:
    if not output.is_file():
        raise SystemExit(f"缺少发布门槛生成的质量证据：{output}")
    existing = json.loads(output.read_text(encoding="utf-8"))
    compared_sections = ("schema", "product", "source", "environment", "gates", "claim_boundary")
    mismatches = [section for section in compared_sections if existing.get(section) != payload.get(section)]
    if mismatches:
        raise SystemExit(
            "质量证据与当前源码、产物或测试结果不一致：" + "、".join(mismatches)
        )
    print(f"质量证据仍对应当前源码、产物和测试结果：{output}")
else:
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"已生成当前源码质量证据：{output}")
