#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
source "$SCRIPT_DIR/lib/build-safety.sh"

BUILD_DIR="$(aweos_prepare_build_dir "${1:-build}" "$REPO_ROOT")"
DISK_IMG="$BUILD_DIR/AWEOS-x86_64-disk.img"
ROOTFS_IMG="$BUILD_DIR/rootfs.img"
LIMINE_TOOL="${LIMINE_TOOL:-$(command -v limine || true)}"

[[ -f "$ROOTFS_IMG" && ! -L "$ROOTFS_IMG" ]] || {
    echo "ERROR: a regular, non-symlink rootfs image is required at $ROOTFS_IMG" >&2
    exit 1
}
test -n "$LIMINE_TOOL" || {
    echo "ERROR: limine host utility is required to make the disk image BIOS-bootable" >&2
    exit 1
}
if [[ -e "$DISK_IMG" || -L "$DISK_IMG" ]]; then
    [[ -f "$DISK_IMG" && ! -L "$DISK_IMG" ]] || {
        echo "ERROR: refusing to replace a non-regular or symlink disk-image destination: $DISK_IMG" >&2
        exit 1
    }
fi

ROOTFS_SIZE_BYTES="$(stat -c%s "$ROOTFS_IMG")"
TOTAL_SIZE_MB=$(( (ROOTFS_SIZE_BYTES + (64 * 1024 * 1024)) / 1024 / 1024 ))

# Keep the previous image intact until partitioning, copying, and Limine all
# succeed. The temporary image lives on the same filesystem for atomic rename.
TEMP_ROOT="$(mktemp -d "$BUILD_DIR/.aweos-disk-image.XXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT
DISK_IMG_TMP="$TEMP_ROOT/AWEOS-x86_64-disk.img"

dd if=/dev/zero of="$DISK_IMG_TMP" bs=1M count="$TOTAL_SIZE_MB" status=none

# One MBR partition starts at 1 MiB and contains the already-built ext4 root filesystem.
echo '2048,,L,*' | sfdisk "$DISK_IMG_TMP" >/dev/null
dd if="$ROOTFS_IMG" of="$DISK_IMG_TMP" bs=512 seek=2048 conv=notrunc status=none

"$LIMINE_TOOL" bios-install "$DISK_IMG_TMP"
test -s "$DISK_IMG_TMP"
mv -f -- "$DISK_IMG_TMP" "$DISK_IMG"
echo "Bootable AWEOS BIOS disk image created at $DISK_IMG"
