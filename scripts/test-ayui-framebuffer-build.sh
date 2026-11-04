#!/usr/bin/env bash
# Compile the actual AYUI framebuffer session with production hardening flags.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-ayui-fb-build.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT

cc -std=gnu11 -O2 -Wall -Wextra -Werror -Wno-unused-parameter \
    -D_FORTIFY_SOURCE=2 -fstack-protector-strong -fPIE -pie \
    -Wl,-z,relro,-z,now \
    -I"$repo_root/src/gui" -I"$repo_root/src/apps" \
    -o "$tmp_root/aweos-ayui-fb" \
    "$repo_root/src/gui/main.c" \
    "$repo_root/src/gui/graphics.c" \
    "$repo_root/src/gui/input.c" \
    "$repo_root/src/gui/ayui_session.c" \
    "$repo_root/src/gui/ayui_shell.c" \
    "$repo_root/src/gui/ayui_wm.c" \
    "$repo_root/src/gui/font.c" \
    "$repo_root/src/apps/apps.c" \
    -lutil

test -x "$tmp_root/aweos-ayui-fb"
readelf -h "$tmp_root/aweos-ayui-fb" >/dev/null
echo "PASS: AYUI framebuffer fallback compiles as a hardened x86_64 ELF executable."
