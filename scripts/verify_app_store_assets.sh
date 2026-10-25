#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SCREENSHOT_DIR="$PROJECT_DIR/AppStore/Screenshots/zh-Hans"
SOURCE_MANIFEST="$SCREENSHOT_DIR/SOURCE_MANIFEST.sha256"
EXPECTED_SCREENSHOTS=("01-groups.jpg" "02-space.jpg" "03-all-apps.jpg" "04-search.jpg")

[[ -d "$SCREENSHOT_DIR" ]] || {
  echo "App Store 素材验收失败：缺少 $SCREENSHOT_DIR" >&2
  exit 1
}

SCREENSHOTS=("$SCREENSHOT_DIR"/*.(jpg|jpeg|png)(N))
[[ ${#SCREENSHOTS[@]} -eq ${#EXPECTED_SCREENSHOTS[@]} ]] || {
  echo "App Store 素材验收失败：交付集必须精确包含 4 张审核截图" >&2
  exit 1
}

for expected in "${EXPECTED_SCREENSHOTS[@]}"; do
  [[ -f "$SCREENSHOT_DIR/$expected" ]] || {
    echo "App Store 素材验收失败：缺少 $expected" >&2
    exit 1
  }
done

for screenshot in "${SCREENSHOTS[@]}"; do
  INFO="$(/usr/bin/sips -g pixelWidth -g pixelHeight -g hasAlpha "$screenshot" 2>/dev/null)"
  WIDTH="$(printf '%s\n' "$INFO" | /usr/bin/awk '/pixelWidth:/ {print $2}')"
  HEIGHT="$(printf '%s\n' "$INFO" | /usr/bin/awk '/pixelHeight:/ {print $2}')"
  HAS_ALPHA="$(printf '%s\n' "$INFO" | /usr/bin/awk '/hasAlpha:/ {print $2}')"
  SIZE="${WIDTH}x${HEIGHT}"

  if [[ "$SIZE" != "2880x1800" ]]; then
    echo "App Store 素材验收失败：$(basename "$screenshot") 尺寸 $SIZE，必须是 2880x1800" >&2
    exit 1
  fi
  if [[ "$HAS_ALPHA" == "yes" ]]; then
    echo "App Store 素材验收失败：$(basename "$screenshot") 含透明通道" >&2
    exit 1
  fi
done

[[ -f "$SOURCE_MANIFEST" ]] || {
  echo "App Store 素材验收失败：缺少可追溯的源文件摘要" >&2
  exit 1
}
if ! (cd "$PROJECT_DIR" && /usr/bin/shasum -a 256 -c "$SOURCE_MANIFEST" >/dev/null); then
  echo "App Store 素材验收失败：截图已落后于当前产品源码，请重新生成" >&2
  exit 1
fi

echo "App Store 截图验收通过：4 张 2880x1800 不透明 JPEG，且与当前产品源码一致。"
