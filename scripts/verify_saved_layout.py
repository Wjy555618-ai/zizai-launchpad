#!/usr/bin/env python3
"""Validate the installed user's persisted spatial layout semantically."""

from __future__ import annotations

import json
import os
import pathlib
import plistlib


ROOT = pathlib.Path(__file__).resolve().parent.parent
APP_WIDTH = 164.0
APP_HEIGHT = 158.0
GROUP_GAP = 42.0


def fail(message: str) -> None:
    raise SystemExit(f"布局验收失败：{message}")


def resolved_bundle_identifier() -> str | None:
    if configured := os.environ.get("ZIZAI_BUNDLE_IDENTIFIER"):
        return configured
    built_info = ROOT / ".artifacts.noindex" / "自在启动台.app" / "Contents" / "Info.plist"
    if not built_info.exists():
        return None
    with built_info.open("rb") as info_file:
        value = plistlib.load(info_file).get("CFBundleIdentifier")
    return value if isinstance(value, str) and value else None


def group_rect(group: dict) -> tuple[float, float, float, float]:
    width = float(group["size"]["width"])
    height = float(group["size"]["height"])
    center = group["center"]
    return (
        float(center["x"]) - width / 2,
        float(center["y"]) - height / 2,
        width,
        height,
    )


def intersects(
    left: tuple[float, float, float, float],
    right: tuple[float, float, float, float],
    gap: float,
) -> bool:
    lx, ly, lw, lh = left
    rx, ry, rw, rh = right
    return not (
        lx + lw + gap <= rx
        or rx + rw + gap <= lx
        or ly + lh + gap <= ry
        or ry + rh + gap <= ly
    )


def main() -> None:
    bundle_identifier = resolved_bundle_identifier()
    if bundle_identifier is None:
        print("未定位构建产物 Bundle ID，跳过本机已安装布局验收。")
        return
    state_path = (
        pathlib.Path.home()
        / "Library"
        / "Containers"
        / bundle_identifier
        / "Data"
        / "Library"
        / "Application Support"
        / "自在启动台"
        / "布局.json"
    )
    if not state_path.exists():
        print("未发现既有布局数据，跳过本机布局迁移验收。")
        return

    data = json.loads(state_path.read_text(encoding="utf-8"))
    groups = data.get("userGroups", [])
    positions = data.get("positions", {})
    assignments = data.get("appGroupIDs", {})
    hidden_ids = set(data.get("hiddenAppIDs", []))

    for index, left in enumerate(groups):
        for right in groups[index + 1 :]:
            if intersects(group_rect(left), group_rect(right), GROUP_GAP):
                fail(f"分组“{left['name']}”与“{right['name']}”重叠或间距不足")

    groups_by_id = {group["id"]: group for group in groups}
    members: dict[str, list[tuple[str, float, float]]] = {}
    for app_id, point in positions.items():
        if app_id in hidden_ids:
            continue
        group_id = assignments.get(app_id)
        if group_id not in groups_by_id:
            continue
        app_x = float(point["x"])
        app_y = float(point["y"])
        members.setdefault(group_id, []).append((app_id, app_x, app_y))

        x, y, width, height = group_rect(groups_by_id[group_id])
        min_x, max_x = x + 48 + APP_WIDTH / 2, x + width - 48 - APP_WIDTH / 2
        min_y, max_y = y + 82 + APP_HEIGHT / 2, y + height - 30 - APP_HEIGHT / 2
        tolerance = 0.5
        if not (
            min_x - tolerance <= app_x <= max_x + tolerance
            and min_y - tolerance <= app_y <= max_y + tolerance
        ):
            fail(f"应用 {app_id} 超出所属分组安全区")

    for group_id, applications in members.items():
        for index, left in enumerate(applications):
            for right in applications[index + 1 :]:
                if (
                    abs(left[1] - right[1]) < APP_WIDTH - 0.5
                    and abs(left[2] - right[2]) < APP_HEIGHT - 0.5
                ):
                    fail(f"应用 {left[0]} 与 {right[0]} 在分组 {group_id} 重叠")

    visible_count = sum(app_id not in hidden_ids for app_id in positions)
    print(f"布局验收通过：{len(groups)} 个分组、{visible_count} 个可见应用均无重叠。")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        fail(str(error))
