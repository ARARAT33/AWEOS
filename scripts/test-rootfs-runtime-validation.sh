#!/usr/bin/env bash
# Verify rootfs validation catches a non-executable ELF interpreter and accepts
# the same runtime after the interpreter permission is corrected.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-rootfs-runtime.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT
rootfs="${tmp_root}/rootfs"

mkdir -p "${rootfs}"/{bin,sbin,dev,etc,home,proc,root,run,sys,tmp,usr/bin,usr/lib,usr/share/applications,usr/share/wayland-sessions,var/log}
mkdir -p "${rootfs}/etc/aweos" "${rootfs}/etc/aweui"
printf 'root:x:0:0:root:/root:/bin/sh\naweos:x:1000:1000:AWEOS:/home/aweos:/bin/sh\n' > "${rootfs}/etc/passwd"
printf 'root:x:0:\naweos:x:1000:\n' > "${rootfs}/etc/group"
printf 'root:*:19700:0:99999:7:::\naweos:*:19700:0:99999:7:::\n' > "${rootfs}/etc/shadow"
printf 'NAME=AWEOS\n' > "${rootfs}/etc/os-release"
printf 'AUTOLOGIN=true\n' > "${rootfs}/etc/aweos/config"
printf '[desktop]\ntheme = "test"\n' > "${rootfs}/etc/aweui/config.toml"
printf '#!/bin/sh\nexec /bin/sh\n' > "${rootfs}/sbin/init"
printf '#!/bin/sh\nexit 0\n' > "${rootfs}/bin/busybox"
chmod 0755 "${rootfs}/sbin/init" "${rootfs}/bin/busybox"
printf '[Desktop Entry]\nExec=/usr/bin/aweui\n' > "${rootfs}/usr/share/wayland-sessions/ayui.desktop"

cat > "${tmp_root}/main.c" <<'C_SOURCE'
#include <stdio.h>
int main(void) { puts("AWEOS runtime probe"); return 0; }
C_SOURCE
cc -o "${rootfs}/usr/bin/aweui" "${tmp_root}/main.c"

interpreter="$(readelf -l "${rootfs}/usr/bin/aweui" | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' | head -n 1)"
test -n "$interpreter"
install -D -m 0644 "$interpreter" "${rootfs}${interpreter}"

ldd "${rootfs}/usr/bin/aweui" |
    awk '$2 == "=>" && $3 ~ /^\// {print $3} $1 ~ /^\/lib/ {print $1}' |
    while IFS= read -r lib; do
        [ -f "$lib" ] || continue
        install -D -m 0644 "$lib" "${rootfs}${lib}"
    done

if bash "${repo_root}/scripts/validate-rootfs-layout.sh" "${tmp_root}" > "${tmp_root}/expected-failure.log" 2>&1; then
    echo "ERROR: rootfs validator accepted a non-executable ELF interpreter." >&2
    exit 1
fi
grep -Fq "ELF interpreter is missing or not executable" "${tmp_root}/expected-failure.log"

chmod 0755 "${rootfs}${interpreter}"
bash "${repo_root}/scripts/validate-rootfs-layout.sh" "${tmp_root}"

echo "PASS: rootfs validation rejects a non-executable ELF interpreter and accepts the corrected runtime."
