#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-build}"
case "${BUILD_DIR}" in
    /*) ;;
    *) BUILD_DIR="${PWD}/${BUILD_DIR}" ;;
esac
ISO_PATH="${BUILD_DIR}/AWEOS-x86_64.iso"
BIOS_LOG="${BUILD_DIR}/qemu-bios.log"
UEFI_LOG="${BUILD_DIR}/qemu-uefi.log"
TARGET_MODE="${2:-all}"

test -s "${ISO_PATH}" || {
    echo "ERROR: ISO not found at ${ISO_PATH}" >&2
    exit 1
}

mkdir -p -- "${BUILD_DIR}"

echo "=========================================="
echo "AWEOS QEMU boot verification"
echo "=========================================="

test_boot() {
    local mode="$1"
    local logfile="$2"
    local debuglog="${logfile%.log}-debug.log"
    shift 2

    echo "Testing AWEOS ${mode} boot..."
    rm -f -- "${logfile}" "${debuglog}"

    set +e
    timeout 100s "$@" >"${logfile}" 2>&1
    local rc=$?
    set -e

    cat "${logfile}"

    # timeout(124) is expected because the desktop session is long-running.
    if [ "${rc}" -ne 0 ] && [ "${rc}" -ne 124 ]; then
        echo "FAIL: QEMU exited with status ${rc} during ${mode} boot." >&2
        if [ -s "${debuglog}" ]; then
            echo "--- QEMU guest-error/CPU-reset diagnostics (${debuglog}) ---" >&2
            tail -n 100 "${debuglog}" >&2
        fi
        return 1
    fi

    if ! grep -q "AWEOS BOOT SUCCESS: mode=" "${logfile}"; then
        echo "FAIL: root filesystem never reached its boot hand-off marker in ${mode} mode." >&2
        if [ -s "${logfile}" ]; then
            echo "--- serial output (${logfile}) ---" >&2
            tail -n 120 "${logfile}" >&2
        fi
        if [ -s "${debuglog}" ]; then
            echo "--- QEMU guest-error/CPU-reset diagnostics (${debuglog}) ---" >&2
            tail -n 100 "${debuglog}" >&2
        fi
        return 1
    fi

    if grep -qiE "kernel panic|unable to mount root fs|VFS: Cannot open root device" "${logfile}"; then
        echo "FAIL: kernel/root-filesystem failure detected in ${mode} log." >&2
        return 1
    fi

    if grep -q "AWEOS BOOT SUCCESS: mode=ayui" "${logfile}"; then
        echo "SUCCESS: AWEOS ${mode} boot reached the default AYUI desktop."
    elif grep -q "AWEOS BOOT SUCCESS: mode=gnome" "${logfile}"; then
        echo "SUCCESS: AWEOS ${mode} boot reached the secondary GNOME userspace."
    elif grep -q "AWEUI Compositor initialized successfully" "${logfile}"; then
        echo "SUCCESS: AWEOS ${mode} boot reached the AYUI compositor."
    else
        echo "FAIL: neither GNOME userspace nor AWEUI compositor reached running state in ${mode} mode." >&2
        return 1
    fi
}

if [ "${TARGET_MODE}" = "all" ] || [ "${TARGET_MODE}" = "bios" ]; then
    test_boot "BIOS" "${BIOS_LOG}" \
        qemu-system-x86_64 \
        -machine q35 \
        -m 2048M \
        -boot order=d \
        -cdrom "${ISO_PATH}" \
        -display none \
        -serial stdio \
        -monitor none \
        -no-reboot \
        -d guest_errors,cpu_reset \
        -D "${BUILD_DIR}/qemu-bios-debug.log"
fi

if [ "${TARGET_MODE}" = "all" ] || [ "${TARGET_MODE}" = "uefi" ]; then
    UEFI_FIRMWARE=""
    for candidate in \
        /usr/share/ovmf/OVMF.fd \
        /usr/share/OVMF/OVMF_CODE_4M.fd \
        /usr/share/OVMF/OVMF_CODE.fd; do
        if [ -f "${candidate}" ]; then
            UEFI_FIRMWARE="${candidate}"
            break
        fi
    done

    if [ -n "${UEFI_FIRMWARE}" ]; then
        test_boot "UEFI" "${UEFI_LOG}" \
            qemu-system-x86_64 \
            -machine q35 \
            -m 2048M \
            -boot order=d \
            -bios "${UEFI_FIRMWARE}" \
            -cdrom "${ISO_PATH}" \
            -display none \
            -serial stdio \
            -monitor none \
            -no-reboot \
            -d guest_errors,cpu_reset \
            -D "${BUILD_DIR}/qemu-uefi-debug.log"
    else
        echo "WARNING: OVMF firmware not found; UEFI boot test skipped."
    fi
fi

echo "=========================================="
echo "AWEOS QEMU boot verification completed."
echo "=========================================="
