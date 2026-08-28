#ifndef AWEOS_GRAPHICS_H
#define AWEOS_GRAPHICS_H

#include "ayui.h"

typedef ayui_fb_t aweos_fb_t;

int aweos_gfx_init(aweos_fb_t *fb, const char *device);
void aweos_gfx_close(aweos_fb_t *fb);
void aweos_gfx_swap_buffers(aweos_fb_t *fb);
void aweos_gfx_clear(aweos_fb_t *fb, uint32_t color);
void aweos_gfx_fill_rect(aweos_fb_t *fb, int x, int y, int w, int h, uint32_t color);
void aweos_gfx_draw_rect(aweos_fb_t *fb, int x, int y, int w, int h, uint32_t color);
void aweos_gfx_draw_line(aweos_fb_t *fb, int x0, int y0, int x1, int y1, uint32_t color);

#endif
