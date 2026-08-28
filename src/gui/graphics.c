#include "graphics.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/fb.h>

int aweos_gfx_init(aweos_fb_t *fb, const char *device) {
    memset(fb, 0, sizeof(*fb));
    const char *dev = device ? device : "/dev/fb0";

    fb->fd = open(dev, O_RDWR);
    if (fb->fd < 0) {
        perror("Failed to open framebuffer device");
        return -1;
    }

    struct fb_var_screeninfo vinfo;
    struct fb_fix_screeninfo finfo;

    if (ioctl(fb->fd, FBIOGET_FSCREENINFO, &finfo) < 0) {
        perror("FBIOGET_FSCREENINFO failed");
        close(fb->fd);
        return -1;
    }

    if (ioctl(fb->fd, FBIOGET_VSCREENINFO, &vinfo) < 0) {
        perror("FBIOGET_VSCREENINFO failed");
        close(fb->fd);
        return -1;
    }

    fb->width = vinfo.xres;
    fb->height = vinfo.yres;
    fb->bpp = vinfo.bits_per_pixel;
    fb->pitch_bytes = finfo.line_length;
    fb->pitch_pixels = finfo.line_length / (fb->bpp / 8);
    fb->screen_size = finfo.smem_len;

    fb->front_buffer = (uint32_t *)mmap(0, fb->screen_size, PROT_READ | PROT_WRITE, MAP_SHARED, fb->fd, 0);
    if (fb->front_buffer == MAP_FAILED) {
        perror("mmap framebuffer failed");
        close(fb->fd);
        return -1;
    }

    size_t back_size = (size_t)fb->height * fb->pitch_pixels * sizeof(uint32_t);
    fb->back_buffer = (uint32_t *)malloc(back_size);
    if (!fb->back_buffer) {
        perror("Failed to allocate back buffer");
        munmap(fb->front_buffer, fb->screen_size);
        close(fb->fd);
        return -1;
    }

    memset(fb->back_buffer, 0, back_size);
    return 0;
}

void aweos_gfx_close(aweos_fb_t *fb) {
    if (fb->back_buffer) free(fb->back_buffer);
    if (fb->front_buffer && fb->front_buffer != MAP_FAILED) munmap(fb->front_buffer, fb->screen_size);
    if (fb->fd >= 0) close(fb->fd);
    memset(fb, 0, sizeof(*fb));
}

void aweos_gfx_swap_buffers(aweos_fb_t *fb) {
    size_t copy_size = (size_t)fb->height * fb->pitch_pixels * sizeof(uint32_t);
    if (copy_size > fb->screen_size) copy_size = fb->screen_size;
    memcpy(fb->front_buffer, fb->back_buffer, copy_size);
}

void aweos_gfx_clear(aweos_fb_t *fb, uint32_t color) {
    size_t total_pixels = (size_t)fb->height * fb->pitch_pixels;
    for (size_t i = 0; i < total_pixels; i++) {
        fb->back_buffer[i] = color;
    }
}

void aweos_gfx_fill_rect(aweos_fb_t *fb, int x, int y, int w, int h, uint32_t color) {
    if (x >= (int)fb->width || y >= (int)fb->height || x + w <= 0 || y + h <= 0) return;
    int x1 = x < 0 ? 0 : x;
    int y1 = y < 0 ? 0 : y;
    int x2 = (x + w) > (int)fb->width ? (int)fb->width : (x + w);
    int y2 = (y + h) > (int)fb->height ? (int)fb->height : (y + h);

    for (int py = y1; py < y2; py++) {
        uint32_t *row = &fb->back_buffer[py * fb->pitch_pixels];
        for (int px = x1; px < x2; px++) {
            row[px] = color;
        }
    }
}

void aweos_gfx_draw_rect(aweos_fb_t *fb, int x, int y, int w, int h, uint32_t color) {
    aweos_gfx_fill_rect(fb, x, y, w, 1, color);
    aweos_gfx_fill_rect(fb, x, y + h - 1, w, 1, color);
    aweos_gfx_fill_rect(fb, x, y, 1, h, color);
    aweos_gfx_fill_rect(fb, x + w - 1, y, 1, h, color);
}
