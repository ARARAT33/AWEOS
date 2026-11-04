#!/usr/bin/env bash
# Exercise pixel packing and visible-region writes for Linux framebuffer layouts.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-ayui-fb-format.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT

cat > "$tmp_root/test.c" <<'C_SOURCE'
#include "graphics.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

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

    /* The visible image may start inside a larger virtual framebuffer. */
    uint8_t front[64];
    const uint8_t sentinel = 0xa5;
    memset(front, sentinel, sizeof(front));
    uint32_t back[4] = {0x00112233U, 0x00445566U, 0x00778899U, 0x00aabbccU};
    aweos_fb_t output = {
        .width = 2, .height = 2, .bpp = 32,
        .pitch_bytes = 16, .pitch_pixels = 2,
        .xoffset = 1, .yoffset = 1, .screen_size = sizeof(front),
        .red_offset = 16, .red_length = 8,
        .green_offset = 8, .green_length = 8,
        .blue_offset = 0, .blue_length = 8,
        .front_buffer = front, .back_buffer = back
    };
    aweos_gfx_swap_buffers(&output);

    const size_t expected_offsets[4] = {20, 24, 36, 40};
    for (size_t pixel = 0; pixel < 4; pixel++) {
        assert(memcmp(front + expected_offsets[pixel], &back[pixel], sizeof(uint32_t)) == 0);
    }
    for (size_t byte = 0; byte < sizeof(front); byte++) {
        int is_pixel = 0;
        for (size_t pixel = 0; pixel < 4; pixel++) {
            if (byte >= expected_offsets[pixel] && byte < expected_offsets[pixel] + sizeof(uint32_t)) {
                is_pixel = 1;
                break;
            }
        }
        if (!is_pixel) assert(front[byte] == sentinel);
    }

    /* A truncated mapped-memory extent must reject the whole frame, not write partially. */
    memset(front, sentinel, sizeof(front));
    output.screen_size = 24;
    aweos_gfx_swap_buffers(&output);
    for (size_t byte = 0; byte < sizeof(front); byte++) assert(front[byte] == sentinel);

    puts("PASS: RGB565, 24-bit BGR, 32-bit XRGB, overlap rejection, virtual offsets, and mapped-memory bounds.");
    return 0;
}
C_SOURCE

cc -std=c11 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined \
    -fno-omit-frame-pointer -I"$repo_root/src/gui" \
    "$tmp_root/test.c" "$repo_root/src/gui/graphics.c" -o "$tmp_root/test"
"$tmp_root/test"
