#!/usr/bin/env bash
# Regression for scripts/extract-qemu-instrtrace.sh.
# Covers QEMU's short-address OBJD-T format, selector and 0x IP forms,
# decoded-instruction fallback, bounded output, and missing/empty/clean logs.
set -uo pipefail

here="$(cd -- "$(dirname -- "$0")" && pwd -P)"
extractor="$here/extract-qemu-instrtrace.sh"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/aweos-instrtrace-test.XXXXXX")"
trap 'rm -rf -- "$workdir"' EXIT

# --- Fixture 1: real QEMU format. Fault IP is inside a short-address OBJD-T block. ---
fault_log="$workdir/qemu-bios-instrtrace-debug.log"
{
    echo "IN:"
    echo "0x03cd63bc:"
    echo "OBJD-T: 8b05b2ae0000bf01000000c4e2fbf7ca81e1ff010000"
    echo "     0: v=06 e=0000 i=0 cpl=0 IP=0010:0000000003cd63c7 pc=0000000003cd63c7"
    echo "     1: v=0d e=0032 i=0 cpl=0 IP=0010:0000000003cd63c7 pc=0000000003cd63c7"
    echo "     2: v=08 e=0000 i=0 cpl=0 IP=0010:0000000003cd63c7 pc=0000000003cd63c7"
} >"$fault_log"

# --- Fixture 2: -d int RIP=0x form and a block beginning at the exact IP. ---
fault0x_log="$workdir/qemu-kernel-instrtrace-debug.log"
{
    echo "IN:"
    echo "0x03cd63c7:"
    echo "OBJD-T: c4e2fbf7ca"
    echo "     0: v=06 e=0000 i=1 cpl=0 RIP=0x3cd63c7"
    echo "     1: v=08 e=0000 i=1 cpl=0 RIP=0x3cd63c7"
} >"$fault0x_log"

# --- Fixture 3: UEFI relocation of the same faulting block by 8 MiB. ---
uefi_log="$workdir/qemu-uefi-instrtrace-debug.log"
{
    echo "IN:"
    echo "0x044d63bc:"
    echo "OBJD-T: 8b05b2ae0000bf01000000c4e2fbf7ca81e1ff010000"
    echo "     0: v=06 e=0000 i=0 cpl=0 IP=0010:00000000044d63c7 pc=00000000044d63c7"
    echo "     1: v=08 e=0000 i=0 cpl=0 IP=0010:00000000044d63c7 pc=00000000044d63c7"
} >"$uefi_log"

# --- Fixture 4: already-decoded disassembly format fallback. ---
decoded_log="$workdir/qemu-decoded-instrtrace-debug.log"
{
    echo "0x0000000003cd63c7:  0f 0b                    ud2"
    echo "     0: v=06 e=0000 i=1 cpl=0 RIP=0x3cd63c7"
} >"$decoded_log"

# --- Fixture 5: fault-free log (fallback tail path). ---
clean_log="$workdir/qemu-clean-instrtrace-debug.log"
for i in $(seq 1 100); do
    echo "clean line $i" >>"$clean_log"
done
echo "AWEOS LAST TRACE LINE" >>"$clean_log"

# --- Fixture 6: empty log. ---
: >"$workdir/qemu-empty-instrtrace-debug.log"

# --- Fixture 7: userspace CPL3 fault at the address observed in QEMU CI. ---
# The bytes are synthetic; this verifies parsing of a low userspace virtual
# address and selector:offset form after the diagnostic filter is widened.
userland_log="$workdir/qemu-userland-instrtrace-debug.log"
{
    echo "IN:"
    echo "0x0056df48:"
    echo "OBJD-T: 90909090909090900f0b"
    echo "     0: v=06 e=0000 i=0 cpl=3 IP=0033:000000000056df50 pc=000000000056df50"
} >"$userland_log"

summary="$workdir/summary.txt"
if ! bash "$extractor" \
        "$fault_log" \
        "$fault0x_log" \
        "$uefi_log" \
        "$decoded_log" \
        "$clean_log" \
        "$workdir/qemu-empty-instrtrace-debug.log" \
        "$userland_log" \
        "$workdir/qemu-missing-instrtrace-debug.log" \
        >"$summary" 2>&1; then
    echo "FAIL: extractor exited non-zero." >&2
    cat "$summary" >&2
    exit 1
fi

fail=0
check() {
    if ! grep -qF "$2" "$summary"; then
        echo "FAIL: expected output not found: $2" >&2
        fail=1
    fi
}

check fixture1 "qemu-bios-instrtrace-debug.log"
check fixture1 "v=06 e=0000 i=0 cpl=0 IP=0010:0000000003cd63c7"
check fixture1 "Guest instructions around faulting address 0x0000000003cd63c7:"
check fixture1 "QEMU trace block: 0x03cd63bc (fault offset 11 bytes)"
check fixture1 "Faulting instruction bytes: c4e2fbf7ca"
if command -v objdump >/dev/null 2>&1; then
    check fixture1 "shrx"
    check fixture1 "rcx,rdx,rax"
fi
check fixture2 "qemu-kernel-instrtrace-debug.log"
check fixture2 "RIP=0x3cd63c7"
check fixture2 "Faulting instruction bytes: c4e2fbf7ca"
check fixture3 "qemu-uefi-instrtrace-debug.log"
check fixture3 "Guest instructions around faulting address 0x00000000044d63c7:"
check fixture3 "QEMU trace block: 0x044d63bc (fault offset 11 bytes)"
check fixture3 "Faulting instruction bytes: c4e2fbf7ca"
check fixture4 "qemu-decoded-instrtrace-debug.log"
check fixture4 "0x0000000003cd63c7:  0f 0b                    ud2"
check fixture5 "qemu-clean-instrtrace-debug.log"
check fixture5 "No CPU fault events"
check fixture5 "AWEOS LAST TRACE LINE"
check fixture6 "qemu-empty-instrtrace-debug.log"
check fixture6 "EMPTY: debug log has no content."
check fixture7 "qemu-userland-instrtrace-debug.log"
check fixture7 "cpl=3 IP=0033:000000000056df50"
check fixture7 "Guest instructions around faulting address 0x000000000056df50:"
check fixture7 "Faulting instruction bytes: 0f0b"
check fixture7 "ud2"
check fixture8 "qemu-missing-instrtrace-debug.log"
check fixture7 "MISSING: no such debug log."

line_count="$(wc -l <"$summary")"
if [ "$line_count" -gt 640 ]; then
    echo "FAIL: summary output is unbounded (${line_count} lines; expected at most 640)." >&2
    fail=1
fi

# --- Usage error handling: no arguments must fail closed. ---
if bash "$extractor" >/dev/null 2>&1; then
    echo "FAIL: extractor without arguments must exit non-zero." >&2
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo "FAIL: qemu instruction-trace extraction regression failed." >&2
    exit 1
fi
echo "PASS: qemu instruction-trace extraction regression."
exit 0
