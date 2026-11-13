#!/usr/bin/env bash
# Verify that a built BusyBox binary really contains every required applet.
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "ERROR: usage: $0 <busybox-binary> <required-applet>..." >&2
    exit 2
fi

binary="$1"
shift
if [[ ! -x "$binary" ]]; then
    echo "ERROR: BusyBox binary is missing or not executable: $binary" >&2
    exit 2
fi

if ! applets="$("$binary" --list)"; then
    echo "ERROR: could not list applets from BusyBox binary: $binary" >&2
    exit 1
fi

for applet in "$@"; do
    if ! grep -Fqx -- "$applet" <<<"$applets"; then
        echo "ERROR: baseline BusyBox is missing required applet: $applet" >&2
        exit 1
    fi
done

echo "PASS: BusyBox provides all required applets."
