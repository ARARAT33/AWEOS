#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-build}"
case "${BUILD_DIR}" in
    /*) ;;
    *) BUILD_DIR="${PWD}/${BUILD_DIR}" ;;
esac
ISO_PATH="${BUILD_DIR}/AWEOS-x86_64.iso"
KERNEL_PATH="${BUILD_DIR}/linux-x86_64/arch/x86/boot/bzImage"
INITRAMFS_PATH="${BUILD_DIR}/aweos-initramfs.cpio.gz"
QEMU_CPU_MODEL="${AWEOS_QEMU_CPU:-qemu64}"
QEMU_DEBUG_FLAGS="${AWEOS_QEMU_DEBUG_FLAGS:-int,guest_errors,cpu_reset}"
if [ "${QEMU_CPU_MODEL}" = "qemu64" ]; then
    CPU_SUFFIX=""
else
    CPU_SUFFIX="-${QEMU_CPU_MODEL//[^A-Za-z0-9_-]/_}"
fi
BIOS_LOG="${BUILD_DIR}/qemu-bios${CPU_SUFFIX}.log"
UEFI_LOG="${BUILD_DIR}/qemu-uefi${CPU_SUFFIX}.log"
KERNEL_LOG="${BUILD_DIR}/qemu-kernel${CPU_SUFFIX}.log"
TARGET_MODE="${2:-all}"

case "${TARGET_MODE}" in
    all|bios|uefi|kernel) ;;
    *)
        echo "ERROR: unsupported boot-test mode '${TARGET_MODE}' (expected all, bios, uefi, or kernel)." >&2
        exit 2
        ;;
esac

test -s "${ISO_PATH}" || {
    echo "ERROR: ISO not found at ${ISO_PATH}" >&2
    exit 1
}
if [ "${TARGET_MODE}" = "all" ] || [ "${TARGET_MODE}" = "kernel" ]; then
    test -s "${KERNEL_PATH}" || { echo "ERROR: kernel image missing at ${KERNEL_PATH}" >&2; exit 1; }
    test -s "${INITRAMFS_PATH}" || { echo "ERROR: initramfs missing at ${INITRAMFS_PATH}" >&2; exit 1; }
fi

mkdir -p -- "${BUILD_DIR}"

echo "=========================================="
echo "AWEOS QEMU boot verification (CPU model: ${QEMU_CPU_MODEL})"
echo "=========================================="

failures=0

test_boot() {
    local mode="$1"
    local logfile="$2"
    local expected="$3"
    local debuglog="${logfile%.log}-debug.log"
    shift 3

    echo "Testing AWEOS ${mode} boot..."
    rm -f -- "${logfile}" "${debuglog}"

    local rc=0
    set +e
    timeout 100s "$@" >"${logfile}" 2>&1
    rc=$?
    set -e

    cat "${logfile}"

    # timeout(124) is expected only after the guest has reached its boot marker.
    if [ "${rc}" -ne 0 ] && [ "${rc}" -ne 124 ]; then
        echo "FAIL: QEMU exited with status ${rc} during ${mode} boot." >&2
        if [ -s "${debuglog}" ]; then
            echo "--- QEMU diagnostics (${debuglog}) ---" >&2
            tail -n 120 "${debuglog}" >&2
        fi
        return 1
    fi

    if ! grep -q "AWEOS ROOTFS READY: mode=" "${logfile}"; then
        echo "FAIL: root filesystem never reached its verified init hand-off in ${mode} mode." >&2
        if [ -s "${logfile}" ]; then
            echo "--- serial output (${logfile}) ---" >&2
            tail -n 120 "${logfile}" >&2
        fi
        if [ -s "${debuglog}" ]; then
            echo "--- QEMU diagnostics (${debuglog}) ---" >&2
            tail -n 120 "${debuglog}" >&2
        fi
        return 1
    fi

    if grep -qiE "kernel panic|unable to mount root fs|VFS: Cannot open root device" "${logfile}"; then
        echo "FAIL: kernel/root-filesystem failure detected in ${mode} log." >&2
        return 1
    fi

    if grep -q "AWEOS RECOVERY SHELL READY" "${logfile}"; then
        echo "FAIL: a boot/session failure transferred control to the recovery console in ${mode} mode." >&2
        grep -E "EventLoopCreation|AYUI|AWEOS session|RECOVERY" "${logfile}" | tail -n 60 >&2 || true
        return 1
    fi

    if [ "${expected}" = "headless" ]; then
        if grep -q "AWEOS ROOTFS READY: mode=headless" "${logfile}" &&
           grep -q "AWEOS HEADLESS CONSOLE READY" "${logfile}"; then
            echo "SUCCESS: AWEOS ${mode} boot reached the verified headless rootfs console (firmware framebuffer not expected)."
        else
            echo "FAIL: direct-kernel boot did not reach its explicit headless console marker." >&2
            return 1
        fi
    elif grep -q "AWEOS AYUI COMPOSITOR READY:" "${logfile}"; then
        echo "SUCCESS: AWEOS ${mode} boot reached the nested AYUI Wayland compositor and rendered its first frame."
    elif grep -q "AWEOS AYUI FRAMEBUFFER READY:" "${logfile}"; then
        echo "SUCCESS: AWEOS ${mode} boot reached the AYUI framebuffer fallback and rendered its first frame (degraded desktop mode)."
    else
        echo "FAIL: rootfs booted, but neither AYUI backend reached its first-frame readiness marker in ${mode} mode." >&2
        return 1
    fi
}

if [ "${TARGET_MODE}" = "all" ] || [ "${TARGET_MODE}" = "bios" ]; then
    # The legacy PC machine provides the conventional PIIX IDE CD-ROM path.
    if ! test_boot "BIOS" "${BIOS_LOG}" "desktop" \
        qemu-system-x86_64 \
        -machine pc \
        -m 2048M \
        -cpu "${QEMU_CPU_MODEL}" \
        -boot order=d \
        -cdrom "${ISO_PATH}" \
        -display none \
        -serial stdio \
        -monitor none \
        -no-reboot \
        -d "${QEMU_DEBUG_FLAGS}" \
        -D "${BUILD_DIR}/qemu-bios${CPU_SUFFIX}-debug.log"; then
        failures=$((failures + 1))
    fi
fi

if [ "${TARGET_MODE}" = "all" ] || [ "${TARGET_MODE}" = "uefi" ]; then
    UEFI_FIRMWARE="${AWEOS_UEFI_FIRMWARE:-}"
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
        if ! test_boot "UEFI" "${UEFI_LOG}" "desktop" \
            qemu-system-x86_64 \
            -machine q35 \
            -m 2048M \
            -cpu "${QEMU_CPU_MODEL}" \
            -boot order=d \
            -bios "${UEFI_FIRMWARE}" \
            -cdrom "${ISO_PATH}" \
            -display none \
            -serial stdio \
            -monitor none \
            -no-reboot \
            -d "${QEMU_DEBUG_FLAGS}" \
            -D "${BUILD_DIR}/qemu-uefi${CPU_SUFFIX}-debug.log"; then
            failures=$((failures + 1))
        fi
    else
        echo "FAIL: OVMF firmware not found; UEFI boot test cannot be skipped." >&2
        failures=$((failures + 1))
    fi
fi

# This bypasses Limine and firmware-provided framebuffer hand-off data.
# Use explicit headless init to isolate kernel + initramfs boot from desktop/display
# support, which is already exercised by the BIOS and UEFI boot tests.
if [ "${TARGET_MODE}" = "all" ] || [ "${TARGET_MODE}" = "kernel" ]; then
    if ! test_boot "direct kernel" "${KERNEL_LOG}" "headless" \
        qemu-system-x86_64 \
        -machine pc \
        -m 2048M \
        -cpu "${QEMU_CPU_MODEL}" \
        -kernel "${KERNEL_PATH}" \
        -initrd "${INITRAMFS_PATH}" \
        -append "aweos.mode=headless console=tty0 console=ttyS0,115200n8 earlycon=uart8250,io,0x3f8,115200 loglevel=7 ignore_loglevel" \
        -cdrom "${ISO_PATH}" \
        -display none \
        -serial stdio \
        -monitor none \
        -no-reboot \
        -d "${QEMU_DEBUG_FLAGS}" \
        -D "${BUILD_DIR}/qemu-kernel${CPU_SUFFIX}-debug.log"; then
        failures=$((failures + 1))
    fi
fi

echo "=========================================="
if [ "${failures}" -gt 0 ]; then
    echo "AWEOS QEMU boot verification failed: ${failures} boot mode(s) failed."
    exit 1
fi
echo "AWEOS QEMU boot verification passed for requested mode(s)."
echo "=========================================="
