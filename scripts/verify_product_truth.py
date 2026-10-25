#!/usr/bin/env python3
"""Reject drift between product, privacy, tests, and stable documentation."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "CURRENT_PRODUCT_BASELINE.md"
UI_TESTS = ROOT / "Tests" / "XCUITests" / "LaunchpadUITests.swift"
NATIVE_TESTS = ROOT / "Tests" / "XCTest"
MODELS = ROOT / "Sources" / "Models.swift"
PRIVACY_POLICY = ROOT / "PRIVACY_POLICY_ZH.md"

required_baseline_claims = {
    "唯一规范性事实源": re.compile(r"唯一规范性事实源"),
    "分组不显示设计工具式控制点": re.compile(
        r"分组选中后不得显示设计工具式的四角或四边控制点"
    ),
    "点击搜索区域外会收起搜索": re.compile(
        r"点击搜索区域外[^。\n]{0,24}(?:收起|关闭搜索)"
    ),
}
forbidden_current_claims = (
    "四边和四角提供常驻",
    "常驻显示缩放控制点",
    "常驻八向缩放控制点",
    "八个控制点立即常驻显示",
)

baseline_text = BASELINE.read_text(encoding="utf-8")
missing = [
    description
    for description, pattern in required_baseline_claims.items()
    if pattern.search(baseline_text) is None
]
if missing:
    raise SystemExit("当前产品基线缺少必需约束：" + "；".join(missing))

# The removed local spec-to-demo contract is no longer a second fact source.
# Scan every public root document instead, so no release/readme handoff can
# silently reintroduce a requirement that contradicts the current baseline.
files_to_check = sorted(ROOT.glob("*.md"))

violations: list[str] = []
for path in files_to_check:
    text = path.read_text(encoding="utf-8")
    for claim in forbidden_current_claims:
        if claim in text:
            violations.append(f"{path.relative_to(ROOT)}: {claim}")

if violations:
    raise SystemExit("发现与唯一产品基线冲突的旧要求：\n" + "\n".join(violations))

test_declaration = re.compile(r"^\s*func\s+test[A-Za-z0-9_]*\s*\(", re.MULTILINE)
native_test_count = sum(
    len(test_declaration.findall(path.read_text(encoding="utf-8")))
    for path in NATIVE_TESTS.glob("*.swift")
)
ui_test_count = len(test_declaration.findall(UI_TESTS.read_text(encoding="utf-8")))
if native_test_count == 0 or ui_test_count == 0:
    raise SystemExit("测试事实源为空：必须同时存在原生 XCTest 与 XCUITest")

# Stable documentation describes responsibilities, not volatile counters. Exact
# counts belong to the generated evidence that compares source declarations with
# the current xcresult. This prevents every added test from making prose stale.
documentation_contracts = {
    ROOT / "README.md": ("完整 XCTest 回归套件", "完整独立 XCUITest 套件"),
    ROOT / "README_EN.md": ("deterministic native regression suite", "end-to-end suite"),
    ROOT / "ARCHITECTURE.md": ("测试数量与结果由当前源码和当次 `.xcresult` 自动核对",),
    ROOT / "CHANGELOG.md": ("原生回归扩展至", "独立 `自在启动台-UI` XCUITest 方案"),
}
documentation_drift: list[str] = []
volatile_count_patterns = (
    re.compile(r"\b\d+\s*(?:项|个|条)\s*(?:XCTest|测试|独立\s*XCUITest|端到端路径)"),
    re.compile(r"\b\d+\s+(?:deterministic\s+native\s+regressions|end-to-end\s+paths)"),
)
for path, required_phrases in documentation_contracts.items():
    text = path.read_text(encoding="utf-8")
    for phrase in required_phrases:
        if phrase not in text:
            documentation_drift.append(f"{path.relative_to(ROOT)} 缺少稳定验证说明：{phrase}")
    for pattern in volatile_count_patterns:
        if pattern.search(text):
            documentation_drift.append(
                f"{path.relative_to(ROOT)} 手写了会漂移的测试数量；精确数量只能来自质量证据"
            )
            break
if documentation_drift:
    raise SystemExit("发布文档与可执行验证契约发生漂移：\n" + "\n".join(documentation_drift))

# Release instructions may describe what the gate verifies, but must not retain
# a manually written pass from an older source revision or machine. The only
# current pass is the generated, source-digest-bound quality evidence.
stale_evidence_phrases = {
    ROOT / "APP_STORE_REVIEW.md": (
        "已通过本机核心功能",
        "真实安装版拖动回归已通过",
        "最终安装版输入 `fig`",
    ),
    ROOT / "APP_STORE_HANDOFF.md": (
        "Release 编译和未签名 Archive 结构验证已通过",
        "已生成并通过 Xcode",
    ),
}
stale_evidence = [
    f"{path.relative_to(ROOT)} 手写旧通过结论：{phrase}"
    for path, phrases in stale_evidence_phrases.items()
    for phrase in phrases
    if phrase in path.read_text(encoding="utf-8")
]
if stale_evidence:
    raise SystemExit("稳定发布文档混入未绑定当前源码的通过结论：\n" + "\n".join(stale_evidence))

# PersistedState is the code-level inventory for locally stored product data.
# Any field addition/removal must fail this gate until the privacy review and
# disclosure are consciously updated together.
model_text = MODELS.read_text(encoding="utf-8")
persisted_match = re.search(
    r"struct PersistedState:.*?\{(?P<body>.*?)\n\s*private enum CodingKeys",
    model_text,
    re.DOTALL,
)
if persisted_match is None:
    raise SystemExit("无法从 Models.swift 解析 PersistedState 隐私数据清单")
persisted_fields = set(
    re.findall(r"^\s*var\s+([A-Za-z_][A-Za-z0-9_]*)\b", persisted_match.group("body"), re.MULTILINE)
)
reviewed_persisted_fields = {
    "schemaVersion",
    "positions",
    "aliases",
    "hiddenAppIDs",
    "appGroupIDs",
    "groupAppOrder",
    "userGroups",
    "deletedStarterGroupIDs",
    "layoutMode",
    "canvasOffsetX",
    "canvasOffsetY",
    "canvasScale",
    "hasSeenWelcome",
}
if persisted_fields != reviewed_persisted_fields:
    added = sorted(persisted_fields - reviewed_persisted_fields)
    removed = sorted(reviewed_persisted_fields - persisted_fields)
    raise SystemExit(
        "PersistedState 已变化，必须同步完成隐私审查："
        f"新增={added or '无'}；移除={removed or '无'}"
    )

privacy_text = PRIVACY_POLICY.read_text(encoding="utf-8")
privacy_surface_text = (ROOT / "Sources" / "Sheets.swift").read_text(encoding="utf-8")
required_privacy_disclosures = (
    "分组及顺序",
    "中文别名",
    "显示或隐藏状态",
    "应用与分组的位置和尺寸",
    "当前视图及画布位置与缩放",
    "欢迎页完成状态",
    "App Sandbox 容器",
)
missing_privacy = [
    phrase
    for phrase in required_privacy_disclosures
    if phrase not in privacy_text or phrase not in privacy_surface_text
]
if missing_privacy:
    raise SystemExit("隐私政策或应用内隐私页未完整披露本地持久化类别：" + "；".join(missing_privacy))
if "常用状态" in privacy_text or "favorites" in model_text:
    raise SystemExit("已移除的常用功能仍残留在隐私说明或持久化模型中")

print(
    "产品事实源通过：当前基线唯一，公开文档无冲突要求，"
    f"源码声明 {native_test_count} 项 XCTest / {ui_test_count} 项 XCUITest，"
    "稳定文档不复制动态数量，隐私披露与 PersistedState 一致。"
)
