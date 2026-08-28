#include "ayui_shell.h"
#include "graphics.h"
#include "font.h"
#include <stdio.h>
#include <time.h>
#include <string.h>

void ayui_shell_render_wallpaper(ayui_fb_t *fb, const ayui_theme_t *theme) {
    aweos_gfx_clear(fb, theme->bg);

    /* Subtle geometric grid / gradient accent for AWEOS desktop background */
    int grid_size = 64;
    for (int y = 0; y < (int)fb->height; y += grid_size) {
        aweos_gfx_fill_rect(fb, 0, y, fb->width, 1, 0x00152230);
    }
    for (int x = 0; x < (int)fb->width; x += grid_size) {
        aweos_gfx_fill_rect(fb, x, 0, 1, fb->height, 0x00152230);
    }

    /* Central subtle watermark branding */
    const char *brand = "AWEOS  |  AYUI Desktop Environment";
    int bw = string_width(brand);
    int bx = (fb->width - bw) / 2;
    int by = (fb->height - FONT_HEIGHT) / 2;
    draw_string(fb->back_buffer, fb->pitch_pixels, bx, by, brand, 0x002B3E50, 0, 1);
}

void ayui_shell_render_panel(ayui_session_t *s) {
    ayui_fb_t *fb = &s->fb;
    const ayui_theme_t *t = &s->theme;

    /* Top Panel Bar (30px high) */
    aweos_gfx_fill_rect(fb, 0, 0, fb->width, 30, t->panel);
    aweos_gfx_fill_rect(fb, 0, 29, fb->width, 1, t->border);

    /* AYUI Menu / Launcher Button */
    uint32_t btn_color = s->launcher_open ? t->title_active : t->button;
    aweos_gfx_fill_rect(fb, 6, 4, 100, 22, btn_color);
    aweos_gfx_draw_rect(fb, 6, 4, 100, 22, t->border);
    draw_string(fb->back_buffer, fb->pitch_pixels, 14, 7, "AYUI Menu", t->white, 0, 1);

    /* OS Branding */
    draw_string(fb->back_buffer, fb->pitch_pixels, 120, 7, "AWEOS v1.0.0", t->white, 0, 1);

    /* Active Window Indicators on Panel */
    int x_off = 240;
    for (int i = 0; i < s->window_count; i++) {
        ayui_window_t *w = &s->windows[i];
        if (!w->visible) continue;
        uint32_t w_bg = w->focused ? t->title_active : t->title_inactive;
        aweos_gfx_fill_rect(fb, x_off, 4, 130, 22, w_bg);
        aweos_gfx_draw_rect(fb, x_off, 4, 130, 22, t->border);
        draw_string_clipped(fb->back_buffer, fb->pitch_pixels, x_off + 6, 7, w->title, t->text, 118);
        x_off += 136;
        if (x_off > (int)fb->width - 240) break;
    }

    /* System Status Indicators (Right Aligned) */
    /* Network Indicator */
    draw_string(fb->back_buffer, fb->pitch_pixels, fb->width - 220, 7, "[NET: UP]", t->green, 0, 1);

    /* Storage Indicator */
    draw_string(fb->back_buffer, fb->pitch_pixels, fb->width - 140, 7, "[SSD: OK]", t->yellow, 0, 1);

    /* Clock */
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    char time_str[32];
    if (tm_info) strftime(time_str, sizeof(time_str), "%H:%M:%S", tm_info);
    else snprintf(time_str, sizeof(time_str), "12:00:00");
    draw_string(fb->back_buffer, fb->pitch_pixels, fb->width - 65, 7, time_str, t->white, 0, 1);
}

void ayui_shell_render_launcher(ayui_session_t *s) {
    ayui_fb_t *fb = &s->fb;
    const ayui_theme_t *t = &s->theme;

    int lw = 260;
    int lh = 320;
    int lx = 6;
    int ly = 32;

    /* Drop shadow + Menu Window */
    aweos_gfx_fill_rect(fb, lx + 4, ly + 4, lw, lh, 0x0005080C);
    aweos_gfx_fill_rect(fb, lx, ly, lw, lh, t->panel);
    aweos_gfx_draw_rect(fb, lx, ly, lw, lh, t->border);

    draw_string(fb->back_buffer, fb->pitch_pixels, lx + 12, ly + 10, "AYUI Applications", t->yellow, 0, 1);
    aweos_gfx_fill_rect(fb, lx + 10, ly + 28, lw - 20, 1, t->border);

    for (int i = 0; i < s->app_count; i++) {
        int app_y = ly + 34 + i * 24;
        if (app_y + 22 > ly + lh) break;

        /* Highlight hovered item */
        if (s->cursor_x >= lx + 10 && s->cursor_x <= lx + lw - 10 &&
            s->cursor_y >= app_y && s->cursor_y < app_y + 22) {
            aweos_gfx_fill_rect(fb, lx + 8, app_y, lw - 16, 22, t->selection);
        }

        char app_label[96];
        snprintf(app_label, sizeof(app_label), "%d. %s", i + 1, s->apps[i].name);
        draw_string_clipped(fb->back_buffer, fb->pitch_pixels, lx + 14, app_y + 3, app_label, t->text, lw - 28);
    }
}

void ayui_shell_render_cursor(ayui_fb_t *fb, int x, int y) {
    static const char *cursor_bmp[] = {
        "X           ",
        "XX          ",
        "X.X         ",
        "X..X        ",
        "X...X       ",
        "X....X      ",
        "X.....X     ",
        "X......X    ",
        "X.......X   ",
        "X.....XXXX  ",
        "X..X..X     ",
        "X.X X..X    ",
        "XX   X..X   ",
        "X     X..X  ",
        "       XX   ",
    };

    for (int r = 0; r < 15; r++) {
        for (int c = 0; c < 12; c++) {
            char p = cursor_bmp[r][c];
            int px = x + c;
            int py = y + r;
            if (px >= 0 && px < (int)fb->width && py >= 0 && py < (int)fb->height) {
                if (p == 'X') {
                    fb->back_buffer[py * fb->pitch_pixels + px] = 0x00000000;
                } else if (p == '.') {
                    fb->back_buffer[py * fb->pitch_pixels + px] = 0x00FFFFFF;
                }
            }
        }
    }
}
