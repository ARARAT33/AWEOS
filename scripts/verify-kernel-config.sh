#!/bin/bash
set -euo pipefail
CONFIG_FILE="${1:-build/linux-x86_64/.config}"
fail() { echo "ERROR: $*" >&2; exit 1; }
[ -f "$CONFIG_FILE" ] || fail "kernel configuration file is missing: $CONFIG_FILE"
require_builtin() {
    local symbol="$1"
    local actual
    if grep -qx "CONFIG_${symbol}=y" "$CONFIG_FILE"; then return 0; fi
    actual="$(grep -E "^(CONFIG_${symbol}=|# CONFIG_${symbol} is not set$)" "$CONFIG_FILE" || true)"
    [ -n "$actual" ] || actual="unset"
    fail "CONFIG_${symbol} must be built into the kernel (=y), found: $actual"
}
for symbol in BLK_DEV_INITRD DEVTMPFS DEVTMPFS_MOUNT EXT4_FS ISO9660_FS BLK_DEV_LOOP SCSI CDROM BLK_DEV_SR BLK_DEV_SD ATA SATA_AHCI; do
    require_builtin "$symbol"
done
echo "AWEOS kernel boot-storage configuration verified: $CONFIG_FILE"
