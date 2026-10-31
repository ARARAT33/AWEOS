#!/usr/bin/env bash
# Regression tests for the QEMU boot-test runner.
# Uses a mock QEMU binary so the runner's failure aggregation can be tested
# without booting a guest or requiring a built AWEOS image.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
is_uefi=0
is_kernel=0
while (($#)); do
    case "$1" in
        -D)
            debug_log="${2:-}"
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
        *)
            shift
            ;;
    esac
done

if [[ "${MOCK_QEMU_MODE:-success}" == "fail-bios" && "$is_uefi" -eq 0 && "$is_kernel" -eq 0 ]]; then
    if [[ -n "$debug_log" ]]; then
        printf 'simulated BIOS reset\n' > "$debug_log"
    fi
    echo 'simulated BIOS boot failure' >&2
    exit 1
fi

echo 'AWEOS BOOT SUCCESS: mode=ayui'
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
grep -q 'SUCCESS: AWEOS direct kernel boot' "$tmp_root/fail-bios-output.log"
grep -q 'AWEOS BOOT SUCCESS: mode=ayui' "$build_dir/qemu-uefi.log"
grep -q 'AWEOS BOOT SUCCESS: mode=ayui' "$build_dir/qemu-kernel.log"
test -s "$build_dir/qemu-bios-debug.log"

# All three boot paths must pass when the mock firmware and QEMU runs succeed.
PATH="$mock_bin:$PATH" \
AWEOS_UEFI_FIRMWARE="$firmware" \
MOCK_QEMU_MODE=success \
    bash "$repo_root/scripts/run-qemu-tests.sh" "$build_dir" all \
    > "$tmp_root/success-output.log" 2>&1
grep -q 'SUCCESS: AWEOS BIOS boot' "$tmp_root/success-output.log"
grep -q 'SUCCESS: AWEOS UEFI boot' "$tmp_root/success-output.log"
grep -q 'SUCCESS: AWEOS direct kernel boot' "$tmp_root/success-output.log"

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

echo "PASS: QEMU runner independently tests BIOS, UEFI and direct kernel boot, aggregates failures, and requires UEFI firmware."
