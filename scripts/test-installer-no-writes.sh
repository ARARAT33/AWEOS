#!/usr/bin/env bash
set -euo pipefail

binary="${1:-target/release/aweui-installer}"
test -x "$binary" || {
    echo "ERROR: installer binary is missing or not executable: $binary" >&2
    exit 1
}

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-installer-no-writes.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT

set +e
AWEOS_ALLOW_DESTRUCTIVE_INSTALL=1 "$binary" --auto >"$tmp_root/auto.log" 2>&1
status=$?
set -e

if [ "$status" -ne 2 ]; then
    echo "ERROR: --auto should exit 2 even when the legacy destructive override is set (got $status)." >&2
    cat "$tmp_root/auto.log" >&2
    exit 1
fi
grep -Fq "Disabled for data safety" "$tmp_root/auto.log"
grep -Fq "no disk operations were attempted" "$tmp_root/auto.log"
if grep -qiE "Partitioning disk|sfdisk|mkfs[.](vfat|ext4)|Formatting target" "$tmp_root/auto.log"; then
    echo "ERROR: blocked --auto path emitted a disk-write operation." >&2
    exit 1
fi

"$binary" --test >"$tmp_root/test.log" 2>&1
grep -Fq "DISK INSTALLATION IS DISABLED" "$tmp_root/test.log"
grep -Fq "No disk, partition, filesystem, bootloader, or user data will be changed" "$tmp_root/test.log"
grep -Fq "[INSTALLER TEST] PASS" "$tmp_root/test.log"

echo "PASS: built Rust installer refuses --auto even with the legacy override, reports the safety hold, and performs no disk operation."
