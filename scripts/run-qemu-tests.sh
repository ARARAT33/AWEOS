#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build}"
ISO_PATH="${BUILD_DIR}/AWEOS-x86_64.iso"
BIOS_LOG="${BUILD_DIR}/qemu-bios.log"
UEFI_LOG="${BUILD_DIR}/qemu-uefi.log"
TARGET_MODE="${2:-all}"

test -s "${ISO_PATH}" || { echo "ERROR: ISO not found at ${ISO_PATH}" >&2; exit 1; }

echo "=========================================="
echo "AWEOS QEMU boot verification"
echo "=========================================="

test_boot() {
    local mode="$1"
    local logfile="$2"
    shift 2

    echo "Testing AWEOS ${mode} boot..."
    rm -f "${logfile}"

    set +e
    timeout 75s "$@" >"${logfile}" 2>&1
    local rc=$?
    set -e

    cat "${logfile}"

    # timeout(124) is expected because AWEUI is intentionally a long-running compositor.
    if [ "${rc}" -ne 0 ] && [ "${rc}" -ne 124 ]; then
        echo "FAIL: QEMU exited with status ${rc} during ${mode} boot." >&2
        return 1
    fi

    grep -q "AWEOS BOOT SUCCESS: mode=" "${logfile}" || {
        echo "FAIL: root filesystem never reached its boot hand-off marker in ${mode} mode." >&2
        return 1
    }

    if grep -qiE "kernel panic|unable to mount root fs|VFS: Cannot open root device" "${logfile}"; then
        echo "FAIL: kernel/root-filesystem failure detected in ${mode} log." >&2
        return 1
    fi

    grep -q "AWEUI Compositor initialized successfully" "${logfile}" || {
        echo "FAIL: AWEUI compositor did not initialize in ${mode} mode." >&2
        return 1
    }

    echo "SUCCESS: AWEOS ${mode} boot reached the running AWEUI compositor."
}

if [ "${TARGET_MODE}" = "all" ] || [ "${TARGET_MODE}" = "bios" ]; then
    test_boot "BIOS" "${BIOS_LOG}"         qemu-system-x86_64 -machine q35 -m 512M -cdrom "${ISO_PATH}"         -display none -serial stdio -no-reboot
fi

if [ "${TARGET_MODE}" = "all" ] || [ "${TARGET_MODE}" = "uefi" ]; then
    UEFI_FIRMWARE=""
    for candidate in         /usr/share/ovmf/OVMF.fd         /usr/share/OVMF/OVMF_CODE_4M.fd         /usr/share/OVMF/OVMF_CODE.fd; do
        if [ -f "${candidate}" ]; then
            UEFI_FIRMWARE="${candidate}"
            break
        fi
    done

    if [ -n "${UEFI_FIRMWARE}" ]; then
        test_boot "UEFI" "${UEFI_LOG}"             qemu-system-x86_64 -machine q35 -m 512M -bios "${UEFI_FIRMWARE}"             -cdrom "${ISO_PATH}" -display none -serial stdio -no-reboot
    else
        echo "WARNING: OVMF firmware not found; UEFI boot test skipped."
    fi
fi

echo "=========================================="
echo "AWEOS QEMU boot verification completed."
echo "=========================================="
