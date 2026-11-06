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

parse_fault_addr() {
    # Accepts the QEMU -d int address forms with and without selector and
    # 0x prefixes:
    #   IP=0008:0000000003cd63c7 pc=0000000003cd63c7  RIP=0x3cd63c7
    local line="$1" tok raw
    tok="$(printf '%s\n' "$line" | grep -oEi '(ip|rip|pc)=(0x)?[0-9a-f:]+' | tail -n 1 || true)"
    [ -z "$tok" ] && { echo ""; return 0; }
    raw="${tok#*=}"
    raw="${raw#0x}"
    raw="${raw##*:}"
    raw="$(printf '%s' "$raw" | sed 's/^0*//')"
    if [ -z "$raw" ]; then raw=0; fi
    printf '%s' "$raw"
}

norm16() {
    local raw="$1"
    while [ ${#raw} -lt 16 ]; do raw="0$raw"; done
    printf '%s' "$raw"
}

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

    local first_ud last_fault fault_line
    first_ud="$(grep -E 'v=06' "$log" | head -n 1 || true)"
    last_fault="$(grep -E 'v=0[68d]' "$log" | tail -n 1 || true)"
    if [ -z "$last_fault" ]; then
        echo "No CPU fault events (v=06/v=08/v=0d) found; last ${MAX_FALLBACK_LINES} log lines follow."
        tail -n "$MAX_FALLBACK_LINES" "$log"
        return 0
    fi
    # The original invalid-opcode (#UD) is the fault to explain; fall back to
    # the last recorded fault event when no invalid-opcode was recorded.
    if [ -n "$first_ud" ]; then fault_line="$first_ud"; else fault_line="$last_fault"; fi

    echo "Last fault event:"
    echo "$last_fault"
    echo
    echo "Recent fault events (up to ${MAX_FAULT_EVENTS}):"
    grep -E 'v=0[68d]|check_exception' "$log" | tail -n "$MAX_FAULT_EVENTS" || true

    local raw1 raw2 addr1 addr2
    raw1="$(parse_fault_addr "$fault_line")"
    raw2="$(parse_fault_addr "$last_fault")"
    addr1="$(norm16 "$raw1")"
    addr2="$(norm16 "$raw2")"
    if [ "$raw1" = "0" ] && [ "$raw2" = "0" ]; then
        echo
        echo "Could not parse a faulting instruction pointer from the fault event line."
        return 0
    fi
    echo
    if [ "$raw1" != "0" ]; then
        echo "Guest instructions around faulting address 0x${addr1}:"
        if ! grep -A "$MAX_DISASM_CONTEXT" -E "^0x${addr1}: " "$log" | head -n $((MAX_DISASM_CONTEXT + 1)); then
            echo "(no in_asm block found for 0x${addr1} in this log)"
        fi
    fi
    if [ "$raw2" != "0" ] && [ "$addr2" != "$addr1" ]; then
        echo
        echo "Guest instructions around last fault event address 0x${addr2}:"
        grep -A "$MAX_DISASM_CONTEXT" -E "^0x${addr2}: " "$log" | head -n $((MAX_DISASM_CONTEXT + 1)) || true
    fi
    echo
}

for log in "$@"; do
    summarize_log "$log" | head -n "$MAX_LINES_PER_LOG"
done

exit 0
