#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aweos-qemu-readiness.XXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

BUILD_DIR="$TEMP_ROOT/build"
FAKE_BIN="$TEMP_ROOT/bin"
mkdir -p "$BUILD_DIR" "$FAKE_BIN"
: > "$BUILD_DIR/AWEOS-x86_64.iso"

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

echo "PASS: QEMU boot validation requires an AYUI compositor first-frame marker."
