#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build}"
ISO_DIR="${BUILD_DIR}/iso"
ISO_OUTPUT="${BUILD_DIR}/AWEOS-x86_64.iso"
LIMINE_TOOL="${LIMINE_TOOL:-$(command -v limine || true)}"

echo "Assembling AWEOS x86_64 hybrid ISO..."

test -x "${LIMINE_TOOL}" || { echo "ERROR: limine host utility is required to create a bootable hybrid ISO" >&2; exit 1; }
test -s "${BUILD_DIR}/linux-x86_64/arch/x86/boot/bzImage" || { echo "ERROR: bzImage missing" >&2; exit 1; }
test -s "${BUILD_DIR}/aweos-initramfs.cpio.gz" || { echo "ERROR: initramfs missing" >&2; exit 1; }
test -s "${BUILD_DIR}/rootfs.img" || { echo "ERROR: rootfs.img missing" >&2; exit 1; }

rm -rf "${ISO_DIR}"
mkdir -p "${ISO_DIR}/boot" "${ISO_DIR}/EFI/BOOT"

cp "${BUILD_DIR}/linux-x86_64/arch/x86/boot/bzImage" "${ISO_DIR}/boot/bzImage"
cp "${BUILD_DIR}/aweos-initramfs.cpio.gz" "${ISO_DIR}/boot/aweos-initramfs.cpio.gz"
cp "${BUILD_DIR}/rootfs.img" "${ISO_DIR}/boot/rootfs.img"
cp Bootloader/x86_64/limine-bios.sys "${ISO_DIR}/boot/limine-bios.sys"
cp Bootloader/x86_64/limine-bios-cd.bin "${ISO_DIR}/limine-bios-cd.bin"
cp Bootloader/x86_64/limine-uefi-cd.bin "${ISO_DIR}/limine-uefi-cd.bin"
cp Bootloader/x86_64/BOOTX64.EFI "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI"
cp Bootloader/x86_64/limine.conf "${ISO_DIR}/limine.conf"

xorriso -as mkisofs     -R -r -J     -b limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table     -hfsplus -apm-block-size 2048     --efi-boot limine-uefi-cd.bin -efi-boot-part -efi-boot-image     --protective-msdos-label     "${ISO_DIR}" -o "${ISO_OUTPUT}"

"${LIMINE_TOOL}" bios-install "${ISO_OUTPUT}"
test -s "${ISO_OUTPUT}"
echo "Bootable AWEOS BIOS/UEFI hybrid ISO created at ${ISO_OUTPUT}"
