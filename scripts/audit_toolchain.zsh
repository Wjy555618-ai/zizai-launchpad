#!/bin/zsh

# Shared native toolchain contract for every standalone Swift audit. Audits
# default to the host architecture; callers may request x86_64 on Apple
# Silicon to exercise the Rosetta path explicitly.
ZIZAI_XCRUN_BIN="${ZIZAI_XCRUN_PATH:-/usr/bin/xcrun}"
ZIZAI_SWIFTC="$($ZIZAI_XCRUN_BIN --find swiftc)"
ZIZAI_SDK="$($ZIZAI_XCRUN_BIN --sdk macosx --show-sdk-path)"
ZIZAI_HOST_ARCH="$(/usr/bin/uname -m)"
ZIZAI_AUDIT_ARCH="${ZIZAI_AUDIT_ARCH:-$ZIZAI_HOST_ARCH}"

case "$ZIZAI_AUDIT_ARCH" in
  arm64|x86_64) ;;
  *)
    echo "不支持的审计架构：$ZIZAI_AUDIT_ARCH" >&2
    return 2
    ;;
esac

ZIZAI_AUDIT_TARGET="$ZIZAI_AUDIT_ARCH-apple-macosx13.0"

zizai_run_audit_binary() {
  if [[ "$ZIZAI_AUDIT_ARCH" == "$ZIZAI_HOST_ARCH" ]]; then
    "$@"
  elif [[ "$ZIZAI_HOST_ARCH" == "arm64" && "$ZIZAI_AUDIT_ARCH" == "x86_64" ]]; then
    /usr/bin/arch -x86_64 "$@"
  else
    echo "当前 $ZIZAI_HOST_ARCH 主机无法执行 $ZIZAI_AUDIT_ARCH 审计产物" >&2
    return 126
  fi
}
