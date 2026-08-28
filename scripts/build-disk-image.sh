#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build}"
DISK_IMG="${BUILD_DIR}/AWEOS-x86_64-disk.img"
ROOTFS_IMG="${BUILD_DIR}/rootfs.img"
KERNEL_IMG="${BUILD_DIR}/linux-x86_64/arch/x86/boot/bzImage"
INITRAMFS_IMG="${BUILD_DIR}/aweos-initramfs.cpio.gz"

echo "Building raw AWEOS bootable disk/USB image at ${DISK_IMG}..."

if [ ! -f "${ROOTFS_IMG}" ]; then
    echo "Error: ${ROOTFS_IMG} not found!" >&2
    exit 1
fi

# Size: Rootfs size + 32MB for boot files/structures
ROOTFS_SIZE_BYTES=$(stat -c%s "${ROOTFS_IMG}")
TOTAL_SIZE_MB=$(( (ROOTFS_SIZE_BYTES / 1024 / 1024) + 32 ))

rm -f "${DISK_IMG}"
dd if=/dev/zero of="${DISK_IMG}" bs=1M count="${TOTAL_SIZE_MB}" status=none

# Create MBR partition table with primary bootable ext4 partition starting at sector 2048 (1MB)
echo '2048,,L,*' | sfdisk "${DISK_IMG}" >/dev/null 2>&1

PART_OFFSET_BYTES=$(( 2048 * 512 ))
dd if="${ROOTFS_IMG}" of="${DISK_IMG}" bs=512 seek=2048 conv=notrunc status=none

echo "Raw bootable disk image created successfully at ${DISK_IMG}"
