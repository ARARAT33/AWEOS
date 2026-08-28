#define _GNU_SOURCE
#include "ayui_wm.h"
#include "graphics.h"
#include "font.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <pty.h>
#include <sys/ioctl.h>

ayui_window_t *ayui_wm_create_window(ayui_session_t *s, int x, int y, int w, int h, const char *title) {
    if (s->window_count >= AYUI_MAX_WINDOWS) return NULL;

    /* Responsive position clamping */
    if (x + w > (int)s->fb.width) x = (s->fb.width - w > 0) ? (s->fb.width - w) / 2 : 10;
    if (y + h > (int)s->fb.height) y = (s->fb.height - h > 0) ? (s->fb.height - h) / 2 : 35;

    ayui_window_t *win = &s->windows[s->window_count];
    memset(win, 0, sizeof(*win));
    win->id = s->window_count + 1;
    win->x = x;
    win->y = y;
    win->width = w;
    win->height = h;
    snprintf(win->title, sizeof(win->title), "%s", title);
    win->visible = true;
    win->focused = true;
    win->pty_fd = -1;

    /* Allocate surface buffer */
    win->surface.width = w;
    win->surface.height = h;
    win->surface.stride = w;
    win->surface.visible = true;
    win->surface.damaged = true;
    win->surface.buffer = (uint32_t *)malloc(w * h * sizeof(uint32_t));
    if (win->surface.buffer) {
        for (int i = 0; i < w * h; i++) win->surface.buffer[i] = s->theme.black;
    }

    ayui_wm_focus_window(s, s->window_count);
    s->window_count++;
    return win;
}

void ayui_wm_close_window(ayui_session_t *s, int window_idx) {
    if (window_idx < 0 || window_idx >= s->window_count) return;

    ayui_window_t *win = &s->windows[window_idx];
    if (win->surface.buffer) {
        free(win->surface.buffer);
        win->surface.buffer = NULL;
    }
    if (win->pty_fd >= 0) {
        close(win->pty_fd);
        win->pty_fd = -1;
    }

    for (int i = window_idx; i < s->window_count - 1; i++) {
        s->windows[i] = s->windows[i + 1];
    }
    s->window_count--;

    if (s->window_count > 0) {
        ayui_wm_focus_window(s, s->window_count - 1);
    } else {
        s->active_window_idx = -1;
    }
}

void ayui_wm_focus_window(ayui_session_t *s, int window_idx) {
    if (window_idx < 0 || window_idx >= s->window_count) return;

    for (int i = 0; i < s->window_count; i++) {
        s->windows[i].focused = (i == window_idx);
    }
    s->active_window_idx = window_idx;
}

int ayui_wm_spawn_terminal(ayui_session_t *s, ayui_window_t *win) {
    (void)s;
    int master_fd;
    struct winsize ws;
    ws.ws_row = AYUI_TERM_ROWS;
    ws.ws_col = AYUI_TERM_COLS;
    ws.ws_xpixel = win->width;
    ws.ws_ypixel = win->height;

    pid_t pid = forkpty(&master_fd, NULL, NULL, &ws);
    if (pid < 0) {
        perror("forkpty failed");
        return -1;
    } else if (pid == 0) {
        setenv("TERM", "xterm", 1);
        setenv("AYUI_SESSION", "1", 1);
        setenv("AWEOS_GUI", "1", 1);
        execl("/bin/sh", "sh", "-l", NULL);
        execl("/bin/busybox", "sh", NULL);
        exit(1);
    }

    int flags = fcntl(master_fd, F_GETFL, 0);
    fcntl(master_fd, F_SETFL, flags | O_NONBLOCK);

    win->pty_fd = master_fd;
    win->child_pid = pid;
    win->cursor_r = 0;
    win->cursor_c = 0;

    for (int r = 0; r < AYUI_TERM_ROWS; r++) {
        for (int c = 0; c < AYUI_TERM_COLS; c++) {
            win->grid[r][c] = ' ';
            win->fg_grid[r][c] = s->theme.text;
        }
    }
    return 0;
}

void ayui_wm_read_pty(ayui_window_t *win) {
    if (win->pty_fd < 0) return;
    char buf[512];
    ssize_t n = read(win->pty_fd, buf, sizeof(buf) - 1);
    if (n <= 0) return;

    static bool in_esc = false;
    static char esc_buf[32];
    static int esc_len = 0;
    static uint32_t current_fg = 0x00E1E6EB;

    for (ssize_t i = 0; i < n; i++) {
        char ch = buf[i];

        if (in_esc) {
            if (esc_len < (int)sizeof(esc_buf) - 1) {
                esc_buf[esc_len++] = ch;
                esc_buf[esc_len] = '\0';
            }
            if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '~') {
                /* End of ANSI escape sequence - parse simple colors */
                if (strstr(esc_buf, "31m")) current_fg = 0x00E63946;
                else if (strstr(esc_buf, "32m")) current_fg = 0x002A9D8F;
                else if (strstr(esc_buf, "33m")) current_fg = 0x00E9C46A;
                else if (strstr(esc_buf, "34m")) current_fg = 0x000080FF;
                else if (strstr(esc_buf, "0m"))  current_fg = 0x00E1E6EB;

                in_esc = false;
                esc_len = 0;
            }
            continue;
        }

        if (ch == '\033') {
            in_esc = true;
            esc_len = 0;
            esc_buf[0] = '\0';
            continue;
        }

        if (ch == '\r') {
            win->cursor_c = 0;
        } else if (ch == '\n') {
            win->cursor_c = 0;
            win->cursor_r++;
            if (win->cursor_r >= AYUI_TERM_ROWS) {
                memmove(win->grid[0], win->grid[1], (AYUI_TERM_ROWS - 1) * AYUI_TERM_COLS);
                memmove(win->fg_grid[0], win->fg_grid[1], (AYUI_TERM_ROWS - 1) * AYUI_TERM_COLS * sizeof(uint32_t));
                for (int c = 0; c < AYUI_TERM_COLS; c++) {
                    win->grid[AYUI_TERM_ROWS - 1][c] = ' ';
                    win->fg_grid[AYUI_TERM_ROWS - 1][c] = current_fg;
                }
                win->cursor_r = AYUI_TERM_ROWS - 1;
            }
        } else if (ch == '\b') {
            if (win->cursor_c > 0) win->cursor_c--;
        } else if (ch == '\t') {
            win->cursor_c = (win->cursor_c + 4) & ~3;
        } else if (ch >= 32 && ch <= 126) {
            if (win->cursor_c >= AYUI_TERM_COLS) {
                win->cursor_c = 0;
                win->cursor_r++;
            }
            if (win->cursor_r >= AYUI_TERM_ROWS) {
                memmove(win->grid[0], win->grid[1], (AYUI_TERM_ROWS - 1) * AYUI_TERM_COLS);
                memmove(win->fg_grid[0], win->fg_grid[1], (AYUI_TERM_ROWS - 1) * AYUI_TERM_COLS * sizeof(uint32_t));
                for (int c = 0; c < AYUI_TERM_COLS; c++) {
                    win->grid[AYUI_TERM_ROWS - 1][c] = ' ';
                    win->fg_grid[AYUI_TERM_ROWS - 1][c] = current_fg;
                }
                win->cursor_r = AYUI_TERM_ROWS - 1;
            }
            win->grid[win->cursor_r][win->cursor_c] = ch;
            win->fg_grid[win->cursor_r][win->cursor_c] = current_fg;
            win->cursor_c++;
        }
    }
}

void ayui_wm_render_window(ayui_session_t *s, ayui_window_t *win) {
    if (!win->visible) return;

    ayui_fb_t *fb = &s->fb;
    const ayui_theme_t *t = &s->theme;

    int title_height = 24;
    /* Drop Shadow & Window Title Frame */
    aweos_gfx_fill_rect(fb, win->x + 4, win->y + 4, win->width + 4, win->height + title_height + 4, 0x0005080C);
    aweos_gfx_fill_rect(fb, win->x, win->y, win->width, title_height, win->focused ? t->title_active : t->title_inactive);
    aweos_gfx_draw_rect(fb, win->x, win->y, win->width, win->height + title_height, t->border);

    /* Title string */
    draw_string_clipped(fb->back_buffer, fb->pitch_pixels, win->x + 8, win->y + 4, win->title, t->white, win->width - 32);

    /* Close Button ('x') */
    aweos_gfx_fill_rect(fb, win->x + win->width - 20, win->y + 4, 16, 16, t->red);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + win->width - 16, win->y + 4, "x", t->white, 0, 1);

    /* Client Workspace Area */
    int client_y = win->y + title_height;
    aweos_gfx_fill_rect(fb, win->x, client_y, win->width, win->height, t->black);

    if (win->render_cb) {
        win->render_cb(fb, win);
    } else if (win->pty_fd >= 0) {
        for (int r = 0; r < AYUI_TERM_ROWS; r++) {
            for (int c = 0; c < AYUI_TERM_COLS; c++) {
                char ch = win->grid[r][c];
                int px = win->x + c * FONT_WIDTH;
                int py = client_y + r * FONT_HEIGHT;
                if (px + FONT_WIDTH <= win->x + win->width && py + FONT_HEIGHT <= client_y + win->height) {
                    if (r == win->cursor_r && c == win->cursor_c) {
                        aweos_gfx_fill_rect(fb, px, py, FONT_WIDTH, FONT_HEIGHT, t->accent);
                        draw_char(fb->back_buffer, fb->pitch_pixels, px, py, ch, t->black, 0, 1);
                    } else if (ch != ' ') {
                        draw_char(fb->back_buffer, fb->pitch_pixels, px, py, ch, win->fg_grid[r][c], 0, 1);
                    }
                }
            }
        }
    }
}

void ayui_wm_render_all(ayui_session_t *s) {
    for (int i = 0; i < s->window_count; i++) {
        ayui_wm_render_window(s, &s->windows[i]);
    }
}
