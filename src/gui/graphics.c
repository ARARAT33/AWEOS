#define _GNU_SOURCE
#include "graphics.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

static uint64_t bitfield_mask(uint32_t offset, uint32_t length) {
    if (offset > 32 || length == 0 || length > 16 || length > 32 - offset) return 0;
    return ((UINT64_C(1) << length) - 1U) << offset;
}

int aweos_gfx_pack_pixel(const aweos_fb_t *fb, uint32_t rgb, uint32_t *packed) {
    if (!fb || !packed) return -1;
    if (fb->bpp != 16 && fb->bpp != 24 && fb->bpp != 32) return -1;

    const uint64_t red_mask = bitfield_mask(fb->red_offset, fb->red_length);
    const uint64_t green_mask = bitfield_mask(fb->green_offset, fb->green_length);
    const uint64_t blue_mask = bitfield_mask(fb->blue_offset, fb->blue_length);
    const uint64_t alpha_mask = fb->transp_length
        ? bitfield_mask(fb->transp_offset, fb->transp_length) : 0;

    if (!red_mask || !green_mask || !blue_mask ||
        (fb->transp_length && !alpha_mask)) return -1;
    if ((red_mask & green_mask) || (red_mask & blue_mask) ||
        (green_mask & blue_mask) || (alpha_mask & (red_mask | green_mask | blue_mask))) {
        return -1;
    }
    if (fb->red_offset > fb->bpp || fb->red_length > fb->bpp - fb->red_offset ||
        fb->green_offset > fb->bpp || fb->green_length > fb->bpp - fb->green_offset ||
        fb->blue_offset > fb->bpp || fb->blue_length > fb->bpp - fb->blue_offset ||
        (fb->transp_length && (fb->transp_offset > fb->bpp ||
         fb->transp_length > fb->bpp - fb->transp_offset))) return -1;

    const uint8_t red = (uint8_t)((rgb >> 16) & 0xffU);
    const uint8_t green = (uint8_t)((rgb >> 8) & 0xffU);
    const uint8_t blue = (uint8_t)(rgb & 0xffU);
    const uint32_t red_max = (UINT32_C(1) << fb->red_length) - 1U;
    const uint32_t green_max = (UINT32_C(1) << fb->green_length) - 1U;
    const uint32_t blue_max = (UINT32_C(1) << fb->blue_length) - 1U;

    uint32_t value = (uint32_t)((((uint64_t)red * red_max + 127U) / 255U) << fb->red_offset);
    value |= (uint32_t)((((uint64_t)green * green_max + 127U) / 255U) << fb->green_offset);
    value |= (uint32_t)((((uint64_t)blue * blue_max + 127U) / 255U) << fb->blue_offset);

    if (fb->transp_length) {
        const uint32_t alpha_max = (UINT32_C(1) << fb->transp_length) - 1U;
        value |= alpha_max << fb->transp_offset;
    }

    *packed = value;
    return 0;
}

int aweos_gfx_init(aweos_fb_t *fb, const char *device) {
    if (!fb) return -1;
    memset(fb, 0, sizeof(*fb));
    fb->fd = -1;

    const char *dev = device ? device : "/dev/fb0";
    fb->fd = open(dev, O_RDWR | O_CLOEXEC);
    if (fb->fd < 0) {
        fprintf(stderr, "AWEOS AYUI: cannot open %s: %s\n", dev, strerror(errno));
        return -1;
    }

    struct fb_var_screeninfo vinfo;
    struct fb_fix_screeninfo finfo;
    if (ioctl(fb->fd, FBIOGET_FSCREENINFO, &finfo) < 0 ||
        ioctl(fb->fd, FBIOGET_VSCREENINFO, &vinfo) < 0) {
        fprintf(stderr, "AWEOS AYUI: cannot query framebuffer %s: %s\n", dev, strerror(errno));
        goto fail;
    }

    if (vinfo.xres == 0 || vinfo.yres == 0 ||
        (vinfo.bits_per_pixel != 16 && vinfo.bits_per_pixel != 24 && vinfo.bits_per_pixel != 32)) {
        fprintf(stderr, "AWEOS AYUI: unsupported framebuffer geometry or pixel depth (%ux%u, %u bpp)\n",
                vinfo.xres, vinfo.yres, vinfo.bits_per_pixel);
        goto fail;
    }

    const uint32_t pixel_bytes = (vinfo.bits_per_pixel + 7U) / 8U;
    const uint64_t minimum_pitch = (uint64_t)vinfo.xres * pixel_bytes;
    const uint64_t required_bytes = (uint64_t)finfo.line_length * vinfo.yres;
    if (finfo.line_length < minimum_pitch || finfo.smem_len == 0 ||
        required_bytes > finfo.smem_len) {
        fprintf(stderr, "AWEOS AYUI: framebuffer pitch or memory length is invalid\n");
        goto fail;
    }

    fb->width = vinfo.xres;
    fb->height = vinfo.yres;
    fb->bpp = vinfo.bits_per_pixel;
    fb->pitch_bytes = finfo.line_length;
    fb->pitch_pixels = (uint32_t)(((uint64_t)finfo.line_length + 3U) / 4U);
    fb->screen_size = finfo.smem_len;
    fb->red_offset = vinfo.red.offset;
    fb->red_length = vinfo.red.length;
    fb->green_offset = vinfo.green.offset;
    fb->green_length = vinfo.green.length;
    fb->blue_offset = vinfo.blue.offset;
    fb->blue_length = vinfo.blue.length;
    fb->transp_offset = vinfo.transp.offset;
    fb->transp_length = vinfo.transp.length;

    uint32_t probe = 0;
    if (aweos_gfx_pack_pixel(fb, 0x00ffffffU, &probe) < 0) {
        fprintf(stderr, "AWEOS AYUI: unsupported framebuffer channel layout\n");
        goto fail;
    }

    const uint64_t back_pixels = (uint64_t)fb->height * fb->pitch_pixels;
    if (back_pixels == 0 || back_pixels > SIZE_MAX / sizeof(uint32_t)) {
        fprintf(stderr, "AWEOS AYUI: framebuffer back-buffer size overflows\n");
        goto fail;
    }

    fb->front_buffer = mmap(NULL, fb->screen_size, PROT_READ | PROT_WRITE,
                            MAP_SHARED, fb->fd, 0);
    if (fb->front_buffer == MAP_FAILED) {
        fb->front_buffer = NULL;
        fprintf(stderr, "AWEOS AYUI: framebuffer mmap failed: %s\n", strerror(errno));
        goto fail;
    }

    fb->back_buffer = calloc((size_t)back_pixels, sizeof(uint32_t));
    if (!fb->back_buffer) {
        fprintf(stderr, "AWEOS AYUI: cannot allocate framebuffer back buffer\n");
        goto fail;
    }

    return 0;

fail:
    aweos_gfx_close(fb);
    return -1;
}

void aweos_gfx_close(aweos_fb_t *fb) {
    if (!fb) return;
    if (fb->back_buffer) free(fb->back_buffer);
    if (fb->front_buffer) munmap(fb->front_buffer, fb->screen_size);
    if (fb->fd >= 0) close(fb->fd);
    memset(fb, 0, sizeof(*fb));
    fb->fd = -1;
}

void aweos_gfx_swap_buffers(aweos_fb_t *fb) {
    if (!fb || !fb->front_buffer || !fb->back_buffer) return;
    const uint32_t pixel_bytes = (fb->bpp + 7U) / 8U;

    for (uint32_t y = 0; y < fb->height; y++) {
        uint8_t *destination = fb->front_buffer + (size_t)y * fb->pitch_bytes;
        const uint32_t *source = fb->back_buffer + (size_t)y * fb->pitch_pixels;
        for (uint32_t x = 0; x < fb->width; x++) {
            uint32_t packed = 0;
            if (aweos_gfx_pack_pixel(fb, source[x], &packed) < 0) return;
            memcpy(destination + (size_t)x * pixel_bytes, &packed, pixel_bytes);
        }
    }
}

void aweos_gfx_clear(aweos_fb_t *fb, uint32_t color) {
    if (!fb || !fb->back_buffer) return;
    const size_t total_pixels = (size_t)fb->height * fb->pitch_pixels;
    for (size_t i = 0; i < total_pixels; i++) fb->back_buffer[i] = color;
}

void aweos_gfx_fill_rect(aweos_fb_t *fb, int x, int y, int w, int h, uint32_t color) {
    if (!fb || !fb->back_buffer || w <= 0 || h <= 0) return;
    const int64_t x_end = (int64_t)x + w;
    const int64_t y_end = (int64_t)y + h;
    if (x >= (int)fb->width || y >= (int)fb->height || x_end <= 0 || y_end <= 0) return;

    const int x1 = x < 0 ? 0 : x;
    const int y1 = y < 0 ? 0 : y;
    const int x2 = x_end > (int64_t)fb->width ? (int)fb->width : (int)x_end;
    const int y2 = y_end > (int64_t)fb->height ? (int)fb->height : (int)y_end;

    for (int py = y1; py < y2; py++) {
        uint32_t *row = &fb->back_buffer[(size_t)py * fb->pitch_pixels];
        for (int px = x1; px < x2; px++) row[px] = color;
    }
}

void aweos_gfx_draw_rect(aweos_fb_t *fb, int x, int y, int w, int h, uint32_t color) {
    if (w <= 0 || h <= 0) return;
    aweos_gfx_fill_rect(fb, x, y, w, 1, color);
    aweos_gfx_fill_rect(fb, x, y + h - 1, w, 1, color);
    aweos_gfx_fill_rect(fb, x, y, 1, h, color);
    aweos_gfx_fill_rect(fb, x + w - 1, y, 1, h, color);
}

void aweos_gfx_draw_line(aweos_fb_t *fb, int x0, int y0, int x1, int y1, uint32_t color) {
    if (!fb || !fb->back_buffer) return;
    int dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
    int dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
    int err = dx + dy, e2;

    while (1) {
        if (x0 >= 0 && x0 < (int)fb->width && y0 >= 0 && y0 < (int)fb->height) {
            fb->back_buffer[(size_t)y0 * fb->pitch_pixels + (size_t)x0] = color;
        }
        if (x0 == x1 && y0 == y1) break;
        e2 = 2 * err;
        if (e2 >= dy) { err += dy; x0 += sx; }
        if (e2 <= dx) { err += dx; y0 += sy; }
    }
}
