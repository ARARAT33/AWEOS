#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build}"
ISO_DIR="${BUILD_DIR}/iso"
ISO_OUTPUT="${BUILD_DIR}/AWEOS-x86_64.iso"

echo "Assembling AWEOS x86_64 ISO..."

rm -rf "${ISO_DIR}"
mkdir -p "${ISO_DIR}"/boot "${ISO_DIR}"/EFI/BOOT

# Ensure kernel and initramfs exist
if [ ! -f "${BUILD_DIR}/linux-x86_64/arch/x86/boot/bzImage" ]; then
    echo "Error: bzImage not found in ${BUILD_DIR}/linux-x86_64/arch/x86/boot/bzImage!" >&2
    exit 1
fi

if [ ! -f "${BUILD_DIR}/aweos-initramfs.cpio.gz" ]; then
    echo "Error: initramfs not found in ${BUILD_DIR}/aweos-initramfs.cpio.gz!" >&2
    exit 1
fi

# Copy kernel & initramfs
cp "${BUILD_DIR}/linux-x86_64/arch/x86/boot/bzImage" "${ISO_DIR}/boot/bzImage"
cp "${BUILD_DIR}/aweos-initramfs.cpio.gz" "${ISO_DIR}/boot/aweos-initramfs.cpio.gz"

# Copy Limine bootloader binaries from Bootloader/x86_64/
cp Bootloader/x86_64/limine-bios.sys "${ISO_DIR}/boot/"
cp Bootloader/x86_64/limine-bios-cd.bin "${ISO_DIR}/"
cp Bootloader/x86_64/limine-uefi-cd.bin "${ISO_DIR}/"
cp Bootloader/x86_64/BOOTX64.EFI "${ISO_DIR}/EFI/BOOT/"
cp Bootloader/x86_64/limine.conf "${ISO_DIR}/"
cp Bootloader/x86_64/limine.conf "${ISO_DIR}/boot/"

# Build hybrid ISO using xorriso
xorriso -as mkisofs \
    -b limine-bios-cd.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --efi-boot limine-uefi-cd.bin \
    -efi-boot-part \
    --efi-boot-image \
    -iso-level 3 \
    -V "AWEOS" \
    -o "${ISO_OUTPUT}" \
    "${ISO_DIR}"

echo "ISO successfully built at ${ISO_OUTPUT}"
