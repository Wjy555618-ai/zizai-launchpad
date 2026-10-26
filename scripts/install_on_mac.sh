#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
ARTIFACT_DIR="${ZIZAI_BUILD_DIR:-$PROJECT_DIR/.artifacts.noindex}"
APP_NAME="自在启动台.app"
BUNDLE_ID=""
BUILD_APP="$ARTIFACT_DIR/$APP_NAME"
INSTALL_DEST="${ZIZAI_INSTALL_DEST:-/Applications/$APP_NAME}"
INSTALL_PARENT="${INSTALL_DEST:h}"
LEGACY_BACKUP_ROOT="${ZIZAI_BACKUP_ROOT:-$HOME/Library/Application Support/自在启动台/安装备份}"
XCRUN_BIN="${ZIZAI_XCRUN_PATH:-/usr/bin/xcrun}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
SKIP_LAUNCH="${ZIZAI_SKIP_LAUNCH:-0}"
PACKAGE_SUMS="$PROJECT_DIR/SHA256SUMS"
TEMP_ROOT=""
TEMP_SEED=""
PREVIOUS_APP=""
INSTALL_WRITE_STARTED=0
INSTALL_COMPLETE=0

fail() {
  echo "安装停止：$1" >&2
  exit 1
}

unregister_app() {
  local app_path="$1"
  if [[ -x "$LSREGISTER" && -n "$app_path" ]]; then
    "$LSREGISTER" -u "$app_path" >/dev/null 2>&1 || true
  fi
}

registered_paths_for_bundle_id() {
  local target_id="$1"
  [[ -x "$LSREGISTER" ]] || return 0
  "$LSREGISTER" -dump | /usr/bin/awk -v target_id="$target_id" '
    function emit() {
      if (identifier == target_id && path != "") print path
      path = ""
      identifier = ""
    }
    /^-+$/ { emit(); next }
    /^path:[[:space:]]*/ {
      path = $0
      sub(/^path:[[:space:]]*/, "", path)
      sub(/[[:space:]]+\(0x[0-9a-fA-F]+\)$/, "", path)
      next
    }
    /^identifier:[[:space:]]*/ {
      identifier = $0
      sub(/^identifier:[[:space:]]*/, "", identifier)
      next
    }
    END { emit() }
  '
}

registered_paths_for_project_products() {
  [[ -x "$LSREGISTER" ]] || return 0
  "$LSREGISTER" -dump | /usr/bin/awk '
    function emit() {
      if (path ~ /\/(自在启动台|自在启动台UITests-Runner)\.app$/) print path
      path = ""
    }
    /^-+$/ { emit(); next }
    /^path:[[:space:]]*/ {
      path = $0
      sub(/^path:[[:space:]]*/, "", path)
      sub(/[[:space:]]+\(0x[0-9a-fA-F]+\)$/, "", path)
      next
    }
    END { emit() }
  '
}

cleanup_install() {
  local exit_code=$?
  if [[ $exit_code -ne 0 && $INSTALL_WRITE_STARTED -eq 1 && $INSTALL_COMPLETE -eq 0 ]]; then
    if [[ -e "$INSTALL_DEST" && -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]]; then
      unregister_app "$INSTALL_DEST"
      /bin/mv "$INSTALL_DEST" "$TEMP_ROOT/未完成的新版本.bundle-backup" || true
    fi
    if [[ -n "$PREVIOUS_APP" && -e "$PREVIOUS_APP" ]]; then
      /bin/mkdir -p "$INSTALL_PARENT"
      /bin/mv "$PREVIOUS_APP" "$INSTALL_DEST" || true
      [[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f -R -trusted "$INSTALL_DEST" >/dev/null 2>&1 || true
      echo "已恢复安装前的应用。" >&2
    fi
  fi
  if [[ -n "$TEMP_ROOT" && "$TEMP_ROOT" == *"/zizai-install."* && -d "$TEMP_ROOT" ]]; then
    /bin/rm -rf "$TEMP_ROOT"
  fi
  return $exit_code
}
trap cleanup_install EXIT

echo "[1/7] 检查交付包完整性"
if [[ -f "$PACKAGE_SUMS" ]]; then
  (
    cd "$PROJECT_DIR"
    /usr/bin/shasum -a 256 -c SHA256SUMS >/dev/null
  ) || fail "文件校验失败，交付包可能不完整或已被修改。"
else
  echo "未发现 SHA256SUMS；当前是源码工程模式，继续使用本地文件。"
fi

echo "[2/7] 检查目标 Mac 和 Xcode"
SYSTEM_ARCH="$(/usr/bin/uname -m)"
SYSTEM_VERSION="$(/usr/bin/sw_vers -productVersion)"
SYSTEM_MAJOR="${SYSTEM_VERSION%%.*}"
[[ "$SYSTEM_ARCH" == "arm64" || "$SYSTEM_ARCH" == "x86_64" ]] || fail "需要 Apple Silicon 或 Intel Mac，检测到 $SYSTEM_ARCH。"
[[ "$SYSTEM_MAJOR" == <-> ]] || fail "无法识别 macOS 版本：$SYSTEM_VERSION。"
(( SYSTEM_MAJOR >= 13 )) || fail "需要 macOS 13.0 或更高版本，检测到 $SYSTEM_VERSION。"
[[ -x "$XCRUN_BIN" ]] || fail "未找到 Apple 开发工具。请先安装 Xcode。"
XCODEBUILD="$($XCRUN_BIN --find xcodebuild 2>/dev/null || true)"
[[ -n "$XCODEBUILD" && -x "$XCODEBUILD" ]] || fail "需要完整 Xcode，不再允许构建旧图标版本。"

echo "[3/7] 构建唯一正式版本"
/bin/zsh "$PROJECT_DIR/scripts/build.sh" >/dev/null
[[ -x "$BUILD_APP/Contents/MacOS/ZizaiLaunchpad" ]] || fail "构建未产生可执行应用。"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUILD_APP/Contents/Info.plist" 2>/dev/null || true)"
[[ -n "$BUNDLE_ID" ]] || fail "构建产物缺少 Bundle ID。"
EXISTING_STATE="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/自在启动台/布局.json"
BUILD_ARCHITECTURES="$(/usr/bin/lipo -archs "$BUILD_APP/Contents/MacOS/ZizaiLaunchpad")"
[[ "$BUILD_ARCHITECTURES" == *"arm64"* && "$BUILD_ARCHITECTURES" == *"x86_64"* ]] || fail "构建产物不是 Universal 2：$BUILD_ARCHITECTURES"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$BUILD_APP/Contents/Info.plist")" == "AppIcon" ]] || fail "构建产物不是新的 Liquid Glass Logo 版本。"
[[ -f "$BUILD_APP/Contents/Resources/Assets.car" ]] || fail "构建产物缺少原生图标资产。"

echo "[4/7] 运行核心工程验证"
/usr/bin/codesign --verify --deep --strict "$BUILD_APP"
/bin/zsh "$PROJECT_DIR/scripts/run_interaction_tests.sh" >/dev/null
/bin/zsh "$PROJECT_DIR/scripts/run_canvas_interaction_performance_audit.sh" >/dev/null
if [[ -f "$EXISTING_STATE" ]]; then
  /usr/bin/python3 "$PROJECT_DIR/scripts/verify_saved_layout.py" --state "$EXISTING_STATE" >/dev/null
else
  echo "当前 Bundle ID 没有旧布局；新安装无迁移对象。"
fi

echo "[5/7] 分阶段原子安装"
/bin/mkdir -p "$INSTALL_PARENT"
[[ -w "$INSTALL_PARENT" ]] || fail "没有写入权限：$INSTALL_PARENT。"

# 替换磁盘上的包不会替换已经运行的进程。先结束所有同名进程，
# 避免新旧两个二进制同时驻留。
if /usr/bin/pgrep -x ZizaiLaunchpad >/dev/null 2>&1; then
  /usr/bin/pkill -TERM -x ZizaiLaunchpad >/dev/null 2>&1 || true
  for _ in {1..50}; do
    /usr/bin/pgrep -x ZizaiLaunchpad >/dev/null 2>&1 || break
    /bin/sleep 0.1
  done
  /usr/bin/pgrep -x ZizaiLaunchpad >/dev/null 2>&1 \
    && fail "旧版本仍在运行，已停止安装以避免版本并存。"
fi

TEMP_SEED="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/zizai-install.XXXXXX")"
TEMP_ROOT="$TEMP_SEED.noindex"
/bin/mv "$TEMP_SEED" "$TEMP_ROOT"
/usr/bin/touch "$TEMP_ROOT/.metadata_never_index"
STAGED_APP="$TEMP_ROOT/$APP_NAME"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl "$BUILD_APP" "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"

unregister_app "$INSTALL_DEST"
if [[ -e "$INSTALL_DEST" ]]; then
  # A rollback payload is data, not another installable application. Keeping
  # the `.app` suffix made Spotlight briefly expose the transaction backup as
  # a second product while the uniqueness check was running.
  PREVIOUS_APP="$TEMP_ROOT/安装前版本.bundle-backup"
  /bin/mv "$INSTALL_DEST" "$PREVIOUS_APP"
fi

INSTALL_WRITE_STARTED=1
if ! COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl "$STAGED_APP" "$INSTALL_DEST"; then
  fail "新版本复制失败。"
fi

if ! /usr/bin/codesign --verify --deep --strict "$INSTALL_DEST"; then
  fail "安装后签名验证失败。"
fi

BUILD_HASH="$(/usr/bin/shasum -a 256 "$BUILD_APP/Contents/MacOS/ZizaiLaunchpad" | /usr/bin/awk '{print $1}')"
INSTALLED_HASH="$(/usr/bin/shasum -a 256 "$INSTALL_DEST/Contents/MacOS/ZizaiLaunchpad" | /usr/bin/awk '{print $1}')"
[[ "$BUILD_HASH" == "$INSTALLED_HASH" ]] || fail "安装二进制与本地构建不一致。"

if [[ "${ZIZAI_INSTALL_TEST_MODE:-0}" == "1" && "${ZIZAI_TEST_FAIL_AFTER_INSTALL:-0}" == "1" ]]; then
  fail "安装事务恢复测试已按预期触发。"
fi

echo "[6/7] 注销并清理所有历史副本"
typeset -a DUPLICATE_APPS
DUPLICATE_APPS=()
if [[ -d "$PROJECT_DIR/build" ]]; then
  DUPLICATE_APPS+=("${(@f)$(/usr/bin/find "$PROJECT_DIR/build" -type d -name "$APP_NAME" -prune -print 2>/dev/null)}")
fi
if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
  DUPLICATE_APPS+=("${(@f)$(/usr/bin/find "$HOME/Library/Developer/Xcode/DerivedData" -type d -name "$APP_NAME" -prune -print 2>/dev/null)}")
fi
if [[ -d "$ARTIFACT_DIR" ]]; then
  DUPLICATE_APPS+=("${(@f)$(/usr/bin/find "$ARTIFACT_DIR" -type d -name "$APP_NAME" -prune -print 2>/dev/null)}")
fi
if [[ -d "$LEGACY_BACKUP_ROOT" ]]; then
  DUPLICATE_APPS+=("${(@f)$(/usr/bin/find "$LEGACY_BACKUP_ROOT" -type d -name '*.app' -prune -print 2>/dev/null)}")
fi

for duplicate_app in "${DUPLICATE_APPS[@]}"; do
  [[ -n "$duplicate_app" && "$duplicate_app" != "$INSTALL_DEST" ]] || continue
  unregister_app "$duplicate_app"
  # Retain only the canonical local build and unsigned Archive as .noindex
  # evidence. They are explicitly unregistered and cannot appear as a second
  # installed app. Every other product/debug copy is disposable build output.
  if [[ "$duplicate_app" != "$BUILD_APP" && "$duplicate_app" != "$ARTIFACT_DIR/"*.xcarchive/* ]]; then
    /bin/rm -rf "$duplicate_app"
  fi
done

# UI runners have a different Bundle ID but the same visible product name in
# system alerts. They are never distributable products and must not survive or
# remain registered after installation.
typeset -a TEST_RUNNERS
TEST_RUNNERS=()
if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
  TEST_RUNNERS+=("${(@f)$(/usr/bin/find "$HOME/Library/Developer/Xcode/DerivedData" -type d -name '自在启动台UITests-Runner.app' -prune -print 2>/dev/null)}")
fi
if [[ -d "$ARTIFACT_DIR" ]]; then
  TEST_RUNNERS+=("${(@f)$(/usr/bin/find "$ARTIFACT_DIR" -type d -name '自在启动台UITests-Runner.app' -prune -print 2>/dev/null)}")
fi
for test_runner in "${TEST_RUNNERS[@]}"; do
  [[ -n "$test_runner" ]] || continue
  unregister_app "$test_runner"
  /bin/rm -rf "$test_runner"
done

# LaunchServices keeps historical rows even after a temporary build directory
# has disappeared. Remove every stale registration for the production Bundle
# ID by its recorded path, including entries whose files no longer exist.
if [[ -x "$LSREGISTER" ]]; then
  typeset -a REGISTERED_PRODUCTION_APPS
  REGISTERED_PRODUCTION_APPS=("${(@f)$(registered_paths_for_bundle_id "$BUNDLE_ID")}")
  for registered_app in "${REGISTERED_PRODUCTION_APPS[@]}"; do
    [[ -n "$registered_app" && "$registered_app" != "$INSTALL_DEST" ]] || continue
    unregister_app "$registered_app"
  done

  # Bundle IDs differ between Release, Debug and XCUITest Runner builds. Clean
  # their historical rows by the two exact project product names as well, so
  # deleted /tmp and DerivedData builds cannot reappear after a cache refresh.
  typeset -a REGISTERED_PROJECT_APPS
  REGISTERED_PROJECT_APPS=("${(@f)$(registered_paths_for_project_products)}")
  for registered_app in "${REGISTERED_PROJECT_APPS[@]}"; do
    [[ -n "$registered_app" && "$registered_app" != "$INSTALL_DEST" ]] || continue
    unregister_app "$registered_app"
  done
fi

# The retained release artifact lives in a .noindex directory for symbol and
# reproducibility checks. Explicitly unregister it because xcodebuild can
# register products independently of Spotlight indexing rules.
unregister_app "$BUILD_APP"

# 旧安装器把每次替换都保存成可被 macOS 索引的 .app，这正是版本错乱根因。
# 新安装器只在当前事务的临时目录中保留可回滚旧版，成功后立即清理。
if [[ -d "$LEGACY_BACKUP_ROOT" ]]; then
  /usr/bin/find "$LEGACY_BACKUP_ROOT" -depth -type d -empty -delete 2>/dev/null || true
fi

[[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f -R -trusted "$INSTALL_DEST" >/dev/null 2>&1 || true

echo "[7/7] 验证唯一安装版"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALL_DEST/Contents/Info.plist")" == "$BUNDLE_ID" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INSTALL_DEST/Contents/Info.plist")" == "AppIcon" ]]
[[ "$(/usr/bin/lipo -archs "$INSTALL_DEST/Contents/MacOS/ZizaiLaunchpad")" == *"arm64"* ]]
[[ "$(/usr/bin/lipo -archs "$INSTALL_DEST/Contents/MacOS/ZizaiLaunchpad")" == *"x86_64"* ]]

# The rollback payload intentionally remains available until the installed
# binary, identity, icon and architectures have all been validated. Remove the
# transaction only after those checks, then inspect Spotlight and
# LaunchServices against the same filesystem state the user will keep.
if [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]]; then
  /bin/rm -rf "$TEMP_ROOT"
  TEMP_ROOT=""
  PREVIOUS_APP=""
fi

typeset -a INDEXED_PRODUCTION_APPS
INDEXED_PRODUCTION_APPS=("${(@f)$(/usr/bin/mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null)}")
for indexed_app in "${INDEXED_PRODUCTION_APPS[@]}"; do
  [[ -d "$indexed_app" ]] || continue
  [[ "$indexed_app" == "$INSTALL_DEST" ]] \
    || fail "macOS 仍索引到第二个正式版：$indexed_app"
done

if [[ -x "$LSREGISTER" ]]; then
  typeset -a FINAL_REGISTERED_PRODUCTION_APPS
  FINAL_REGISTERED_PRODUCTION_APPS=("${(@f)$(registered_paths_for_bundle_id "$BUNDLE_ID")}")
  for registered_app in "${FINAL_REGISTERED_PRODUCTION_APPS[@]}"; do
    [[ -n "$registered_app" ]] || continue
    [[ "$registered_app" == "$INSTALL_DEST" ]] \
      || fail "LaunchServices 仍保留第二个正式版注册：$registered_app"
  done


  typeset -a FINAL_REGISTERED_PROJECT_APPS
  FINAL_REGISTERED_PROJECT_APPS=("${(@f)$(registered_paths_for_project_products)}")
  for registered_app in "${FINAL_REGISTERED_PROJECT_APPS[@]}"; do
    [[ -n "$registered_app" ]] || continue
    [[ "$registered_app" == "$INSTALL_DEST" ]] \
      || fail "LaunchServices 仍保留项目生成的副本：$registered_app"
  done
fi

if [[ "$SKIP_LAUNCH" != "1" ]]; then
  /usr/bin/open "$INSTALL_DEST"
fi
INSTALL_COMPLETE=1

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALL_DEST/Contents/Info.plist")"
echo "INSTALL_OK"
echo "APP_PATH=$INSTALL_DEST"
echo "VERSION=$APP_VERSION"
echo "ARCHITECTURES=$BUILD_ARCHITECTURES"
echo "MACOS_VERSION=$SYSTEM_VERSION"
echo "BINARY_SHA256=$INSTALLED_HASH"
echo "DUPLICATE_POLICY=ONLY_APPLICATIONS_COPY"
