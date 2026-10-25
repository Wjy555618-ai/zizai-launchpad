#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
PACKAGE_NAME="自在启动台-AppStore首发版项目接力包"
ROOT_NAME="自在启动台-AppStore首发版"
DEST_DIR="${ZIZAI_HANDOFF_DEST:-$HOME/Downloads}"
ZIP_PATH="$DEST_DIR/$PACKAGE_NAME.zip"
ZIP_SUM_PATH="$ZIP_PATH.sha256"
STAGE_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/zizai-app-store-handoff.XXXXXX")"
PACKAGE_DIR="$STAGE_ROOT/$ROOT_NAME"

cleanup_package() {
  local exit_code=$?
  if [[ "$STAGE_ROOT" == *"/zizai-app-store-handoff."* && -d "$STAGE_ROOT" ]]; then
    /bin/rm -rf "$STAGE_ROOT"
  fi
  return $exit_code
}
trap cleanup_package EXIT

[[ -n "$DEST_DIR" && "$DEST_DIR" != "/" ]] || {
  echo "拒绝使用不安全的输出目录：$DEST_DIR" >&2
  exit 1
}

/bin/mkdir -p "$PACKAGE_DIR/scripts" "$PACKAGE_DIR/evidence" "$DEST_DIR"

COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl \
  "$PROJECT_DIR/.swift-format" "$PACKAGE_DIR/.swift-format"

for SOURCE_DIR in Sources Resources Tests AppStore "自在启动台.xcodeproj"; do
  COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl \
    "$PROJECT_DIR/$SOURCE_DIR" "$PACKAGE_DIR/$SOURCE_DIR"
done

# Preserve local design history without shipping superseded Icon Composer drafts.
if [[ -d "$PACKAGE_DIR/Resources/IconComposer/archive" ]]; then
  /bin/rm -rf "$PACKAGE_DIR/Resources/IconComposer/archive"
fi

# Xcode recreates these local UI and user-state directories. They are never
# part of a source handoff and may contain the release Mac account name.
for LOCAL_XCODE_STATE in \
  "$PACKAGE_DIR/自在启动台.xcodeproj/xcuserdata" \
  "$PACKAGE_DIR/自在启动台.xcodeproj/project.xcworkspace"; do
  if [[ -e "$LOCAL_XCODE_STATE" ]]; then
    /bin/rm -rf "$LOCAL_XCODE_STATE"
  fi
done

# Copy the complete release-tooling surface so a new dependency introduced by
# verify_release.sh cannot silently disappear from the handoff. Exclude only
# local installation, public-repository, and package-construction commands that
# do not belong on a separate App Store release Mac.
for SCRIPT_PATH in "$PROJECT_DIR/scripts"/*; do
  [[ -f "$SCRIPT_PATH" ]] || continue
  SCRIPT_NAME="${SCRIPT_PATH:t}"
  case "$SCRIPT_NAME" in
    install_on_mac.sh|audit_public_repo.sh|package_app_store_handoff.sh|verify_app_store_handoff.sh)
      continue
      ;;
  esac
  COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl \
    "$SCRIPT_PATH" "$PACKAGE_DIR/scripts/$SCRIPT_NAME"
done

# The release gate validates product claims across the complete current
# documentation set. Copy top-level Markdown as one coherent truth surface so
# adding or renaming a checked document cannot produce a partially valid
# handoff.
for DOCUMENT_PATH in "$PROJECT_DIR"/*.md; do
  [[ -f "$DOCUMENT_PATH" ]] || continue
  DOCUMENT_NAME="${DOCUMENT_PATH:t}"
  COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl \
    "$DOCUMENT_PATH" "$PACKAGE_DIR/$DOCUMENT_NAME"
done
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl \
  "$PROJECT_DIR/APP_STORE_HANDOFF_MANIFEST.json" "$PACKAGE_DIR/APP_STORE_HANDOFF_MANIFEST.json"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl \
  "$PROJECT_DIR/LICENSE" "$PACKAGE_DIR/LICENSE"

COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl \
  "$PROJECT_DIR/AppStore/Screenshots/zh-Hans/01-groups.jpg" \
  "$PACKAGE_DIR/evidence/当前分组视图.jpg"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl \
  "$PROJECT_DIR/AppStore/Screenshots/zh-Hans/02-space.jpg" \
  "$PACKAGE_DIR/evidence/当前空间视图.jpg"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl \
  "$PROJECT_DIR/AppStore/Screenshots/zh-Hans/03-all-apps.jpg" \
  "$PACKAGE_DIR/evidence/当前全部应用视图.jpg"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl \
  "$PROJECT_DIR/AppStore/Screenshots/zh-Hans/04-search.jpg" \
  "$PACKAGE_DIR/evidence/当前多实例搜索视图.jpg"

(
  cd "$PACKAGE_DIR"
  /usr/bin/find . -type f ! -path './SHA256SUMS' -print \
    | /usr/bin/sort \
    | while IFS= read -r relative_path; do
        file_hash="$(/usr/bin/shasum -a 256 "$relative_path" | /usr/bin/awk '{print $1}')"
        /usr/bin/printf '%s  %s\n' "$file_hash" "$relative_path"
      done > SHA256SUMS
  /usr/bin/shasum -a 256 -c SHA256SUMS >/dev/null
)

/bin/rm -f "$ZIP_PATH" "$ZIP_SUM_PATH"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --noextattr --noacl --keepParent \
  "$PACKAGE_DIR" "$ZIP_PATH"
ZIP_HASH="$(/usr/bin/shasum -a 256 "$ZIP_PATH" | /usr/bin/awk '{print $1}')"
/usr/bin/printf '%s  %s\n' "$ZIP_HASH" "${ZIP_PATH:t}" > "$ZIP_SUM_PATH"

echo "APP_STORE_HANDOFF_PACKAGE_OK"
echo "ZIP_PATH=$ZIP_PATH"
echo "ZIP_SHA256=$ZIP_HASH"
echo "ZIP_SHA256_FILE=$ZIP_SUM_PATH"
