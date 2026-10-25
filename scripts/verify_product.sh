#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
APP_DIR="$ARTIFACT_DIR/自在启动台.app"
INSTALLED_APP="${ZIZAI_INSTALLED_APP:-/Applications/自在启动台.app}"

/bin/zsh "$PROJECT_DIR/scripts/run_interaction_tests.sh"
[[ -x "$APP_DIR/Contents/MacOS/ZizaiLaunchpad" ]] || {
  echo "缺少已通过发布门槛的本地应用产物；请先运行 scripts/verify_release.sh。" >&2
  exit 1
}
/usr/bin/python3 "$PROJECT_DIR/scripts/generate_quality_evidence.py" \
  "$ARTIFACT_DIR" --verify-current
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")"
STATE="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/自在启动台/布局.json"
BACKUP_STATE="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/自在启动台/布局.backup.json"
/bin/zsh "$PROJECT_DIR/scripts/run_visual_render_audit.sh" /tmp/zizai-product-visual-audit.png >/dev/null
[[ -s /tmp/zizai-product-visual-audit.png ]]
ZIZAI_BUNDLE_IDENTIFIER="$BUNDLE_ID" /usr/bin/python3 "$PROJECT_DIR/scripts/verify_saved_layout.py"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
/usr/bin/plutil -lint "$PROJECT_DIR/Resources/Info.plist" "$PROJECT_DIR/Resources/ZizaiLaunchpad.entitlements" >/dev/null
/usr/bin/python3 "$PROJECT_DIR/scripts/verify_security_capabilities.py" --app "$APP_DIR"

if [[ -f "$STATE" ]]; then
  /usr/bin/python3 -m json.tool "$STATE" >/dev/null
fi
if [[ -f "$BACKUP_STATE" ]]; then
  /usr/bin/python3 -m json.tool "$BACKUP_STATE" >/dev/null
fi
if [[ -x "$INSTALLED_APP/Contents/MacOS/ZizaiLaunchpad" ]]; then
  [[ "$(/usr/bin/shasum -a 256 "$APP_DIR/Contents/MacOS/ZizaiLaunchpad" | /usr/bin/awk '{print $1}')" == \
     "$(/usr/bin/shasum -a 256 "$INSTALLED_APP/Contents/MacOS/ZizaiLaunchpad" | /usr/bin/awk '{print $1}')" ]]
fi

echo "产品验收通过：构建、交互模型、应用扫描、状态闭环、离屏界面、布局完整性、签名和本机安装一致性均正常。"
