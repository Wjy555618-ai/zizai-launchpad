#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"

cd "$ROOT"
/usr/bin/shasum -a 256 -c SHA256SUMS >/dev/null
/usr/bin/python3 -m json.tool ICON_COMPOSER_MANIFEST.json >/dev/null

# Icon Composer 27 writes a non-empty top-level `features` gate. Stable Xcode
# 26 understands the material properties themselves but crashes in actool when
# that preview-only gate is present. Keep one shipping .icon document that both
# stable and next-generation toolchains can compile.
/usr/bin/python3 - "../AppIcon.icon/icon.json" <<'PY'
import json
from pathlib import Path
import sys

icon = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if icon.get("features"):
    raise SystemExit(
        "AppIcon.icon contains the Icon Composer 27 top-level features gate; "
        "remove it before release so stable Xcode 26 actool can compile the icon."
    )
groups = icon.get("groups", [])
if len(groups) != 4 or any(len(group.get("layers", [])) != 1 for group in groups):
    raise SystemExit("AppIcon.icon must retain four independent one-layer groups.")
PY

EXPECTED_SVGS=(
  00-background-reference.svg
  01-red-square.svg
  02-blue-triangle.svg
  03-yellow-square.svg
  04-green-circle.svg
  05-flat-composite-preview.svg
  current-logo-reference.svg
)

for svg in "${EXPECTED_SVGS[@]}"; do
  /usr/bin/xmllint --noout "$svg"
  /usr/bin/grep -q 'width="1024" height="1024" viewBox="0 0 1024 1024"' "$svg"
  if /usr/bin/grep -E '<(script|foreignObject|image|filter|mask)([[:space:]>])' "$svg" >/dev/null; then
    echo "SVG 含有不允许的脚本、外链图像、滤镜或遮罩：$svg" >&2
    exit 1
  fi
done

for layer in 01-red-square.svg 02-blue-triangle.svg 03-yellow-square.svg 04-green-circle.svg; do
  if /usr/bin/grep -E '<(linearGradient|radialGradient)|filter=|mask=|opacity=' "$layer" >/dev/null; then
    echo "Icon Composer 前景层不是平面不透明源：$layer" >&2
    exit 1
  fi
  /usr/bin/grep -q 'transform="translate(-7 -5)"' "$layer"
done

echo "ICON_COMPOSER_LAYER_PACKAGE_OK"
echo "CANVAS=1024x1024"
echo "FOREGROUND_LAYERS=4"
echo "PREMASKED=NO"
echo "BAKED_FILTERS=NO"
