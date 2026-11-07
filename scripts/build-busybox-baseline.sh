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

for tool in curl sha256sum tar make musl-gcc readelf; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: $tool is required to build the baseline BusyBox." >&2
        exit 2
    }
done

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
if grep -q '^# CONFIG_STATIC is not set$' "$SOURCE_DIR/.config"; then
    sed -i 's/^# CONFIG_STATIC is not set$/CONFIG_STATIC=y/' "$SOURCE_DIR/.config"
elif grep -q '^CONFIG_STATIC=' "$SOURCE_DIR/.config"; then
    sed -i 's/^CONFIG_STATIC=.*/CONFIG_STATIC=y/' "$SOURCE_DIR/.config"
else
    printf '\nCONFIG_STATIC=y\n' >> "$SOURCE_DIR/.config"
fi
grep -qx 'CONFIG_STATIC=y' "$SOURCE_DIR/.config" || {
    echo "ERROR: BusyBox static linking could not be enabled." >&2
    exit 1
}

jobs="${AWEOS_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2')}"
case "$jobs" in
    ''|*[!0-9]*) jobs=2 ;;
esac
[ "$jobs" -gt 0 ] || jobs=2
compiler="musl-gcc -march=x86-64 -mtune=generic -mno-avx -mno-avx2 -mno-bmi -mno-bmi2"

echo "Building static BusyBox with an explicit x86-64 baseline compiler target..."
make -C "$SOURCE_DIR" -j"$jobs" \
    HOSTCC="${HOSTCC:-cc}" \
    CC="$compiler" \
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
