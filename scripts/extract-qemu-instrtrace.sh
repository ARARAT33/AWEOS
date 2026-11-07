#!/usr/bin/env bash
# Extract a bounded, human-readable summary of the last CPU fault event and
# the guest instruction bytes around it from a QEMU -d int,in_asm debug log.
# QEMU's in_asm output may use short addresses plus OBJD-T raw-byte records;
# do not assume every address is printed as a zero-padded 16-digit value.
# Usage: extract-qemu-instrtrace.sh <qemu-debug-log> [<qemu-debug-log> ...]
set -uo pipefail

MAX_FAULT_EVENTS=8
MAX_FALLBACK_LINES=40
MAX_LINES_PER_LOG=80

if [ "$#" -lt 1 ]; then
    echo "usage: $0 <qemu-debug-log> [<qemu-debug-log> ...]" >&2
    exit 2
fi

parse_fault_addr() {
    # Accepts QEMU -d int address forms with and without selector/0x prefixes:
    #   IP=0008:0000000003cd63c7 pc=0000000003cd63c7
    #   RIP=0x3cd63c7
    local line="$1" tok raw
    tok="$(printf '%s\n' "$line" | grep -oEi '(ip|rip|pc)=(0x)?[0-9a-f:]+' | tail -n 1 || true)"
    [ -z "$tok" ] && { echo ""; return 0; }
    raw="${tok#*=}"
    raw="${raw#0x}"
    raw="${raw##*:}"
    raw="${raw,,}"
    raw="$(printf '%s' "$raw" | sed 's/^0*//')"
    if [ -z "$raw" ]; then raw=0; fi
    printf '%s' "$raw"
}

norm16() {
    local raw="$1"
    while [ ${#raw} -lt 16 ]; do raw="0$raw"; done
    printf '%s' "$raw"
}

# Return the latest QEMU OBJD-T byte block before the fault event that covers
# the faulting IP: <block-start-hex>|<concatenated-bytes>|<byte-offset>.
find_trace_block() {
    local log="$1" line_limit="$2" target="$3"
    local target_num current_addr="" current_bytes="" best_addr="" best_bytes="" best_offset=-1
    local start_num offset raw_bytes
    target_num=$((16#$target))

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*0x([[:xdigit:]]+): ]]; then
            if [ -n "$current_addr" ] && [ -n "$current_bytes" ]; then
                start_num=$((16#$current_addr))
                offset=$((target_num - start_num))
                if (( offset >= 0 && offset * 2 < ${#current_bytes} )); then
                    best_addr="$current_addr"
                    best_bytes="$current_bytes"
                    best_offset="$offset"
                fi
            fi
            current_addr="${BASH_REMATCH[1],,}"
            current_bytes=""
        elif [[ "$line" == *OBJD-T:* ]]; then
            raw_bytes="${line#*OBJD-T:}"
            raw_bytes="${raw_bytes//[^[:xdigit:]]/}"
            current_bytes+="${raw_bytes,,}"
        fi
    done < <(sed -n "1,${line_limit}p" "$log")

    if [ -n "$current_addr" ] && [ -n "$current_bytes" ]; then
        start_num=$((16#$current_addr))
        offset=$((target_num - start_num))
        if (( offset >= 0 && offset * 2 < ${#current_bytes} )); then
            best_addr="$current_addr"
            best_bytes="$current_bytes"
            best_offset="$offset"
        fi
    fi

    if (( best_offset >= 0 )); then
        printf '%s|%s|%s\n' "$best_addr" "$best_bytes" "$best_offset"
    fi
}

hex_to_file() {
    local hex="$1" output="$2" i
    : > "$output"
    for ((i = 0; i + 1 < ${#hex}; i += 2)); do
        printf '%b' "\\x${hex:i:2}" >> "$output"
    done
}

decode_bytes_at_ip() {
    local hex="$1" target="$2" tmp decoded
    command -v objdump >/dev/null 2>&1 || return 0
    tmp="$(mktemp "${TMPDIR:-/tmp}/aweos-instrtrace.XXXXXX")" || return 0
    hex_to_file "$hex" "$tmp"
    decoded="$(objdump -D -b binary -m i386:x86-64 -Mintel --adjust-vma="0x${target}" "$tmp" 2>/dev/null | awk '/^[[:space:]]*[[:xdigit:]]+:/ { print; if (++count == 3) exit }' || true)"
    rm -f -- "$tmp"
    if [ -n "$decoded" ]; then
        printf '%s\n' "$decoded"
    fi
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

    local first_ud last_fault fault_line fault_line_number
    first_ud="$(grep -E 'v=06' "$log" | head -n 1 || true)"
    last_fault="$(grep -E 'v=0[68d]' "$log" | tail -n 1 || true)"
    if [ -z "$last_fault" ]; then
        echo "No CPU fault events (v=06/v=08/v=0d) found; last ${MAX_FALLBACK_LINES} log lines follow."
        tail -n "$MAX_FALLBACK_LINES" "$log"
        return 0
    fi

    # The original invalid-opcode (#UD) is the fault to explain; fall back to
    # the last recorded fault event when no invalid-opcode was recorded.
    if [ -n "$first_ud" ]; then
        fault_line="$first_ud"
        fault_line_number="$(grep -n -m1 -E 'v=06' "$log" | cut -d: -f1 || true)"
    else
        fault_line="$last_fault"
        fault_line_number="$(grep -n -E 'v=0[68d]' "$log" | tail -n 1 | cut -d: -f1 || true)"
    fi

    echo "Last fault event:"
    echo "$last_fault"
    echo
    echo "Recent fault events (up to ${MAX_FAULT_EVENTS}):"
    grep -E 'v=0[68d]|check_exception' "$log" | tail -n "$MAX_FAULT_EVENTS" || true

    local raw1 raw2 addr1 addr2 block block_addr block_bytes block_offset instruction_bytes
    raw1="$(parse_fault_addr "$fault_line")"
    raw2="$(parse_fault_addr "$last_fault")"
    addr1="$(norm16 "$raw1")"
    addr2="$(norm16 "$raw2")"
    if [ "$raw1" = "0" ] && [ "$raw2" = "0" ]; then
        echo
        echo "Could not parse a faulting instruction pointer from the fault event line."
        return 0
    fi

    if [ "$raw1" != "0" ]; then
        echo
        echo "Guest instructions around faulting address 0x${addr1}:"
        block=""
        if [ -n "$fault_line_number" ]; then
            block="$(find_trace_block "$log" "$fault_line_number" "$raw1" || true)"
        fi
        if [ -n "$block" ]; then
            IFS='|' read -r block_addr block_bytes block_offset <<< "$block"
            instruction_bytes="${block_bytes:$((block_offset * 2)):30}"
            echo "QEMU trace block: 0x${block_addr} (fault offset ${block_offset} bytes)"
            decoded="$(decode_bytes_at_ip "$instruction_bytes" "$raw1" || true)"
            first_instruction="$(printf '%s\n' "$decoded" | sed -n '1p')"
            decoded_bytes="$(printf '%s\n' "$first_instruction" | sed -E 's/^[[:space:]]*[^:]+:[[:space:]]*//; s/[[:space:]]{2,}.*$//; s/[[:space:]]//g')"
            if [ -n "$decoded_bytes" ]; then
                echo "Faulting instruction bytes: ${decoded_bytes}"
            else
                echo "Instruction stream bytes at faulting address: ${instruction_bytes}"
            fi
            if [ -n "$decoded" ]; then
                echo "Decoded instructions (objdump):"
                printf '%s\n' "$decoded"
            fi
        elif grep -qiE "^0x0*${raw1}:" "$log"; then
            grep -iE "^0x0*${raw1}:" "$log" | head -n 1
        else
            echo "(no instruction-byte block found for 0x${addr1} before the fault event)"
        fi
    fi

    if [ "$raw2" != "0" ] && [ "$addr2" != "$addr1" ]; then
        echo
        echo "Last fault event address: 0x${addr2}"
    fi
    echo
}

for log in "$@"; do
    summarize_log "$log" | head -n "$MAX_LINES_PER_LOG"
done

exit 0
