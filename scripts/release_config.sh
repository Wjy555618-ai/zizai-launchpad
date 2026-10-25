#!/bin/zsh

# Read a target-level Release build setting from the single Xcode source of truth.
zizai_release_setting() {
  local project_dir="$1"
  local setting_name="$2"
  local xcrun_bin="${ZIZAI_XCRUN_PATH:-/usr/bin/xcrun}"
  local xcodebuild_bin=""

  [[ -x "$xcrun_bin" ]] || return 1
  xcodebuild_bin="$($xcrun_bin --find xcodebuild 2>/dev/null || true)"
  [[ -n "$xcodebuild_bin" && -x "$xcodebuild_bin" ]] || return 1

  "$xcodebuild_bin" \
    -project "$project_dir/自在启动台.xcodeproj" \
    -scheme "自在启动台" \
    -configuration Release \
    -showBuildSettings 2>/dev/null \
    | /usr/bin/awk -F ' = ' -v key="$setting_name" \
        '$1 ~ "^[[:space:]]*" key "[[:space:]]*$" { print $2; exit }'
}

zizai_require_release_setting() {
  local project_dir="$1"
  local setting_name="$2"
  local value=""

  value="$(zizai_release_setting "$project_dir" "$setting_name")"
  [[ -n "$value" ]] || {
    echo "无法从 Xcode Release 配置读取 $setting_name" >&2
    return 1
  }
  /usr/bin/printf '%s\n' "$value"
}
