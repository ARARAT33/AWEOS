#!/usr/bin/env bash
# Build the initramfs/rootfs BusyBox ourselves instead of copying the host
# distribution binary, which may be an amd64v3/AVX-optimized package.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
source "$SCRIPT_DIR/lib/build-safety.sh"

BUILD_DIR="$(aweos_prepare_build_dir "${1:-build}" "$REPO_ROOT")"
VERSION="1.38.0"
ARCHIVE="busybox-${VERSION}.tar.bz2"
URL="https://busybox.net/downloads/${ARCHIVE}"
# Pinned upstream tarball digest (also recorded by Buildroot's BusyBox recipe).
SHA256="34f9ea6ff8636f2c9241153b9114eefa9e65674a45318ae1ef95bb5f31c53bb2"

MUSL_CC="${MUSL_CC:-musl-gcc}"
for tool in curl sha256sum tar make readelf; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: $tool is required to build the baseline BusyBox." >&2
        exit 2
    }
done
command -v "$MUSL_CC" >/dev/null 2>&1 || {
    echo "ERROR: $MUSL_CC is required to build the baseline BusyBox." >&2
    exit 2
}

# BusyBox's default console-tools configuration builds kbd_mode, which
# includes <linux/kd.h>. musl provides libc headers but not the Linux UAPI
# development headers. Check this before downloading and compiling BusyBox so
# a missing linux-libc-dev package produces an actionable error.
# musl-gcc uses -nostdinc, so distro UAPI headers are not searched by
# default. Add them after musl's own headers to avoid mixing glibc headers
# into the target's libc include chain.
UAPI_INCLUDE_FLAGS=(-idirafter /usr/include -idirafter /usr/include/x86_64-linux-gnu)
if ! printf '#include <linux/kd.h>\n' |
    AWEOS_MUSL_CC="$MUSL_CC" bash "$SCRIPT_DIR/cc-x86_64-baseline.sh" \
        "${UAPI_INCLUDE_FLAGS[@]}" -x c -fsyntax-only - >/dev/null 2>&1; then
    echo "ERROR: Linux UAPI header <linux/kd.h> is unavailable to musl-gcc even with explicit UAPI include paths; install linux-libc-dev and verify the system UAPI headers." >&2
    exit 2
fi

# Verify the real compiler's effective target state, not just the wrapper's
# argument ordering. This catches a toolchain/specs mismatch before compiling
# the bootstrap binary.
TARGET_REPORT="$BUILD_DIR/busybox-compiler-target-report.txt"
AWEOS_MUSL_CC="$MUSL_CC" bash "$SCRIPT_DIR/cc-x86_64-baseline.sh" \
    -Q --help=target > "$TARGET_REPORT"
for option in -mavx -mavx2 -mavx512f -mbmi -mbmi2 -mmovbe \
              -mpopcnt -mlzcnt -msse3 -mssse3 -msse4.1 -msse4.2 \
              -maes -mpclmul -mrdrnd -mrdseed -madx; do
    if ! awk -v wanted="$option" \
        '$1 == wanted && $2 == "[disabled]" { found = 1 } END { exit !found }' \
        "$TARGET_REPORT"; then
        echo "ERROR: compiler target policy did not disable $option." >&2
        grep -E "^[[:space:]]*$option[[:space:]]" "$TARGET_REPORT" >&2 || true
        exit 2
    fi
done
awk '$1 == "-msse2" && $2 == "[enabled]" { found = 1 } END { exit !found }' \
    "$TARGET_REPORT" || {
    echo "ERROR: compiler target policy does not retain baseline SSE2." >&2
    exit 2
}
echo "Effective BusyBox compiler target policy:"
grep -E '^[[:space:]]+-(mavx|mavx2|mavx512f|mbmi|mbmi2|mmovbe|mpopcnt|mlzcnt|msse2|msse3|mssse3|msse4\.1|msse4\.2|maes|mpclmul|mrdrnd|mrdseed|madx)[[:space:]]' \
    "$TARGET_REPORT" || true
echo "PASS: the actual BusyBox compiler reports the required x86-64 baseline."

WORK_DIR="$(mktemp -d "$BUILD_DIR/.busybox-build.XXXXXX")"
TOOLS_DIR="$BUILD_DIR/tools"
OUTPUT="$TOOLS_DIR/busybox"
OUTPUT_TMP=""
CHECKSUM_TMP=""
cleanup() {
    rm -rf -- "$WORK_DIR"
    [ -z "$OUTPUT_TMP" ] || rm -f -- "$OUTPUT_TMP"
    [ -z "$CHECKSUM_TMP" ] || rm -f -- "$CHECKSUM_TMP"
}
trap cleanup EXIT

mkdir -p "$TOOLS_DIR"
TARBALL="$WORK_DIR/$ARCHIVE"

echo "Downloading pinned BusyBox $VERSION source..."
curl --fail --location --retry 3 --retry-all-errors --proto '=https' --tlsv1.2 \
    "$URL" -o "$TARBALL"
printf '%s  %s\n' "$SHA256" "$TARBALL" | sha256sum --check --status || {
    echo "ERROR: BusyBox source archive SHA-256 mismatch." >&2
    exit 1
}

tar -xjf "$TARBALL" -C "$WORK_DIR" --no-same-owner --no-same-permissions
SOURCE_DIR="$WORK_DIR/busybox-$VERSION"
[ -d "$SOURCE_DIR" ] || {
    echo "ERROR: BusyBox source directory is missing after extraction." >&2
    exit 1
}

make -C "$SOURCE_DIR" defconfig
bash "$SCRIPT_DIR/configure-busybox-baseline.sh" "$SOURCE_DIR"

jobs="${AWEOS_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2')}"
case "$jobs" in
    ''|*[!0-9]*) jobs=2 ;;
esac
[ "$jobs" -gt 0 ] || jobs=2
echo "Building static BusyBox with the enforced x86-64-v1 compiler policy..."
AWEOS_MUSL_CC="$MUSL_CC" make -C "$SOURCE_DIR" -j"$jobs" \
    HOSTCC="${HOSTCC:-cc}" \
    CC="bash $SCRIPT_DIR/cc-x86_64-baseline.sh ${UAPI_INCLUDE_FLAGS[*]}" \
    busybox

BUILT="$SOURCE_DIR/busybox"
[ -x "$BUILT" ] || {
    echo "ERROR: BusyBox build did not produce an executable." >&2
    exit 1
}
if readelf -l "$BUILT" 2>/dev/null | grep -q 'INTERP'; then
    echo "ERROR: BusyBox is dynamically linked; the bootstrap binary must be static." >&2
    exit 1
fi

required_applets=(
    awk cat chmod cp cttyhack dd find grep hostname ln mkdir mktemp mknod
    mount mv rm rmdir sed sha256sum sh sleep sort switch_root tar tr umount wc
)
applets="$("$BUILT" --list)"
for applet in "${required_applets[@]}"; do
    printf '%s\n' "$applets" | grep -Fxq "$applet" || {
        echo "ERROR: baseline BusyBox is missing required applet: $applet" >&2
        exit 1
    }
done

bash "$SCRIPT_DIR/check-qemu64-baseline-isa.sh" "$BUILT"

OUTPUT_TMP="$(mktemp "$TOOLS_DIR/.busybox.XXXXXX")"
CHECKSUM_TMP="$(mktemp "$TOOLS_DIR/.busybox.sha256.XXXXXX")"
install -m 0755 "$BUILT" "$OUTPUT_TMP"
sha256sum "$OUTPUT_TMP" > "$CHECKSUM_TMP"
mv -f -- "$OUTPUT_TMP" "$OUTPUT"
OUTPUT_TMP=""
mv -f -- "$CHECKSUM_TMP" "$OUTPUT.sha256"
CHECKSUM_TMP=""

echo "PASS: baseline static BusyBox $VERSION published at $OUTPUT"
