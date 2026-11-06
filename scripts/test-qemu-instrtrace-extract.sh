#!/usr/bin/env bash
# Regression for scripts/extract-qemu-instrtrace.sh.
# Verifies fault-event extraction, faulting-address disassembly lookup,
# bounded output, and missing/empty/fault-free log handling. Uses only
# fabricated QEMU-style debug logs in a temporary directory.
set -uo pipefail

here="$(cd -- "$(dirname -- "$0")" && pwd -P)"
extractor="$here/extract-qemu-instrtrace.sh"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/aweos-instrtrace-test.XXXXXX")"
trap 'rm -rf -- "$workdir"' EXIT

# --- Fixture 1: qemu64-style -d int,in_asm log with a #UD fault. ---
fault_log="$workdir/qemu-bios-instrtrace-debug.log"
{
    echo "TRACE: Executing 0008:0000000003cd6300"
    for i in $(seq 1 400); do
        echo "0x0000000003cd6$(printf '%03x' "$i"):  90                       nop"
    done
    echo "0x0000000003cd63c7:  0f 0b                    ud2"
    echo "0x0000000003cd63c8:  90                       nop"
    echo "     0: v=06 e=0000 i=1 cpl=0 IP=0008:0000000003cd63c7 pc=0000000003cd63c7 SP=0000000000007c00"
    echo "     0: v=0d e=0032 i=1 cpl=0 IP=0008:0000000003cd63c7 pc=0000000003cd63c7 SP=0000000000007c00"
    echo "check_exception old: 0xffffffff new 6 (#ud -> #gp)"
    echo "     0: v=08 e=0000 i=1"
} >"$fault_log"

# --- Fixture 2: fault-free log (fallback tail path). ---
clean_log="$workdir/qemu-uefi-instrtrace-debug.log"
for i in $(seq 1 100); do
    echo "clean line $i"
done
echo "AWEOS LAST TRACE LINE" >>"$clean_log"

# --- Fixture 3: empty log. ---
: >"$workdir/qemu-empty-instrtrace-debug.log"

summary="$workdir/summary.txt"
if ! bash "$extractor" \
        "$fault_log" \
        "$clean_log" \
        "$workdir/qemu-empty-instrtrace-debug.log" \
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
check fixture1 "v=06 e=0000 i=1 cpl=0 IP=0008:0000000003cd63c7"
check fixture1 "0x0000000003cd63c7:  0f 0b                    ud2"
check fixture1 "check_exception"
check fixture2 "qemu-uefi-instrtrace-debug.log"
check fixture2 "No CPU fault events"
check fixture2 "AWEOS LAST TRACE LINE"
check fixture3 "qemu-empty-instrtrace-debug.log"
check fixture3 "EMPTY: debug log has no content."
check fixture4 "qemu-missing-instrtrace-debug.log"
check fixture4 "MISSING: no such debug log."

line_count="$(wc -l <"$summary")"
if [ "$line_count" -gt 320 ]; then
    echo "FAIL: summary output is unbounded (${line_count} lines; expected at most 320)." >&2
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
