#!/usr/bin/env bash
# Re-run a failed QEMU boot with a narrow in_asm trace around a userspace RIP.
set -euo pipefail

if [ "\${#}" -lt 3 ]; then
    echo "usage: $0 <serial-log> <trace-log> <qemu-command> [args...]" >&2
    exit 2
fi

serial_log="$1"
trace_log="$2"
shift 2
if [ ! -s "$serial_log" ]; then
    echo "ERROR: serial log is missing or empty: $serial_log" >&2
    exit 2
fi

rip="$(sed -nE 's/.*RIP: 0033:0x([[:xdigit:]]+).*/\1/p' "$serial_log" | head -n 1)"
if [ -z "$rip" ]; then
    echo "ERROR: no user-mode RIP was found in $serial_log" >&2
    exit 2
fi

rip_value=$((16#$rip))
lower=$((rip_value > 256 ? rip_value - 256 : 0))
upper=$((rip_value + 256))
printf -v filter '0x%x-0x%x' "$lower" "$upper"

mkdir -p "$(dirname "$trace_log")"
rm -f "$trace_log"
status=0
timeout "\${AWEOS_QEMU_TRACE_TIMEOUT:-15s}" "$@" -d int,in_asm -D "$trace_log" -dfilter "$filter" >/dev/null 2>&1 || status=$?

if [ ! -s "$trace_log" ]; then
    echo "ERROR: QEMU produced no targeted instruction trace (exit status $status)." >&2
    exit 1
fi

echo "Captured user-mode RIP 0x$rip with QEMU filter $filter (QEMU exit status $status)."
echo "Targeted instruction trace: $trace_log"
tail -n 120 "$trace_log"
