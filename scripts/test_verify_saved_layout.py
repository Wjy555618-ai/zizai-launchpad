#!/usr/bin/env python3
"""Exercise the saved-layout validator as a fail-closed release contract."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
VALIDATOR = ROOT / "scripts" / "verify_saved_layout.py"


def run(path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["/usr/bin/python3", str(VALIDATOR), "--state", str(path)],
        capture_output=True,
        text=True,
        check=False,
    )


def write(path: Path, groups: list[dict]) -> None:
    payload = {
        "userGroups": groups,
        "positions": {"app-a": {"x": 300, "y": 325}},
        "appGroupIDs": {"app-a": "group-a"},
        "hiddenAppIDs": [],
    }
    path.write_text(json.dumps(payload), encoding="utf-8")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="zizai-layout-contract-") as directory:
        root = Path(directory)
        valid = root / "valid.json"
        invalid = root / "invalid.json"
        missing = root / "missing.json"
        first = {
            "id": "group-a",
            "name": "A",
            "center": {"x": 300, "y": 300},
            "size": {"width": 400, "height": 300},
        }
        second = {
            "id": "group-b",
            "name": "B",
            "center": {"x": 800, "y": 300},
            "size": {"width": 400, "height": 300},
        }
        overlapping = {**second, "center": {"x": 500, "y": 300}}
        write(valid, [first, second])
        write(invalid, [first, overlapping])

        valid_result = run(valid)
        if valid_result.returncode != 0:
            raise SystemExit(valid_result.stderr or valid_result.stdout)
        for label, result in (("缺失文件", run(missing)), ("重叠布局", run(invalid))):
            if result.returncode == 0:
                raise SystemExit(f"布局验证器未对{label}失败关闭")

    print("布局验证器契约通过：明确文件成功，缺失或冲突数据均失败关闭。")


if __name__ == "__main__":
    main()
