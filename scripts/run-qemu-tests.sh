#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build}"
ISO_PATH="${BUILD_DIR}/AWEOS-x86_64.iso"
BIOS_LOG="${BUILD_DIR}/qemu-bios.log"
UEFI_LOG="${BUILD_DIR}/qemu-uefi.log"
TARGET_MODE="${2:-all}"

case "${TARGET_MODE}" in
    all|bios|uefi) ;;
    *) echo "ERROR: unsupported QEMU target mode: ${TARGET_MODE}" >&2; exit 2 ;;
esac

test -s "${ISO_PATH}" || { echo "ERROR: ISO not found at ${ISO_PATH}" >&2; exit 1; }

echo "=========================================="
echo "AWEOS QEMU boot verification"
echo "=========================================="

# Emit the last serial-log lines as GitHub error annotations so the concrete
# failure is readable on the workflow run page without an authenticated session.
annotate_log_tail() {
    local logfile="$1" label="$2"
    [ -f "${logfile}" ] || return 0
    tail -n 8 "${logfile}" | while IFS= read -r line; do
        [ -n "${line}" ] || continue
        echo "::error::AWEOS ${label} boot serial tail: ${line}"
    done
}

test_boot() {
    local mode="$1"
    local logfile="$2"
    shift 2

    echo "Testing AWEOS ${mode} boot..."
    rm -f "${logfile}"

    set +e
    timeout 100s "$@" >"${logfile}" 2>&1
    local rc=$?
    set -e

    cat "${logfile}"

    # timeout(124) is expected because AWEUI is intentionally a long-running compositor.
    if [ "${rc}" -ne 0 ] && [ "${rc}" -ne 124 ]; then
        echo "FAIL: QEMU exited with status ${rc} during ${mode} boot." >&2
        annotate_log_tail "${logfile}" "${mode}"
        return 1
    fi

    grep -q "AWEOS ROOTFS READY: mode=" "${logfile}" || {
        echo "FAIL: root filesystem did not reach its init hand-off marker in ${mode} mode." >&2
        annotate_log_tail "${logfile}" "${mode}"
        return 1
    }

    if grep -qiE "kernel panic|unable to mount root fs|VFS: Cannot open root device" "${logfile}"; then
        echo "FAIL: kernel/root-filesystem failure detected in ${mode} log." >&2
        annotate_log_tail "${logfile}" "${mode}"
        return 1
    fi

    # Rootfs init is only the hand-off. Do not call that a desktop boot: the
    # AYUI compositor must initialize its backend and submit its first frame.
    if grep -q "AWEOS COMPOSITOR READY: session=ayui backend=winit first-frame=1" "${logfile}" ||
       grep -q "AYUI DESKTOP READY" "${logfile}"; then
        echo "SUCCESS: AWEOS ${mode} boot reached a running AYUI compositor."
    else
        echo "FAIL: AYUI compositor did not submit its first frame in ${mode} mode; rootfs hand-off alone is not desktop readiness." >&2
        annotate_log_tail "${logfile}" "${mode}"
        return 1
    fi
}

if [ "${TARGET_MODE}" = "all" ] || [ "${TARGET_MODE}" = "bios" ]; then
    test_boot "BIOS" "${BIOS_LOG}"         qemu-system-x86_64 -machine q35 -m 2048M -cdrom "${ISO_PATH}"         -display none -serial stdio -no-reboot
fi

if [ "${TARGET_MODE}" = "all" ] || [ "${TARGET_MODE}" = "uefi" ]; then
    UEFI_FIRMWARE="${AWEOS_OVMF_FIRMWARE:-}"
    if [ -z "${UEFI_FIRMWARE}" ]; then
        for candidate in \
            /usr/share/ovmf/OVMF.fd \
            /usr/share/OVMF/OVMF_CODE_4M.fd \
            /usr/share/OVMF/OVMF_CODE.fd; do
            if [ -f "${candidate}" ]; then
                UEFI_FIRMWARE="${candidate}"
                break
            fi
        done
    fi

    if [ -n "${UEFI_FIRMWARE}" ] && [ -f "${UEFI_FIRMWARE}" ]; then
        test_boot "UEFI" "${UEFI_LOG}" \
            qemu-system-x86_64 -machine q35 -m 2048M -bios "${UEFI_FIRMWARE}" \
            -cdrom "${ISO_PATH}" -display none -serial stdio -no-reboot
    else
        echo "ERROR: OVMF firmware not found; UEFI boot test is required." >&2
        exit 1
    fi
fi

echo "=========================================="
echo "AWEOS QEMU boot verification completed."
echo "=========================================="
