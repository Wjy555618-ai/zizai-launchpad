#!/usr/bin/env python3
"""Reject compiler warnings and actionable SwiftUI runtime diagnostics."""

from pathlib import Path
import re
import sys


if len(sys.argv) != 3:
    raise SystemExit("用法：verify_test_log.py <XCTest|XCUITest> <日志路径>")

label = sys.argv[1]
path = Path(sys.argv[2])
if not path.is_file():
    raise SystemExit(f"{label} 日志不存在：{path}")

text = path.read_text(encoding="utf-8", errors="replace")
diagnostics = {
    "编译或链接警告": re.compile(r"(^|:\s)warning:", re.MULTILINE),
    "SwiftUI Preference 同帧重复更新": re.compile(
        r"Bound preference .* tried to update multiple times per frame\."
    ),
    "SwiftUI 视图更新期间发布状态": re.compile(
        r"Publishing changes from within view updates is not allowed"
    ),
    "SwiftUI 视图更新期间修改状态": re.compile(r"Modifying state during view update"),
}

failures: list[str] = []
for description, pattern in diagnostics.items():
    match = pattern.search(text)
    if match is None:
        continue
    line_start = text.rfind("\n", 0, match.start()) + 1
    line_end = text.find("\n", match.end())
    if line_end == -1:
        line_end = len(text)
    failures.append(f"{description}：{text[line_start:line_end].strip()}")

if failures:
    raise SystemExit(f"{label} 日志质量门槛失败：\n" + "\n".join(failures))

print(f"{label} 日志通过：无编译警告或可操作的 SwiftUI 运行时诊断。")
