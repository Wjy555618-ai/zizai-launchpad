#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
/bin/mkdir -p "$ARTIFACT_DIR"
WORK_DIR="$(/usr/bin/mktemp -d "$ARTIFACT_DIR/visual-reproducibility.XXXXXX")"
trap '/bin/rm -rf "$WORK_DIR"' EXIT

typeset -a SCREENSHOT_CASES=(
  "01-groups:storeGroups:dark"
  "02-space:storeSpace:dark"
  "03-all-apps:storeAllApps:dark"
  "04-search:storeSearch:dark"
)

render_pass() {
  local pass="$1"
  local output_dir="$WORK_DIR/$pass"
  /bin/mkdir -p "$output_dir"
  local specification stem layout appearance png jpg
  for specification in "${SCREENSHOT_CASES[@]}"; do
    stem="${specification%%:*}"
    specification="${specification#*:}"
    layout="${specification%%:*}"
    appearance="${specification##*:}"
    png="$output_dir/$stem.png"
    jpg="$output_dir/$stem.jpg"
    /bin/zsh "$PROJECT_DIR/scripts/run_visual_render_audit.sh" \
      "$png" "$layout" "$appearance" reducedMotion >/dev/null
    /usr/bin/sips -s format jpeg -s formatOptions 92 "$png" --out "$jpg" >/dev/null
  done
}

render_pass first
render_pass second

for specification in "${SCREENSHOT_CASES[@]}"; do
  stem="${specification%%:*}"
  /usr/bin/cmp -s "$WORK_DIR/first/$stem.png" "$WORK_DIR/second/$stem.png" || {
    echo "视觉可重复性失败：$stem 的两次 PNG 渲染不一致" >&2
    exit 1
  }
  /usr/bin/cmp -s "$WORK_DIR/first/$stem.jpg" "$WORK_DIR/second/$stem.jpg" || {
    echo "视觉可重复性失败：$stem 的两次 JPEG 导出不一致" >&2
    exit 1
  }
done

echo "视觉可重复性门槛通过：4 个商店场景连续两次生成的 2× PNG 与 JPEG 均逐字节一致。"
