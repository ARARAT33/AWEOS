#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-build}"
mkdir -p -- "$BUILD_DIR"
BUILD_DIR="$(cd -- "$BUILD_DIR" && pwd -P)"
REPO_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

if [[ "$BUILD_DIR" == "/" || "$BUILD_DIR" == "$REPO_ROOT" ]]; then
    echo "ERROR: refusing to use the filesystem root or repository root as BUILD_DIR: $BUILD_DIR" >&2
    exit 1
fi

OUTPUT_CPIO="$BUILD_DIR/aweos-initramfs.cpio.gz"
INIT_SCRIPT="$REPO_ROOT/scripts/aweos-initramfs-init.sh"
TMP_ROOT="$(mktemp -d "$BUILD_DIR/.aweos-initramfs.XXXXXX")"
trap 'rm -rf -- "$TMP_ROOT"' EXIT
INITRAMFS_DIR="$TMP_ROOT/initramfs"
OUTPUT_CPIO_TMP="$TMP_ROOT/aweos-initramfs.cpio.gz"

echo "Building AWEOS bootstrap initramfs in a private staging directory..."

test -s "$INIT_SCRIPT" || {
    echo "ERROR: initramfs init script is missing: $INIT_SCRIPT" >&2
    exit 1
}
BUSYBOX_BIN="$(command -v busybox || true)"
if [[ -z "$BUSYBOX_BIN" ]]; then
    echo "ERROR: busybox binary not found!" >&2
    exit 1
fi
command -v cpio >/dev/null 2>&1 || {
    echo "ERROR: cpio is required to build the initramfs." >&2
    exit 1
}
command -v gzip >/dev/null 2>&1 || {
    echo "ERROR: gzip is required to build the initramfs." >&2
    exit 1
}
command -v readelf >/dev/null 2>&1 || {
    echo "ERROR: readelf is required to inspect BusyBox runtime dependencies." >&2
    exit 1
}

mkdir -p "$INITRAMFS_DIR"/{bin,sbin,usr/bin,usr/sbin,dev,proc,sys,run,tmp,etc,mnt/rootfs,mnt/boot}
install -m 0755 "$BUSYBOX_BIN" "$INITRAMFS_DIR/bin/busybox"
install -m 0755 "$INIT_SCRIPT" "$INITRAMFS_DIR/init"

# Copy the dynamic loader and libraries required by the selected BusyBox binary.
interpreter="$(readelf -l "$BUSYBOX_BIN" 2>/dev/null |
    sed -n 's/.*Requesting program interpreter: \\(.*\\)]/\\1/p' | head -n 1)"
if [[ -n "$interpreter" ]]; then
    [[ -f "$interpreter" ]] || {
        echo "ERROR: BusyBox ELF interpreter is missing: $interpreter" >&2
        exit 1
    }
    install -D -m 0755 "$interpreter" "$INITRAMFS_DIR$interpreter"
    if command -v ldd >/dev/null 2>&1; then
        ldd "$BUSYBOX_BIN" 2>/dev/null |
            awk '/=> \\// {print $3} /^\\// {print $1}' |
            while IFS= read -r library; do
                [[ -f "$library" ]] || continue
                install -D -m 0644 "$library" "$INITRAMFS_DIR$library"
            done
    fi
fi

(
    cd "$INITRAMFS_DIR"
    while IFS= read -r applet; do
        [[ -n "$applet" ]] || continue
        target="bin/$applet"
        [[ -e "$target" ]] || ln -s /bin/busybox "$target"
    done < <(./bin/busybox --list)
)

chmod 0755 "$INITRAMFS_DIR/init"
(
    cd "$INITRAMFS_DIR"
    find . -print0 | cpio --null -o --format=newc | gzip -9
) > "$OUTPUT_CPIO_TMP"

test -s "$OUTPUT_CPIO_TMP"
# Publish only after the complete archive has been created successfully.
# The previous initramfs remains intact if any earlier step fails.
mv -f -- "$OUTPUT_CPIO_TMP" "$OUTPUT_CPIO"
echo "Bootstrap initramfs created successfully at $OUTPUT_CPIO"
