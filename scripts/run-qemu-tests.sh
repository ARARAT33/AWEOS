#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build}"
ISO_PATH="${BUILD_DIR}/AWEOS-x86_64.iso"
BIOS_LOG="${BUILD_DIR}/qemu-bios.log"
UEFI_LOG="${BUILD_DIR}/qemu-uefi.log"

if [ ! -f "${ISO_PATH}" ]; then
    echo "Error: ISO not found at ${ISO_PATH}" >&2
    exit 1
fi

echo "=========================================="
echo "Starting AWEOS QEMU Boot Verification"
echo "=========================================="

test_boot() {
    local mode="$1"
    local logfile="$2"
    shift 2
    local qemu_cmd=("$@")

    echo "Testing AWEOS QEMU ${mode} Boot..."
    rm -f "${logfile}"

    set +e
    timeout 90s "${qemu_cmd[@]}" > "${logfile}" 2>&1
    local rc=$?
    set -e

    echo "--- ${mode} Boot Output ---"
    cat "${logfile}"
    echo "---------------------------"

    if ! grep -q "AWEOS BOOT SUCCESS" "${logfile}"; then
        echo "FAIL: 'AWEOS BOOT SUCCESS' marker missing in ${mode} boot output!" >&2
        return 1
    fi

    if ! grep -q "AWEOS TERMINAL READY" "${logfile}"; then
        echo "FAIL: 'AWEOS TERMINAL READY' marker missing in ${mode} boot output!" >&2
        return 1
    fi

    if grep -q "Kernel panic" "${logfile}"; then
        echo "FAIL: Kernel panic detected in ${mode} boot log!" >&2
        return 1
    fi

    echo "SUCCESS: AWEOS ${mode} Boot test passed!"
    return 0
}

# 1. QEMU BIOS Boot Test
test_boot "BIOS" "${BIOS_LOG}" qemu-system-x86_64 -machine q35 -m 512M -cdrom "${ISO_PATH}" -display none -serial stdio -no-reboot

# 2. QEMU UEFI Boot Test
UEFI_FIRMWARE=""
if [ -f /usr/share/ovmf/OVMF.fd ]; then
    UEFI_FIRMWARE=/usr/share/ovmf/OVMF.fd
elif [ -f /usr/share/OVMF/OVMF_CODE_4M.fd ]; then
    UEFI_FIRMWARE=/usr/share/OVMF/OVMF_CODE_4M.fd
elif [ -f /usr/share/OVMF/OVMF_CODE.fd ]; then
    UEFI_FIRMWARE=/usr/share/OVMF/OVMF_CODE.fd
fi

if [ -n "${UEFI_FIRMWARE}" ]; then
    test_boot "UEFI" "${UEFI_LOG}" qemu-system-x86_64 -machine q35 -m 512M -bios "${UEFI_FIRMWARE}" -cdrom "${ISO_PATH}" -display none -serial stdio -no-reboot
else
    echo "WARNING: OVMF firmware not found, skipping UEFI test in current environment."
fi

echo "=========================================="
echo "All AWEOS Boot Tests PASSED Successfully!"
echo "=========================================="
