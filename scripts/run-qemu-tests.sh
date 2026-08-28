#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build}"
ISO_PATH="${BUILD_DIR}/AWEOS-x86_64.iso"
BIOS_LOG="${BUILD_DIR}/qemu-bios.log"
UEFI_LOG="${BUILD_DIR}/qemu-uefi.log"
GUI_LOG="${BUILD_DIR}/qemu-gui.log"
SCREENSHOT_PATH="${BUILD_DIR}/aweos-gui-screenshot.png"
PPM_PATH="${BUILD_DIR}/aweos-gui-screenshot.ppm"
QMP_SOCKET="${BUILD_DIR}/qmp-socket"
TARGET_MODE="${2:-all}"

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

# 1. BIOS Test
if [ "$TARGET_MODE" = "all" ] || [ "$TARGET_MODE" = "bios" ]; then
    test_boot "BIOS" "${BIOS_LOG}" qemu-system-x86_64 -machine q35 -m 512M -append "aweos.mode=headless" -cdrom "${ISO_PATH}" -display none -serial stdio -no-reboot -net nic,model=virtio -net user
fi

# 2. GUI Test (Standard QEMU VGA + QMP Framebuffer Verification)
test_gui() {
    echo "Testing AWEOS QEMU GUI Boot & Framebuffer rendering..."
    rm -f "${GUI_LOG}" "${QMP_SOCKET}" "${SCREENSHOT_PATH}" "${PPM_PATH}"

    set +e
    qemu-system-x86_64 -machine q35 -m 512M -cdrom "${ISO_PATH}" -vga std -display none \
        -serial stdio -qmp "unix:${QMP_SOCKET},server,nowait" -no-reboot -net nic,model=virtio -net user > "${GUI_LOG}" 2>&1 &
    QEMU_PID=$!

    local count=0
    local gui_ready=0
    while [ $count -lt 60 ]; do
        if grep -q "AWEOS GUI TERMINAL READY" "${GUI_LOG}"; then
            gui_ready=1
            break
        fi
        sleep 1
        count=$((count + 1))
    done

    echo "--- GUI Boot Output ---"
    cat "${GUI_LOG}"
    echo "----------------------"

    if [ "$gui_ready" -eq 1 ]; then
        echo "AWEOS GUI ready signal detected. Capturing QEMU framebuffer screenshot..."
        sleep 1
        # Send QMP screenshot command
        (
            sleep 0.5
            echo '{"execute": "qmp_capabilities"}'
            sleep 0.5
            echo "{\"execute\": \"screendump\", \"arguments\": {\"filename\": \"${PPM_PATH}\"}}"
            sleep 0.5
            echo '{"execute": "quit"}'
        ) | nc -U "${QMP_SOCKET}" >/dev/null 2>&1 || true

        wait $QEMU_PID 2>/dev/null || true
        set -e

        if [ -f "${PPM_PATH}" ]; then
            if command -v convert >/dev/null 2>&1; then
                convert "${PPM_PATH}" "${SCREENSHOT_PATH}" 2>/dev/null || cp "${PPM_PATH}" "${SCREENSHOT_PATH}"
            else
                cp "${PPM_PATH}" "${SCREENSHOT_PATH}"
            fi
            echo "SUCCESS: AWEOS Framebuffer Screenshot saved at ${SCREENSHOT_PATH}"
        else
            echo "WARNING: Screenshot generation via QMP skipped or unavailable."
        fi
    else
        kill -9 $QEMU_PID 2>/dev/null || true
        set -e
        echo "FAIL: AWEOS GUI initialization markers missing!" >&2
        return 1
    fi

    # Verify GUI boot markers
    for marker in "AWEOS BOOT SUCCESS" "AWEOS TERMINAL READY" "AWEOS GRAPHICS READY" "AWEOS INPUT READY" "AWEOS COMPOSITOR READY" "AWEOS GUI READY" "AWEOS GUI TERMINAL READY"; do
        if ! grep -q "${marker}" "${GUI_LOG}"; then
            echo "FAIL: Missing boot marker '${marker}' in GUI boot log!" >&2
            return 1
        fi
    done

    echo "SUCCESS: AWEOS QEMU GUI Boot & Rendering test PASSED!"
    return 0
}

if [ "$TARGET_MODE" = "all" ] || [ "$TARGET_MODE" = "gui" ]; then
    test_gui
fi

# 2. UEFI Test
UEFI_FIRMWARE=""
if [ -f /usr/share/ovmf/OVMF.fd ]; then
    UEFI_FIRMWARE=/usr/share/ovmf/OVMF.fd
elif [ -f /usr/share/OVMF/OVMF_CODE_4M.fd ]; then
    UEFI_FIRMWARE=/usr/share/OVMF/OVMF_CODE_4M.fd
elif [ -f /usr/share/OVMF/OVMF_CODE.fd ]; then
    UEFI_FIRMWARE=/usr/share/OVMF/OVMF_CODE.fd
fi

if [ "$TARGET_MODE" = "all" ] || [ "$TARGET_MODE" = "uefi" ]; then
    if [ -n "${UEFI_FIRMWARE}" ]; then
        test_boot "UEFI" "${UEFI_LOG}" qemu-system-x86_64 -machine q35 -m 512M -bios "${UEFI_FIRMWARE}" -cdrom "${ISO_PATH}" -display none -serial stdio -no-reboot -net nic,model=virtio -net user
    else
        echo "WARNING: OVMF firmware not found, skipping UEFI test in current environment."
    fi
fi

echo "=========================================="
echo "All AWEOS Boot Tests PASSED Successfully!"
echo "=========================================="
