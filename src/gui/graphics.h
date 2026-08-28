#ifndef AWEOS_GRAPHICS_H
#define AWEOS_GRAPHICS_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    int fd;
    uint32_t width;
    uint32_t height;
    uint32_t bpp;
    uint32_t pitch_bytes;
    uint32_t pitch_pixels;
    size_t screen_size;
    uint32_t *front_buffer;
    uint32_t *back_buffer;
} aweos_fb_t;

int aweos_gfx_init(aweos_fb_t *fb, const char *device);
void aweos_gfx_close(aweos_fb_t *fb);
void aweos_gfx_swap_buffers(aweos_fb_t *fb);
void aweos_gfx_clear(aweos_fb_t *fb, uint32_t color);
void aweos_gfx_fill_rect(aweos_fb_t *fb, int x, int y, int w, int h, uint32_t color);
void aweos_gfx_draw_rect(aweos_fb_t *fb, int x, int y, int w, int h, uint32_t color);

#endif
