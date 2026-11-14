#!/usr/bin/env bash
# Regression: the BusyBox bootstrap must compile against sanitized UAPI
# headers installed from the vendored kernel tree, not the raw kernel
# include/uapi files. The raw headers keep __user annotations and include
# kernel-internal headers, which fail under musl-gcc's -nostdinc; only the
# `make headers_install` export is userspace-safe.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
BUILD_SCRIPT="$SCRIPT_DIR/build-busybox-baseline.sh"
# shellcheck source=lib/install-uapi-headers.sh
source "$SCRIPT_DIR/lib/install-uapi-headers.sh"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

# 1. Static contract: the production build must install the sanitized
#    headers and must not consume the raw kernel uapi trees directly.
grep -q 'aweos_install_uapi_headers' "$BUILD_SCRIPT" ||
    fail "build-busybox-baseline.sh does not install sanitized UAPI headers."
if grep -q 'REPO_ROOT/linux/include/uapi' "$BUILD_SCRIPT"; then
    fail "build-busybox-baseline.sh still consumes raw kernel uapi headers, which are not userspace-safe under -nostdinc."
fi

# 2. Functional: install the sanitized headers for real and run the same
#    probe compilation the production build performs before BusyBox.
command -v cc >/dev/null 2>&1 || fail "a host C compiler (cc) is required."
[ -f "$REPO_ROOT/linux/Makefile" ] || fail "the vendored kernel tree is missing."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aweos-uapi-test.XXXXXX")"
cleanup() { rm -rf -- "$WORK"; }
trap cleanup EXIT

PREFIX="$WORK/tools/uapi"
aweos_install_uapi_headers "$REPO_ROOT/linux" "$WORK/linux-uapi-build" \
    "$PREFIX" "$WORK/headers-install.log" ||
    fail "sanitized UAPI header installation failed."

KD_H="$PREFIX/include/linux/kd.h"
[ -f "$KD_H" ] || fail "sanitized UAPI install did not provide include/linux/kd.h."
if grep -q '__user' "$KD_H"; then
    fail "sanitized linux/kd.h still contains __user annotations; headers_install did not sanitize."
fi

if ! printf '#include <linux/kd.h>\n' |
    cc -nostdinc -idirafter "$PREFIX/include" \
        -x c -fsyntax-only - >"$WORK/probe-error.txt" 2>&1; then
    sed -n '1,20p' "$WORK/probe-error.txt" | sed 's/^/ERROR: probe: /' >&2 || true
    fail "the sanitized UAPI prefix did not satisfy the <linux/kd.h> probe under -nostdinc."
fi

echo "PASS: sanitized UAPI headers are self-contained and satisfy the <linux/kd.h> probe."
