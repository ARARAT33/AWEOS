#!/bin/sh
# Keep PID 1 alive if a desktop or installer process fails or exits.
# A failed GUI must not panic the kernel by allowing the init process to exit.
set -u

SESSION_BIN="${1:-/usr/bin/aweui}"
RECOVERY_SHELL="${2:-/bin/busybox}"

if [ ! -x "$SESSION_BIN" ]; then
    status=127
    echo "AWEOS session executable is missing or not executable: $SESSION_BIN" >&2
else
    echo "Starting AWEOS session: $SESSION_BIN"
    status=0
    "$SESSION_BIN" || status=$?
fi

if [ "$status" -eq 0 ]; then
    echo "AWEOS session exited normally; returning to the recovery console."
else
    echo "AWEOS session failed with exit status $status; starting the recovery console." >&2
fi

echo "AWEOS RECOVERY SHELL READY"
if [ -f "$RECOVERY_SHELL" ] && [ -x "$RECOVERY_SHELL" ]; then
    while :; do
        "$RECOVERY_SHELL" cttyhack /bin/sh || true
        echo "AWEOS recovery shell exited; reopening the console."
        /bin/busybox sleep 1
    done
fi

echo "ERROR: recovery shell is unavailable; keeping PID 1 alive." >&2
while :; do
    /bin/busybox sleep 3600
done
