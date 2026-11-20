#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aweos-kernel-config-test.XXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT
GOOD_CONFIG="$TEMP_ROOT/good.config"
cat > "$GOOD_CONFIG" <<'CONFIG'
CONFIG_BLK_DEV_INITRD=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_EXT4_FS=y
CONFIG_ISO9660_FS=y
CONFIG_BLK_DEV_LOOP=y
CONFIG_SCSI=y
CONFIG_CDROM=y
CONFIG_BLK_DEV_SR=y
CONFIG_BLK_DEV_SD=y
CONFIG_ATA=y
CONFIG_SATA_AHCI=y
CONFIG_UNRELATED_OPTION=m
CONFIG
bash "$SCRIPT_DIR/verify-kernel-config.sh" "$GOOD_CONFIG" >/dev/null
MISSING_SR="$TEMP_ROOT/missing-sr.config"
grep -v '^CONFIG_BLK_DEV_SR=y$' "$GOOD_CONFIG" > "$MISSING_SR"
if bash "$SCRIPT_DIR/verify-kernel-config.sh" "$MISSING_SR" >"$TEMP_ROOT/missing.out" 2>&1; then
    echo "ERROR: kernel config verifier accepted a missing SCSI CD-ROM driver." >&2; exit 1
fi
grep -Fq 'CONFIG_BLK_DEV_SR must be built into the kernel (=y)' "$TEMP_ROOT/missing.out"
MODULE_SR="$TEMP_ROOT/module-sr.config"
sed 's/^CONFIG_BLK_DEV_SR=y$/CONFIG_BLK_DEV_SR=m/' "$GOOD_CONFIG" > "$MODULE_SR"
if bash "$SCRIPT_DIR/verify-kernel-config.sh" "$MODULE_SR" >"$TEMP_ROOT/module.out" 2>&1; then
    echo "ERROR: kernel config verifier accepted a module-only SCSI CD-ROM driver." >&2; exit 1
fi
grep -Fq 'CONFIG_BLK_DEV_SR must be built into the kernel (=y)' "$TEMP_ROOT/module.out"
if bash "$SCRIPT_DIR/verify-kernel-config.sh" "$TEMP_ROOT/not-found.config" >"$TEMP_ROOT/missing-file.out" 2>&1; then
    echo "ERROR: kernel config verifier accepted a missing configuration file." >&2; exit 1
fi
grep -Fq 'kernel configuration file is missing' "$TEMP_ROOT/missing-file.out"
grep -Fq -- '--enable CONFIG_BLK_DEV_SR' "$SCRIPT_DIR/config-kernel.sh"
grep -Fq 'verify-kernel-config.sh' "$SCRIPT_DIR/config-kernel.sh"
grep -Fq -- '--disable CONFIG_X86_NATIVE_CPU' "$SCRIPT_DIR/config-kernel.sh"
grep -Fq -- '-march=x86-64 -mtune=generic -mno-bmi -mno-bmi2' "$SCRIPT_DIR/../Makefile"
grep -Fq -- '-j"$$(nproc)"' "$SCRIPT_DIR/../Makefile"
if [ ! -x "$SCRIPT_DIR/config-kernel.sh" ]; then
    echo "ERROR: config-kernel.sh must remain executable because the Makefile invokes it directly." >&2
    exit 1
fi
echo "PASS: required boot storage drivers are built in and kernel build enforces portable x86-64 flags without native CPU leakage."
