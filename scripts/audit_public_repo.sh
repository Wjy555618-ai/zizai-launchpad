#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

required_files=(
  README.md README_EN.md LICENSE CONTRIBUTING.md CODE_OF_CONDUCT.md
  SECURITY.md SUPPORT.md CHANGELOG.md ARCHITECTURE.md QUALITY_REPORT.md
  CURRENT_PRODUCT_BASELINE.md PRIVACY_POLICY_ZH.md RELEASE_READINESS.md
  APP_STORE_METADATA_ZH.md
  .github/workflows/quality.yml .gitignore .gitattributes
)

# Superseded local installers and parallel "current" screenshots created the
# exact kind of split truth this audit is meant to prevent. They are rejected
# even when someone tries to hide them behind .gitignore: the public source,
# App Store assets, and release handoff must all derive from one maintained
# evidence surface.
for obsolete_path in \
  START_HERE.md \
  RELEASE_MANIFEST.json \
  scripts/package_codex_installer.sh \
  scripts/verify_codex_installer.sh \
  handoff/evidence/after/final-groups-current.png \
  handoff/evidence/after/final-space-current.png; do
  [[ ! -e "$obsolete_path" ]] || {
    echo "公开仓库存在已废弃的平行交付或视觉事实源：$obsolete_path" >&2
    exit 1
  }
done

for required_file in "${required_files[@]}"; do
  [[ -s "$required_file" ]] || {
    echo "公开仓库缺少必要文件：$required_file" >&2
    exit 1
  }
done

CANDIDATES_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/zizai-public-files.XXXXXX")"
cleanup() { /bin/rm -f "$CANDIDATES_FILE"; }
trap cleanup EXIT

/usr/bin/git ls-files --cached --others --exclude-standard -z > "$CANDIDATES_FILE"
[[ -s "$CANDIDATES_FILE" ]] || {
  echo "公开仓库候选集为空" >&2
  exit 1
}

while IFS= read -r -d '' path; do
  [[ -e "$path" ]] || continue
  case "$path" in
    *.app/*|*.xcresult/*|*.xcarchive/*|DerivedData/*|build/*|.artifacts.noindex/*|*.p12|*.cer|*.key|*.mobileprovision|*.provisionprofile)
      echo "公开候选集包含构建物或敏感签名材料：$path" >&2
      exit 1
      ;;
  esac
  if [[ -f "$path" && "$(/usr/bin/stat -f %z "$path")" -gt 10485760 ]]; then
    echo "公开候选文件超过 10 MiB，请确认是否应由 Git LFS 管理：$path" >&2
    exit 1
  fi
done < "$CANDIDATES_FILE"

if /usr/bin/xargs -0 /usr/bin/grep -IlZ '' < "$CANDIDATES_FILE" 2>/dev/null \
  | /usr/bin/xargs -0 /usr/bin/grep -nE \
    '(/Users/[A-Za-z0-9._-]+/|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})' \
    >/dev/null 2>&1; then
  echo "公开候选集发现个人绝对路径、私钥或常见凭据格式" >&2
  exit 1
fi

if /usr/bin/xargs -0 /usr/bin/grep -IlZ '' < "$CANDIDATES_FILE" 2>/dev/null \
  | /usr/bin/xargs -0 /usr/bin/grep -nE '[[:blank:]]+$' >/dev/null 2>&1; then
  echo "公开候选集存在行尾空白" >&2
  exit 1
fi

/usr/bin/plutil -lint Resources/Info.plist Resources/PrivacyInfo.xcprivacy Resources/ZizaiLaunchpad.entitlements >/dev/null
/usr/bin/python3 scripts/verify_security_capabilities.py
/usr/bin/python3 -m json.tool APP_STORE_HANDOFF_MANIFEST.json >/dev/null
/usr/bin/python3 scripts/verify_product_truth.py
/usr/bin/python3 scripts/verify_documentation.py

if /usr/bin/grep -R -nE --include='*.swift' \
  '(TODO|FIXME|HACK|XXX)|try!|as!|unsafeBitCast' Sources Tests >/dev/null; then
  echo "产品源码或测试中存在未收敛标记或高风险强制操作" >&2
  /usr/bin/grep -R -nE --include='*.swift' \
    '(TODO|FIXME|HACK|XXX)|try!|as!|unsafeBitCast' Sources Tests >&2
  exit 1
fi

/usr/bin/xcrun swift-format lint --strict --recursive Sources Tests

echo "公开仓库候选审计通过：事实源、文档链接、许可证、工作流、格式、代码边界、敏感信息和构建物边界均有效。"
echo "注意：本地审计不等于 GitHub 远端 CI 已通过；首次提交与远程仓库必须使用项目所有者身份。"
