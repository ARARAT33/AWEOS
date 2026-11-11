#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aweos-rootfs-validator-test.XXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

BUILD_DIR="$TEMP_ROOT/build"
ROOTFS_DIR="$BUILD_DIR/rootfs"

mkdir -p "$ROOTFS_DIR"/{bin,dev,etc,home,proc,root,run,sbin,sys,tmp,usr/bin,usr/lib,usr/share/applications,usr/share/wayland-sessions,var/log,etc/aweos,etc/aweui}

printf '%s\n' 'root:x:0:0:root:/root:/bin/sh' 'aweos:x:1000:1000:AWEOS User:/home/aweos:/bin/sh' > "$ROOTFS_DIR/etc/passwd"
printf '%s\n' 'root:x:0:' 'aweos:x:1000:' > "$ROOTFS_DIR/etc/group"
printf '%s\n' 'root:*:19700:0:99999:7:::' > "$ROOTFS_DIR/etc/shadow"
printf '%s\n' 'NAME="AWEOS"' > "$ROOTFS_DIR/etc/os-release"
printf '%s\n' 'NETWORK_AUTO=true' > "$ROOTFS_DIR/etc/aweos/config"
printf '%s\n' '[desktop]' > "$ROOTFS_DIR/etc/aweui/config.toml"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$ROOTFS_DIR/sbin/init"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$ROOTFS_DIR/bin/busybox"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$ROOTFS_DIR/usr/bin/aweui"
chmod 0755 "$ROOTFS_DIR/sbin/init" "$ROOTFS_DIR/bin/busybox" "$ROOTFS_DIR/usr/bin/aweui"
printf '%s\n' '[Desktop Entry]' 'Exec=/usr/bin/aweui' > "$ROOTFS_DIR/usr/share/wayland-sessions/ayui.desktop"

# Exercise the same Makefile target used by the image build.
make --no-print-directory -s -C "$REPO_ROOT" validate-rootfs BUILD_DIR="$BUILD_DIR"

# Missing boot-critical configuration must fail closed.
rm -f "$ROOTFS_DIR/etc/aweos/config"
if make --no-print-directory -s -C "$REPO_ROOT" validate-rootfs BUILD_DIR="$BUILD_DIR" >"$TEMP_ROOT/invalid.out" 2>&1; then
    echo "ERROR: rootfs validator accepted a missing required configuration file." >&2
    exit 1
fi
grep -Fq 'required rootfs file is missing or empty: /etc/aweos/config' "$TEMP_ROOT/invalid.out"

echo "PASS: Makefile invokes the rootfs validator and invalid rootfs layouts are rejected."
