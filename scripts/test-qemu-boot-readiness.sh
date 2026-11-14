#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aweos-qemu-readiness.XXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

BUILD_DIR="$TEMP_ROOT/build"
FAKE_BIN="$TEMP_ROOT/bin"
mkdir -p "$BUILD_DIR" "$FAKE_BIN"
printf x > "$BUILD_DIR/AWEOS-x86_64.iso"

cat > "$FAKE_BIN/qemu-system-x86_64" <<'QEMU'
#!/bin/sh
cat "$AWEOS_QEMU_FAKE_LOG"
QEMU
chmod 0755 "$FAKE_BIN/qemu-system-x86_64"

# A rootfs hand-off marker alone must never be treated as a successful desktop boot.
printf '%s\n' 'AWEOS ROOTFS READY: mode=aweui' > "$TEMP_ROOT/rootfs-only.log"
if PATH="$FAKE_BIN:$PATH" AWEOS_QEMU_FAKE_LOG="$TEMP_ROOT/rootfs-only.log" \
    bash "$SCRIPT_DIR/run-qemu-tests.sh" "$BUILD_DIR" bios > "$TEMP_ROOT/rootfs-only.out" 2>&1; then
    echo "ERROR: QEMU boot test accepted rootfs hand-off without compositor readiness." >&2
    exit 1
fi
grep -Fq 'rootfs hand-off alone is not desktop readiness' "$TEMP_ROOT/rootfs-only.out"

# The explicit compositor first-frame marker is required for an AYUI boot pass.
printf '%s\n' \
    'AWEOS ROOTFS READY: mode=aweui' \
    'AWEOS COMPOSITOR READY: session=ayui backend=winit first-frame=1' \
    > "$TEMP_ROOT/compositor-ready.log"
PATH="$FAKE_BIN:$PATH" AWEOS_QEMU_FAKE_LOG="$TEMP_ROOT/compositor-ready.log" \
    bash "$SCRIPT_DIR/run-qemu-tests.sh" "$BUILD_DIR" bios > "$TEMP_ROOT/compositor-ready.out" 2>&1
grep -Fq 'SUCCESS: AWEOS BIOS boot reached a running AYUI compositor.' "$TEMP_ROOT/compositor-ready.out"

# A present OVMF image must run the UEFI path with the same readiness checks.
printf x > "$TEMP_ROOT/OVMF.fd"
AWEOS_OVMF_FIRMWARE="$TEMP_ROOT/OVMF.fd" \
    PATH="$FAKE_BIN:$PATH" AWEOS_QEMU_FAKE_LOG="$TEMP_ROOT/compositor-ready.log" \
    bash "$SCRIPT_DIR/run-qemu-tests.sh" "$BUILD_DIR" uefi > "$TEMP_ROOT/uefi-ready.out" 2>&1
grep -Fq 'SUCCESS: AWEOS UEFI boot reached a running AYUI compositor.' "$TEMP_ROOT/uefi-ready.out"

# Missing OVMF must be a hard failure, never a silently skipped UEFI test.
if AWEOS_OVMF_FIRMWARE="$TEMP_ROOT/missing-ovmf.fd" \
    PATH="$FAKE_BIN:$PATH" AWEOS_QEMU_FAKE_LOG="$TEMP_ROOT/compositor-ready.log" \
    bash "$SCRIPT_DIR/run-qemu-tests.sh" "$BUILD_DIR" uefi > "$TEMP_ROOT/uefi-missing.out" 2>&1; then
    echo "ERROR: QEMU boot test silently accepted a missing OVMF firmware image." >&2
    exit 1
fi
grep -Fq 'ERROR: OVMF firmware not found; UEFI boot test is required.' "$TEMP_ROOT/uefi-missing.out"

echo "PASS: QEMU boot validation requires compositor readiness and cannot skip UEFI firmware."
