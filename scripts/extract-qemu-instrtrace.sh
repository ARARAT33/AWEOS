#!/usr/bin/env bash
# Extract a bounded, human-readable summary of the last CPU fault event and
# the guest instructions around it from a QEMU -d int,in_asm debug log.
# Intended for the tagged qemu64 instruction-trace diagnostics produced by
# scripts/run-qemu-tests.sh, so the faulting instruction can be diagnosed from
# the CI annotations, step summary, and a small dedicated artifact instead of
# requiring a full multi-hundred-megabyte diagnostics download.
# Usage: extract-qemu-instrtrace.sh <qemu-debug-log> [<qemu-debug-log> ...]
set -uo pipefail

MAX_FAULT_EVENTS=8
MAX_DISASM_CONTEXT=12
MAX_FALLBACK_LINES=40
MAX_LINES_PER_LOG=80

if [ "$#" -lt 1 ]; then
    echo "usage: $0 <qemu-debug-log> [<qemu-debug-log> ...]" >&2
    exit 2
fi

summarize_log() {
    local log="$1"

    echo "==== $(basename "$log") ===="
    if [ ! -f "$log" ]; then
        echo "MISSING: no such debug log."
        return 0
    fi
    if [ ! -s "$log" ]; then
        echo "EMPTY: debug log has no content."
        return 0
    fi

    local fault_line
    fault_line="$(grep -E 'v=0[68d]' "$log" | tail -n 1 || true)"
    if [ -z "$fault_line" ]; then
        echo "No CPU fault events (v=06/v=08/v=0d) found; last ${MAX_FALLBACK_LINES} log lines follow."
        tail -n "$MAX_FALLBACK_LINES" "$log"
        return 0
    fi

    echo "Last fault event:"
    echo "$fault_line"
    echo
    echo "Recent fault events (up to ${MAX_FAULT_EVENTS}):"
    grep -E 'v=0[68d]|check_exception' "$log" | tail -n "$MAX_FAULT_EVENTS" || true

    local fault_addr fault_addr_norm zero_pad
    fault_addr="$(printf '%s\n' "$fault_line" | grep -oEi '(ip|rip|pc)=[0-9:]*0x[0-9a-f]+' | tail -n 1 | grep -oE '0x[0-9a-f]+' || true)"
    if [ -z "$fault_addr" ]; then
        echo "Could not parse a faulting instruction pointer from the fault event line."
        return 0
    fi
    fault_addr_norm="$(printf '%s' "$fault_addr" | sed 's/^0x//')"
    if [ ${#fault_addr_norm} -lt 16 ]; then
        zero_pad=$((16 - ${#fault_addr_norm}))
        fault_addr_norm="$(printf '%*s%s' "$zero_pad" '' "$fault_addr_norm" | tr ' ' '0')"
    fi
    echo
    echo "Guest instructions around faulting address 0x${fault_addr_norm}:"
    grep -A "$MAX_DISASM_CONTEXT" -E "^0x${fault_addr_norm}: " "$log" | head -n $((MAX_DISASM_CONTEXT + 1)) || true
    echo
}

for log in "$@"; do
    summarize_log "$log" | head -n "$MAX_LINES_PER_LOG"
done

exit 0
