#!/usr/bin/env bash
# Regression tests for the QEMU boot-test runner.
# Uses a mock QEMU binary so the runner's failure aggregation can be tested
# without booting a guest or requiring a built AWEOS image.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The available API push transport commits blobs as mode 100644 and cannot
# restore 100755, so the runner is invoked through bash everywhere in CI and
# correctness must not depend on the checked-out mode. Still require the bash
# interpreter line so the runner cannot silently become a non-bash shell script.
if [ "$(head -n 1 "$repo_root/scripts/run-qemu-tests.sh")" != "#!/usr/bin/env bash" ]; then
    echo "ERROR: scripts/run-qemu-tests.sh must start with the bash interpreter line; every CI path invokes it through bash." >&2
    exit 1
fi
tmp_root="$(mktemp -d)"
trap 'rm -rf -- "$tmp_root"' EXIT

build_dir="$tmp_root/build"
mock_bin="$tmp_root/bin"
firmware="$tmp_root/OVMF_CODE.fd"
mkdir -p "$build_dir/linux-x86_64/arch/x86/boot" "$mock_bin"
printf 'mock ISO\n' > "$build_dir/AWEOS-x86_64.iso"
printf 'mock kernel\n' > "$build_dir/linux-x86_64/arch/x86/boot/bzImage"
printf 'mock initramfs\n' > "$build_dir/aweos-initramfs.cpio.gz"
printf 'mock firmware\n' > "$firmware"

cat > "$mock_bin/qemu-system-x86_64" <<'MOCK_QEMU'
#!/usr/bin/env bash
set -euo pipefail

debug_log=""
append=""
dfilter=""
is_uefi=0
is_kernel=0
while (($#)); do
    case "$1" in
        -D)
            debug_log="${2:-}"
            shift 2
            ;;
        -dfilter)
            dfilter="${2:-}"
            shift 2
            ;;
        -bios)
            is_uefi=1
            shift 2
            ;;
        -kernel)
            is_kernel=1
            shift 2
            ;;
        -append)
            append="${2:-}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Mirror QEMU's documented -dfilter address-range grammar for the range form
# used by this test (start..end). This catches malformed diagnostic arguments
# before the mock can accidentally report a false-positive boot.
if [[ -n "$dfilter" ]]; then
    IFS=',' read -r -a dfilter_ranges <<< "$dfilter"
    for dfilter_range in "${dfilter_ranges[@]}"; do
        if [[ ! "$dfilter_range" =~ ^0x[[:xdigit:]]+\.\.0x[[:xdigit:]]+$ ]]; then
            echo "qemu-system-x86_64: -dfilter $dfilter: Invalid range" >&2
            exit 1
        fi
    done
fi

# Record the CPU model in the exact debug file passed through QEMU's -D option.
# This verifies that a later diagnostic retry cannot overwrite primary logs.
if [[ -n "$debug_log" ]]; then
    printf 'mock cpu=%s\n' "${AWEOS_QEMU_CPU:-qemu64}" > "$debug_log"
    if [[ -n "$dfilter" ]]; then
    grep -qF "mock dfilter=0x500000..0x600000,0x3c00000..0x45d0000" "$build_dir/qemu-$mode-instrtrace-debug.log"
    fi
fi

if [[ "${MOCK_QEMU_MODE:-success}" == "desktop-fails" ]]; then
    echo 'AWEOS ROOTFS READY: mode=ayui'
    echo 'AWEOS RECOVERY SHELL READY'
    exit 0
fi

if [[ "${MOCK_QEMU_MODE:-success}" == "headless-fails" && "$is_kernel" -eq 1 ]]; then
    echo 'AWEOS ROOTFS READY: mode=headless'
    exit 0
fi

if [[ "$is_kernel" -eq 1 && "$append" == *aweos.mode=headless* ]]; then
    echo 'AWEOS ROOTFS READY: mode=headless'
    echo 'AWEOS HEADLESS CONSOLE READY'
    exit 0
fi

if [[ "${MOCK_QEMU_MODE:-success}" == "framebuffer-fallback" ]]; then
    echo 'AWEOS ROOTFS READY: mode=ayui'
    echo 'AWEOS AYUI FRAMEBUFFER READY: device=/dev/fb0 width=800 height=600 bpp=32'
    exit 0
fi

if [[ "${MOCK_QEMU_MODE:-success}" == "fail-bios" && "$is_uefi" -eq 0 && "$is_kernel" -eq 0 ]]; then
    if [[ -n "$debug_log" ]]; then
        printf 'simulated BIOS reset\n' >> "$debug_log"
    fi
    echo 'simulated BIOS boot failure' >&2
    exit 1
fi

if [[ "$is_kernel" -eq 1 ]]; then
    echo 'AWEOS ROOTFS READY: mode=headless'
    echo 'AWEOS HEADLESS CONSOLE READY'
else
    echo 'AWEOS ROOTFS READY: mode=ayui'
    echo 'AWEOS AYUI COMPOSITOR READY: backend=mock'
fi
exit 0
MOCK_QEMU
chmod 0755 "$mock_bin/qemu-system-x86_64"

# A BIOS failure must not prevent the UEFI or direct-kernel tests from running.
set +e
PATH="$mock_bin:$PATH" \
AWEOS_UEFI_FIRMWARE="$firmware" \
MOCK_QEMU_MODE=fail-bios \
    bash "$repo_root/scripts/run-qemu-tests.sh" "$build_dir" all \
    > "$tmp_root/fail-bios-output.log" 2>&1
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
    echo "ERROR: runner unexpectedly passed when the BIOS mock failed." >&2
    exit 1
fi
grep -q 'Testing AWEOS UEFI boot' "$tmp_root/fail-bios-output.log"
grep -q 'SUCCESS: AWEOS UEFI boot' "$tmp_root/fail-bios-output.log"
grep -q 'Testing AWEOS direct kernel boot' "$tmp_root/fail-bios-output.log"
grep -q 'SUCCESS: AWEOS direct kernel boot reached the verified headless rootfs console' "$tmp_root/fail-bios-output.log"
grep -q 'AWEOS ROOTFS READY: mode=ayui' "$build_dir/qemu-uefi.log"
grep -q 'AWEOS AYUI COMPOSITOR READY' "$build_dir/qemu-uefi.log"
grep -q 'AWEOS ROOTFS READY: mode=headless' "$build_dir/qemu-kernel.log"
grep -q 'AWEOS HEADLESS CONSOLE READY' "$build_dir/qemu-kernel.log"
! grep -q 'AWEOS AYUI COMPOSITOR READY' "$build_dir/qemu-kernel.log"
test -s "$build_dir/qemu-bios-debug.log"

# All three boot paths must pass when the mock firmware and QEMU runs succeed.
PATH="$mock_bin:$PATH" \
AWEOS_QEMU_CPU=max \
AWEOS_UEFI_FIRMWARE="$firmware" \
MOCK_QEMU_MODE=success \
    bash "$repo_root/scripts/run-qemu-tests.sh" "$build_dir" all \
    > "$tmp_root/success-output.log" 2>&1
grep -q 'SUCCESS: AWEOS BIOS boot' "$tmp_root/success-output.log"
grep -q 'SUCCESS: AWEOS UEFI boot' "$tmp_root/success-output.log"
grep -q 'SUCCESS: AWEOS direct kernel boot reached the verified headless rootfs console' "$tmp_root/success-output.log"
for mode in bios uefi kernel; do
    test -s "$build_dir/qemu-$mode-debug.log"
    test -s "$build_dir/qemu-$mode-max-debug.log"
    grep -q "^mock cpu=qemu64$" "$build_dir/qemu-$mode-debug.log"
    grep -q "^mock cpu=max$" "$build_dir/qemu-$mode-max-debug.log"
done

# A rootfs that falls back to the recovery console must not be misreported as a desktop boot.
set +e
PATH="$mock_bin:$PATH" \
MOCK_QEMU_MODE=desktop-fails \
    bash "$repo_root/scripts/run-qemu-tests.sh" "$build_dir" bios \
    > "$tmp_root/desktop-failure-output.log" 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
    echo "ERROR: runner reported a desktop success after AYUI fell back to recovery." >&2
    exit 1
fi
grep -q 'AWEOS RECOVERY SHELL READY' "$build_dir/qemu-bios.log"
grep -q 'transferred control to the recovery console' "$tmp_root/desktop-failure-output.log"

# A first-frame framebuffer fallback is a valid, explicitly degraded desktop boot.
PATH="$mock_bin:$PATH" \
AWEOS_UEFI_FIRMWARE="$firmware" \
MOCK_QEMU_MODE=framebuffer-fallback \
    bash "$repo_root/scripts/run-qemu-tests.sh" "$build_dir" all \
    > "$tmp_root/framebuffer-fallback-output.log" 2>&1
grep -q 'AYUI framebuffer fallback' "$tmp_root/framebuffer-fallback-output.log"
grep -q 'AWEOS AYUI FRAMEBUFFER READY' "$build_dir/qemu-bios.log"
grep -q 'AWEOS AYUI FRAMEBUFFER READY' "$build_dir/qemu-uefi.log"
grep -q 'AWEOS HEADLESS CONSOLE READY' "$build_dir/qemu-kernel.log"

# Direct-kernel boot must not pass merely because the rootfs mounted; it must
# execute the explicit headless console hand-off.
set +e
PATH="$mock_bin:$PATH" \
MOCK_QEMU_MODE=headless-fails \
    bash "$repo_root/scripts/run-qemu-tests.sh" "$build_dir" kernel \
    > "$tmp_root/headless-failure-output.log" 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
    echo "ERROR: direct-kernel test passed without the headless console marker." >&2
    exit 1
fi
grep -q 'direct-kernel boot did not reach its explicit headless console marker' "$tmp_root/headless-failure-output.log"

# A requested UEFI test must fail if the explicitly selected firmware is missing.
set +e
PATH="$mock_bin:$PATH" \
AWEOS_UEFI_FIRMWARE="$tmp_root/missing-OVMF.fd" \
    bash "$repo_root/scripts/run-qemu-tests.sh" "$build_dir" uefi \
    > "$tmp_root/missing-firmware-output.log" 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
    echo "ERROR: runner unexpectedly passed with missing UEFI firmware." >&2
    exit 1
fi
grep -q 'OVMF firmware not found' "$tmp_root/missing-firmware-output.log"

# Reject the malformed hyphen-separated range that QEMU itself rejects.
set +e
PATH="$mock_bin:$PATH" \
AWEOS_QEMU_DFILTER=0x3c00000-0x3d00000 \
    bash "$repo_root/scripts/run-qemu-tests.sh" "$build_dir" bios \
    > "$tmp_root/invalid-dfilter-output.log" 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
    echo "ERROR: runner mock accepted QEMU's invalid hyphen-separated -dfilter range." >&2
    exit 1
fi
grep -q -- "-dfilter 0x3c00000-0x3d00000: Invalid range" "$tmp_root/invalid-dfilter-output.log"

# Validate each member of a comma-separated range list independently.
set +e
PATH="$mock_bin:$PATH" \
AWEOS_QEMU_DFILTER=0x500000..0x600000,0x3c00000-0x3d00000 \
    bash "$repo_root/scripts/run-qemu-tests.sh" "$build_dir" bios \
    > "$tmp_root/invalid-dfilter-list-output.log" 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
    echo "ERROR: runner mock accepted an invalid member of a comma-separated -dfilter list." >&2
    exit 1
fi
grep -q -- "-dfilter 0x500000..0x600000,0x3c00000-0x3d00000: Invalid range" "$tmp_root/invalid-dfilter-list-output.log"

# A diagnostic instruction-trace retry with the same CPU model must write to
# its own tagged logs and must not overwrite the primary or max-CPU logs.
PATH="$mock_bin:$PATH" \
AWEOS_UEFI_FIRMWARE="$firmware" \
AWEOS_QEMU_LOG_SUFFIX=instrtrace \
AWEOS_QEMU_DFILTER=0x500000..0x600000,0x3c00000..0x45d0000 \
MOCK_QEMU_MODE=success \
    bash "$repo_root/scripts/run-qemu-tests.sh" "$build_dir" all \
    > "$tmp_root/trace-output.log" 2>&1
for mode in bios uefi kernel; do
    test -s "$build_dir/qemu-$mode-instrtrace.log"
    test -s "$build_dir/qemu-$mode-instrtrace-debug.log"
    grep -q "^mock cpu=qemu64$" "$build_dir/qemu-$mode-instrtrace-debug.log"
    grep -q "^mock dfilter=0x3c00000\.\.0x45d0000$" "$build_dir/qemu-$mode-instrtrace-debug.log"
done
for mode in bios uefi kernel; do
    grep -q "^mock cpu=max$" "$build_dir/qemu-$mode-max-debug.log"
done
grep -q "SUCCESS: AWEOS BIOS boot" "$tmp_root/trace-output.log"
grep -q "SUCCESS: AWEOS UEFI boot" "$tmp_root/trace-output.log"
grep -q "SUCCESS: AWEOS direct kernel boot" "$tmp_root/trace-output.log"

echo "PASS: QEMU runner requires first-frame AYUI for BIOS/UEFI, an explicit headless-console hand-off for direct kernel, aggregates failures, requires UEFI firmware, and keeps diagnostic retries in separate tagged logs."
