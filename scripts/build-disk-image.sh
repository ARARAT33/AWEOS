#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-build}"
case "${BUILD_DIR}" in
    /*) ;;
    *) BUILD_DIR="${PWD}/${BUILD_DIR}" ;;
esac
DISK_IMG="${BUILD_DIR}/AWEOS-x86_64-disk.img"
ROOTFS_IMG="${BUILD_DIR}/rootfs.img"
LIMINE_TOOL="${LIMINE_TOOL:-$(command -v limine || true)}"

test -s "${ROOTFS_IMG}" || { echo "ERROR: ${ROOTFS_IMG} not found or empty" >&2; exit 1; }
test -x "${LIMINE_TOOL}" || { echo "ERROR: executable Limine host utility is required to make the disk image BIOS-bootable" >&2; exit 1; }

ROOTFS_SIZE_BYTES=$(stat -c%s "${ROOTFS_IMG}")
TOTAL_SIZE_MB=$(( (ROOTFS_SIZE_BYTES + (64 * 1024 * 1024)) / 1024 / 1024 ))

mkdir -p -- "${BUILD_DIR}"
TEMP_DIR="$(mktemp -d "${BUILD_DIR}/.aweos-disk-work.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT
DISK_IMG_TMP="${TEMP_DIR}/AWEOS-x86_64-disk.img"

# Build the replacement image in a unique workspace. The previously published
# disk image is not removed unless the new image has passed all final checks.
dd if=/dev/zero of="${DISK_IMG_TMP}" bs=1M count="${TOTAL_SIZE_MB}" status=none

# One MBR partition starts at 1 MiB and contains the already-built ext4 root filesystem.
echo '2048,,L,*' | sfdisk "${DISK_IMG_TMP}" >/dev/null
dd if="${ROOTFS_IMG}" of="${DISK_IMG_TMP}" bs=512 seek=2048 conv=notrunc status=none

"${LIMINE_TOOL}" bios-install "${DISK_IMG_TMP}"
test -s "${DISK_IMG_TMP}"
mv -f -- "${DISK_IMG_TMP}" "${DISK_IMG}"

echo "Bootable AWEOS BIOS disk image created at ${DISK_IMG}"
