#ifndef AWEOS_FONT_H
#define AWEOS_FONT_H

#include <stdint.h>

#define FONT_WIDTH 8
#define FONT_HEIGHT 16

extern const uint8_t aweos_font8x16[256][16];

void draw_char(uint32_t *buffer, int pitch_pixels, int x, int y, char c, uint32_t fg, uint32_t bg, int transparent_bg);
void draw_string(uint32_t *buffer, int pitch_pixels, int x, int y, const char *str, uint32_t fg, uint32_t bg, int transparent_bg);
void draw_string_clipped(uint32_t *buffer, int pitch_pixels, int x, int y, const char *str, uint32_t fg, int max_width);
int string_width(const char *str);

#endif
