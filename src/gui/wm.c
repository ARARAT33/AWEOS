#define _GNU_SOURCE
#include "wm.h"
#include "font.h"
#include "../apps/apps.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <pty.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <time.h>

#define COLOR_BG      0x001B263B
#define COLOR_PANEL   0x000D1B2A
#define COLOR_TITLE   0x00415A77
#define COLOR_ACCENT  0x00778DA9
#define COLOR_TEXT    0x00E0E1DD
#define COLOR_WHITE   0x00FFFFFF
#define COLOR_BLACK   0x00000000
#define COLOR_RED     0x00E63946
#define COLOR_GREEN   0x002A9D8F
#define COLOR_YELLOW  0x00E9C46A
#define COLOR_BUTTON  0x001D3557

int aweos_wm_init(aweos_wm_t *wm) {
    memset(wm, 0, sizeof(*wm));

    if (aweos_gfx_init(&wm->fb, "/dev/fb0") < 0) {
        fprintf(stderr, "AWEOS WM: Graphics init failed!\n");
        return -1;
    }

    if (aweos_input_init(&wm->input, wm->fb.width, wm->fb.height) < 0) {
        fprintf(stderr, "AWEOS WM: Warning - Input init fallback enabled\n");
    }

    wm->cursor_x = wm->fb.width / 2;
    wm->cursor_y = wm->fb.height / 2;
    wm->running = 1;
    wm->active_window_idx = -1;
    wm->launcher_open = false;

    return 0;
}

void aweos_wm_close(aweos_wm_t *wm) {
    for (int i = 0; i < wm->window_count; i++) {
        if (wm->windows[i].buffer) free(wm->windows[i].buffer);
        if (wm->windows[i].pty_fd >= 0) close(wm->windows[i].pty_fd);
    }
    aweos_input_close(&wm->input);
    aweos_gfx_close(&wm->fb);
}

aweos_window_t *aweos_wm_create_window(aweos_wm_t *wm, int x, int y, int w, int h, const char *title) {
    if (wm->window_count >= MAX_WINDOWS) return NULL;

    if (x + w > (int)wm->fb.width) x = (wm->fb.width - w > 0) ? (wm->fb.width - w) / 2 : 10;
    if (y + h > (int)wm->fb.height) y = (wm->fb.height - h > 0) ? (wm->fb.height - h) / 2 : 35;

    aweos_window_t *win = &wm->windows[wm->window_count];
    memset(win, 0, sizeof(*win));
    win->id = wm->window_count + 1;
    win->x = x;
    win->y = y;
    win->width = w;
    win->height = h;
    snprintf(win->title, sizeof(win->title), "%s", title);
    win->visible = 1;
    win->focused = 1;
    win->pty_fd = -1;

    win->buffer = (uint32_t *)malloc(w * h * sizeof(uint32_t));
    if (!win->buffer) return NULL;
    for (int i = 0; i < w * h; i++) win->buffer[i] = COLOR_BLACK;

    wm->active_window_idx = wm->window_count;
    wm->window_count++;
    return win;
}

int aweos_wm_spawn_terminal(aweos_wm_t *wm, aweos_window_t *win) {
    (void)wm;
    int master_fd;
    struct winsize ws;
    ws.ws_row = TERM_ROWS;
    ws.ws_col = TERM_COLS;
    ws.ws_xpixel = win->width;
    ws.ws_ypixel = win->height;

    pid_t pid = forkpty(&master_fd, NULL, NULL, &ws);
    if (pid < 0) {
        perror("forkpty failed");
        return -1;
    } else if (pid == 0) {
        setenv("TERM", "xterm", 1);
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

    for (int r = 0; r < TERM_ROWS; r++) {
        for (int c = 0; c < TERM_COLS; c++) {
            win->grid[r][c] = ' ';
            win->fg_grid[r][c] = COLOR_TEXT;
        }
    }
    return 0;
}

static void read_pty_output(aweos_window_t *win) {
    if (win->pty_fd < 0) return;
    char buf[512];
    ssize_t n = read(win->pty_fd, buf, sizeof(buf) - 1);
    if (n <= 0) return;

    for (ssize_t i = 0; i < n; i++) {
        char ch = buf[i];
        if (ch == '\r') {
            win->cursor_c = 0;
        } else if (ch == '\n') {
            win->cursor_c = 0;
            win->cursor_r++;
            if (win->cursor_r >= TERM_ROWS) {
                memmove(win->grid[0], win->grid[1], (TERM_ROWS - 1) * TERM_COLS);
                memmove(win->fg_grid[0], win->fg_grid[1], (TERM_ROWS - 1) * TERM_COLS * sizeof(uint32_t));
                for (int c = 0; c < TERM_COLS; c++) {
                    win->grid[TERM_ROWS - 1][c] = ' ';
                    win->fg_grid[TERM_ROWS - 1][c] = COLOR_TEXT;
                }
                win->cursor_r = TERM_ROWS - 1;
            }
        } else if (ch == '\b') {
            if (win->cursor_c > 0) win->cursor_c--;
        } else if (ch == '\t') {
            win->cursor_c = (win->cursor_c + 4) & ~3;
        } else if (ch >= 32 && ch <= 126) {
            if (win->cursor_c >= TERM_COLS) {
                win->cursor_c = 0;
                win->cursor_r++;
            }
            if (win->cursor_r >= TERM_ROWS) {
                memmove(win->grid[0], win->grid[1], (TERM_ROWS - 1) * TERM_COLS);
                memmove(win->fg_grid[0], win->fg_grid[1], (TERM_ROWS - 1) * TERM_COLS * sizeof(uint32_t));
                for (int c = 0; c < TERM_COLS; c++) {
                    win->grid[TERM_ROWS - 1][c] = ' ';
                    win->fg_grid[TERM_ROWS - 1][c] = COLOR_TEXT;
                }
                win->cursor_r = TERM_ROWS - 1;
            }
            win->grid[win->cursor_r][win->cursor_c] = ch;
            win->fg_grid[win->cursor_r][win->cursor_c] = COLOR_TEXT;
            win->cursor_c++;
        }
    }
}

static void draw_cursor(aweos_fb_t *fb, int x, int y) {
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
                    fb->back_buffer[py * fb->pitch_pixels + px] = COLOR_BLACK;
                } else if (p == '.') {
                    fb->back_buffer[py * fb->pitch_pixels + px] = COLOR_WHITE;
                }
            }
        }
    }
}

static void launch_app(aweos_wm_t *wm, int app_id) {
    wm->launcher_open = false;
    aweos_window_t *win = NULL;
    switch (app_id) {
        case 1:
            win = aweos_wm_create_window(wm, 40, 50, TERM_COLS * FONT_WIDTH, TERM_ROWS * FONT_HEIGHT, "AWEOS Terminal");
            if (win) aweos_wm_spawn_terminal(wm, win);
            break;
        case 2:
            win = aweos_wm_create_window(wm, 60, 60, 480, 260, "File Manager");
            if (win) win->render_cb = render_app_file_manager;
            break;
        case 3:
            win = aweos_wm_create_window(wm, 80, 70, 480, 220, "System Settings");
            if (win) win->render_cb = render_app_settings;
            break;
        case 4:
            win = aweos_wm_create_window(wm, 100, 80, 480, 220, "System Information");
            if (win) win->render_cb = render_app_system_info;
            break;
        case 5:
            win = aweos_wm_create_window(wm, 120, 90, 480, 220, "Network Manager");
            if (win) win->render_cb = render_app_network_manager;
            break;
        case 6:
            win = aweos_wm_create_window(wm, 140, 100, 480, 220, "Storage & Disk Info");
            if (win) win->render_cb = render_app_storage_info;
            break;
        case 7:
            win = aweos_wm_create_window(wm, 160, 110, 480, 220, "AOSIN Package Manager");
            if (win) win->render_cb = render_app_package_manager;
            break;
        case 8:
            win = aweos_wm_create_window(wm, 180, 120, 500, 240, "AWEOS Graphical Installer");
            if (win) win->render_cb = render_app_installer;
            break;
        case 9:
            win = aweos_wm_create_window(wm, 200, 130, 500, 240, "AWEOS System Updater");
            if (win) win->render_cb = render_app_updater;
            break;
        case 0:
            win = aweos_wm_create_window(wm, 220, 140, 480, 220, "About AWEOS");
            if (win) win->render_cb = render_app_about;
            break;
    }
}

static void render_launcher_menu(aweos_fb_t *fb) {
    int w = 220;
    int h = 260;
    int x = 10;
    int y = 35;

    aweos_gfx_fill_rect(fb, x + 4, y + 4, w, h, 0x000A1118);
    aweos_gfx_fill_rect(fb, x, y, w, h, COLOR_PANEL);
    aweos_gfx_draw_rect(fb, x, y, w, h, COLOR_ACCENT);

    draw_string(fb->back_buffer, fb->pitch_pixels, x + 15, y + 10, "AWEOS Applications", COLOR_YELLOW, 0, 1);
    aweos_gfx_fill_rect(fb, x + 10, y + 28, w - 20, 1, COLOR_TITLE);

    const char *apps[] = {
        "1. Terminal",
        "2. File Manager",
        "3. Settings",
        "4. System Info",
        "5. Network Manager",
        "6. Storage Info",
        "7. Package Manager",
        "8. AWEOS Installer",
        "9. AWEOS Updater",
        "0. About AWEOS"
    };

    for (int i = 0; i < 10; i++) {
        draw_string(fb->back_buffer, fb->pitch_pixels, x + 15, y + 36 + i * 22, apps[i], COLOR_TEXT, 0, 1);
    }
}

static void render_window(aweos_fb_t *fb, aweos_window_t *win) {
    if (!win->visible) return;

    int title_height = 24;
    aweos_gfx_fill_rect(fb, win->x + 4, win->y + 4, win->width + 4, win->height + title_height + 4, 0x000A1118);
    aweos_gfx_fill_rect(fb, win->x, win->y, win->width, title_height, win->focused ? COLOR_TITLE : COLOR_PANEL);
    aweos_gfx_draw_rect(fb, win->x, win->y, win->width, win->height + title_height, COLOR_ACCENT);

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 8, win->y + 4, win->title, COLOR_WHITE, 0, 1);
    aweos_gfx_fill_rect(fb, win->x + win->width - 20, win->y + 4, 16, 16, COLOR_RED);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + win->width - 16, win->y + 4, "x", COLOR_WHITE, 0, 1);

    int client_y = win->y + title_height;
    aweos_gfx_fill_rect(fb, win->x, client_y, win->width, win->height, COLOR_BLACK);

    if (win->render_cb) {
        win->render_cb(fb, win);
    } else if (win->pty_fd >= 0) {
        for (int r = 0; r < TERM_ROWS; r++) {
            for (int c = 0; c < TERM_COLS; c++) {
                char ch = win->grid[r][c];
                int px = win->x + c * FONT_WIDTH;
                int py = client_y + r * FONT_HEIGHT;
                if (px + FONT_WIDTH <= win->x + win->width && py + FONT_HEIGHT <= client_y + win->height) {
                    if (r == win->cursor_r && c == win->cursor_c) {
                        aweos_gfx_fill_rect(fb, px, py, FONT_WIDTH, FONT_HEIGHT, COLOR_ACCENT);
                        draw_char(fb->back_buffer, fb->pitch_pixels, px, py, ch, COLOR_BLACK, 0, 1);
                    } else if (ch != ' ') {
                        draw_char(fb->back_buffer, fb->pitch_pixels, px, py, ch, win->fg_grid[r][c], 0, 1);
                    }
                }
            }
        }
    }
}

void aweos_wm_run(aweos_wm_t *wm) {
    printf("AWEOS COMPOSITOR INITIALIZING\n");
    printf("AWEOS COMPOSITOR READY\n");
    printf("AWEOS GUI INITIALIZING\n");
    printf("AWEOS GUI READY\n");

    aweos_window_t *term = aweos_wm_create_window(wm, 40, 50, TERM_COLS * FONT_WIDTH, TERM_ROWS * FONT_HEIGHT, "AWEOS Terminal (x86_64)");
    if (term) {
        aweos_wm_spawn_terminal(wm, term);
        printf("AWEOS GUI TERMINAL READY\n");
    }

    while (wm->running) {
        for (int i = 0; i < wm->window_count; i++) {
            read_pty_output(&wm->windows[i]);
        }

        aweos_input_event_t ev;
        while (aweos_input_poll(&wm->input, &ev, 10)) {
            if (ev.type == EVENT_MOUSE_MOVE) {
                wm->cursor_x += ev.mouse_dx;
                wm->cursor_y += ev.mouse_dy;
                if (wm->cursor_x < 0) wm->cursor_x = 0;
                if (wm->cursor_x >= (int)wm->fb.width) wm->cursor_x = wm->fb.width - 1;
                if (wm->cursor_y < 0) wm->cursor_y = 0;
                if (wm->cursor_y >= (int)wm->fb.height) wm->cursor_y = wm->fb.height - 1;
            } else if (ev.type == EVENT_KEY_DOWN) {
                if (wm->launcher_open) {
                    if (ev.ascii >= '0' && ev.ascii <= '9') {
                        launch_app(wm, ev.ascii - '0');
                    }
                } else if (wm->active_window_idx >= 0) {
                    aweos_window_t *active = &wm->windows[wm->active_window_idx];
                    if (active->pty_fd >= 0 && ev.ascii != 0) {
                        ssize_t ret = write(active->pty_fd, &ev.ascii, 1);
                        (void)ret;
                    }
                }
            } else if (ev.type == EVENT_MOUSE_BTN && (ev.mouse_buttons & 1)) {
                if (wm->cursor_x >= 5 && wm->cursor_x <= 95 && wm->cursor_y >= 3 && wm->cursor_y <= 27) {
                    wm->launcher_open = !wm->launcher_open;
                } else if (wm->launcher_open && wm->cursor_x >= 10 && wm->cursor_x <= 230 && wm->cursor_y >= 35 && wm->cursor_y <= 295) {
                    int clicked_idx = (wm->cursor_y - 71) / 22 + 1;
                    if (clicked_idx >= 1 && clicked_idx <= 10) {
                        launch_app(wm, clicked_idx % 10);
                    }
                }
            }
        }

        aweos_gfx_clear(&wm->fb, COLOR_BG);

        aweos_gfx_fill_rect(&wm->fb, 0, 0, wm->fb.width, 30, COLOR_PANEL);

        aweos_gfx_fill_rect(&wm->fb, 5, 4, 90, 22, wm->launcher_open ? COLOR_TITLE : COLOR_BUTTON);
        draw_string(wm->fb.back_buffer, wm->fb.pitch_pixels, 12, 7, "AWEOS Menu", COLOR_WHITE, 0, 1);

        draw_string(wm->fb.back_buffer, wm->fb.pitch_pixels, 110, 7, "AWEOS v1.0.0 (Native GUI)", COLOR_WHITE, 0, 1);

        time_t t = time(NULL);
        struct tm *tm_info = localtime(&t);
        char time_str[32];
        if (tm_info) strftime(time_str, sizeof(time_str), "%H:%M:%S", tm_info);
        else snprintf(time_str, sizeof(time_str), "12:00:00");
        draw_string(wm->fb.back_buffer, wm->fb.pitch_pixels, wm->fb.width - 90, 7, time_str, COLOR_GREEN, 0, 1);

        for (int i = 0; i < wm->window_count; i++) {
            render_window(&wm->fb, &wm->windows[i]);
        }

        if (wm->launcher_open) {
            render_launcher_menu(&wm->fb);
        }

        draw_cursor(&wm->fb, wm->cursor_x, wm->cursor_y);
        aweos_gfx_swap_buffers(&wm->fb);
        usleep(16000);
    }
}
