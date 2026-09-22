#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build}"
DISK_IMG="${BUILD_DIR}/AWEOS-x86_64-disk.img"
ROOTFS_IMG="${BUILD_DIR}/rootfs.img"
LIMINE_TOOL="${LIMINE_TOOL:-$(command -v limine || true)}"

test -f "${ROOTFS_IMG}" || { echo "ERROR: ${ROOTFS_IMG} not found" >&2; exit 1; }
test -n "${LIMINE_TOOL}" || { echo "ERROR: limine host utility is required to make the disk image BIOS-bootable" >&2; exit 1; }

ROOTFS_SIZE_BYTES=$(stat -c%s "${ROOTFS_IMG}")
TOTAL_SIZE_MB=$(( (ROOTFS_SIZE_BYTES + (64 * 1024 * 1024)) / 1024 / 1024 ))

rm -f "${DISK_IMG}"
dd if=/dev/zero of="${DISK_IMG}" bs=1M count="${TOTAL_SIZE_MB}" status=none

# One MBR partition starts at 1 MiB and contains the already-built ext4 root filesystem.
echo '2048,,L,*' | sfdisk "${DISK_IMG}" >/dev/null
dd if="${ROOTFS_IMG}" of="${DISK_IMG}" bs=512 seek=2048 conv=notrunc status=none

"${LIMINE_TOOL}" bios-install "${DISK_IMG}"

test -s "${DISK_IMG}"
echo "Bootable AWEOS BIOS disk image created at ${DISK_IMG}"
