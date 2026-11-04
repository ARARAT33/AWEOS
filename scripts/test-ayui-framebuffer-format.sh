#!/usr/bin/env bash
# Exercise pixel packing for common 16/24/32-bpp Linux framebuffer layouts.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-ayui-fb-format.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT

cat > "$tmp_root/test.c" <<'C_SOURCE'
#include "graphics.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>

int main(void) {
    uint32_t packed = 0;
    aweos_fb_t fb = {
        .bpp = 32,
        .red_offset = 16, .red_length = 8,
        .green_offset = 8, .green_length = 8,
        .blue_offset = 0, .blue_length = 8
    };
    assert(aweos_gfx_pack_pixel(&fb, 0x00123456U, &packed) == 0);
    assert(packed == 0x00123456U);

    fb = (aweos_fb_t){
        .bpp = 16,
        .red_offset = 11, .red_length = 5,
        .green_offset = 5, .green_length = 6,
        .blue_offset = 0, .blue_length = 5
    };
    assert(aweos_gfx_pack_pixel(&fb, 0x00ff0000U, &packed) == 0 && packed == 0xf800U);
    assert(aweos_gfx_pack_pixel(&fb, 0x0000ff00U, &packed) == 0 && packed == 0x07e0U);
    assert(aweos_gfx_pack_pixel(&fb, 0x000000ffU, &packed) == 0 && packed == 0x001fU);

    fb = (aweos_fb_t){
        .bpp = 24,
        .red_offset = 0, .red_length = 8,
        .green_offset = 8, .green_length = 8,
        .blue_offset = 16, .blue_length = 8
    };
    assert(aweos_gfx_pack_pixel(&fb, 0x00ff0000U, &packed) == 0 && packed == 0x000000ffU);

    fb.green_offset = fb.red_offset;
    assert(aweos_gfx_pack_pixel(&fb, 0x00ffffffU, &packed) != 0);

    puts("PASS: RGB565, 24-bit BGR, 32-bit XRGB and invalid overlapping layouts.");
    return 0;
}
C_SOURCE

cc -std=c11 -O2 -Wall -Wextra -Werror -I"$repo_root/src/gui" \
    "$tmp_root/test.c" "$repo_root/src/gui/graphics.c" -o "$tmp_root/test"
"$tmp_root/test"
