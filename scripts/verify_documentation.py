#!/usr/bin/env python3
"""Validate repository-controlled Markdown links and public-path hygiene."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parent.parent
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
IGNORED_DIRECTORIES = {".git", ".artifacts.noindex", "build", "DerivedData"}


def markdown_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*.md"):
        if any(part in IGNORED_DIRECTORIES for part in path.relative_to(ROOT).parts):
            continue
        files.append(path)
    return sorted(files)


def local_link_target(raw_target: str) -> str | None:
    target = raw_target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    target = target.split(maxsplit=1)[0]
    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc or target.startswith("#"):
        return None
    return unquote(parsed.path)


def main() -> int:
    errors: list[str] = []
    files = markdown_files()
    for path in files:
        text = path.read_text(encoding="utf-8")
        relative_path = path.relative_to(ROOT)
        if re.search(r"/Users/[A-Za-z0-9._-]+/", text):
            errors.append(f"{relative_path}: 包含个人绝对路径")
        for line_number, line in enumerate(text.splitlines(), start=1):
            for match in MARKDOWN_LINK.finditer(line):
                target = local_link_target(match.group(1))
                if target is None or not target:
                    continue
                resolved = (path.parent / target).resolve()
                if not resolved.is_relative_to(ROOT.resolve()):
                    errors.append(
                        f"{relative_path}:{line_number}: 本地链接越出仓库边界：{target}"
                    )
                elif not resolved.exists():
                    errors.append(
                        f"{relative_path}:{line_number}: 本地链接不存在：{target}"
                    )

    if errors:
        print("文档审计失败：", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"文档审计通过：{len(files)} 个 Markdown 文件的本地链接与路径边界有效。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
