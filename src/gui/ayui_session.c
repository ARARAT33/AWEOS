#include "ayui_session.h"
#include "ayui_shell.h"
#include "ayui_wm.h"
#include "graphics.h"
#include "font.h"
#include "../apps/apps.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int ayui_session_init(ayui_session_t *s, bool test_mode) {
    memset(s, 0, sizeof(*s));
    s->theme = AYUI_THEME_DEFAULT;
    s->test_mode = test_mode;

    printf("AWEOS AYUI FRAMEBUFFER INITIALIZING\n");

    if (aweos_gfx_init(&s->fb, "/dev/fb0") < 0) {
        fprintf(stderr, "AYUI Session: Failed to initialize framebuffer /dev/fb0\n");
        return -1;
    }
    printf("AWEOS AYUI FRAMEBUFFER OPEN: %ux%u %u bpp\n", s->fb.width, s->fb.height, s->fb.bpp);

    printf("AWEOS INPUT INITIALIZING\n");
    if (aweos_input_init(&s->input, s->fb.width, s->fb.height) < 0) {
        fprintf(stderr, "AYUI Session: Warning - Input device fallback mode\n");
    }
    printf("AWEOS INPUT READY\n");

    printf("AYUI FRAMEBUFFER SESSION INITIALIZED\n");

    s->cursor_x = s->fb.width / 2;
    s->cursor_y = s->fb.height / 2;
    s->running = true;
    s->active_window_idx = -1;
    s->launcher_open = false;

    ayui_session_register_apps(s);

    return 0;
}

#include <dirent.h>

void ayui_session_register_apps(ayui_session_t *s) {
    memset(s->apps, 0, sizeof(s->apps));
    s->app_count = 2;
    s->apps[0] = (ayui_app_info_t){
        .id = 1, .name = "Terminal", .version = "1.0",
        .description = "Interactive BusyBox shell in a PTY",
        .icon = "terminal", .executable = "/bin/sh",
        .category = "System", .launch_cb = NULL
    };
    s->apps[1] = (ayui_app_info_t){
        .id = 2, .name = "Root Listing (read-only)", .version = "1.0",
        .description = "Read-only snapshot of the root directory",
        .icon = "folder", .executable = "internal:root-listing",
        .category = "System", .launch_cb = NULL
    };
}

void ayui_session_launch_app(ayui_session_t *s, int app_id) {
    s->launcher_open = false;
    ayui_window_t *win = NULL;

    switch (app_id) {
        case 1:
            win = ayui_wm_create_window(s, 40, 50, AYUI_TERM_COLS * FONT_WIDTH, AYUI_TERM_ROWS * FONT_HEIGHT, "AWEOS Terminal");
            if (win) {
                if (ayui_wm_spawn_terminal(s, win) < 0) {
                    fprintf(stderr, "AYUI: terminal PTY could not be started\n");
                } else {
                    printf("AYUI TERMINAL READY\n");
                }
            }
            break;
        case 2:
            win = ayui_wm_create_window(s, 60, 60, 480, 260, "Root Listing (read-only)");
            if (win) win->render_cb = render_app_file_manager;
            break;
    }
}

void ayui_session_run(ayui_session_t *s) {
    /* Launch default AYUI Terminal on desktop startup */
    ayui_session_launch_app(s, 1);

    if (s->test_mode) {
        /* Open launcher in test scene so screenshot validation captures desktop + panel + menu + terminal */
        s->launcher_open = true;
    }

    int frame_counter = 0;
    bool ready_logged = false;

    while (s->running) {
        frame_counter++;

        for (int i = 0; i < s->window_count; i++) {
            ayui_wm_read_pty(&s->windows[i]);
        }

        ayui_event_t ev;
        while (aweos_input_poll(&s->input, &ev, 10)) {
            if (ev.type == AYUI_EVENT_MOUSE_MOVE) {
                s->cursor_x += ev.mouse_dx;
                s->cursor_y += ev.mouse_dy;
                if (s->cursor_x < 0) s->cursor_x = 0;
                if (s->cursor_x >= (int)s->fb.width) s->cursor_x = s->fb.width - 1;
                if (s->cursor_y < 0) s->cursor_y = 0;
                if (s->cursor_y >= (int)s->fb.height) s->cursor_y = s->fb.height - 1;
            } else if (ev.type == AYUI_EVENT_KEY_DOWN) {
                if (s->launcher_open) {
                    if (ev.ascii >= '1' && ev.ascii <= '9') {
                        ayui_session_launch_app(s, ev.ascii - '0');
                    }
                } else if (s->active_window_idx >= 0) {
                    ayui_window_t *active = &s->windows[s->active_window_idx];
                    if (active->pty_fd >= 0 && ev.ascii != 0) {
                        ssize_t ret = write(active->pty_fd, &ev.ascii, 1);
                        (void)ret;
                    }
                }
            } else if (ev.type == AYUI_EVENT_MOUSE_BTN && (ev.mouse_buttons & 1)) {
                /* Check panel menu button */
                if (s->cursor_x >= 6 && s->cursor_x <= 106 && s->cursor_y >= 4 && s->cursor_y <= 26) {
                    s->launcher_open = !s->launcher_open;
                } else if (s->launcher_open && s->cursor_x >= 6 && s->cursor_x <= 266 && s->cursor_y >= 32 && s->cursor_y <= 352) {
                    int clicked_idx = (s->cursor_y - 66) / 24 + 1;
                    if (clicked_idx >= 1 && clicked_idx <= s->app_count) {
                        ayui_session_launch_app(s, clicked_idx);
                    }
                } else {
                    /* Check window titlebar close button or focus click */
                    for (int i = s->window_count - 1; i >= 0; i--) {
                        ayui_window_t *w = &s->windows[i];
                        if (!w->visible) continue;
                        if (s->cursor_x >= w->x && s->cursor_x <= w->x + w->width &&
                            s->cursor_y >= w->y && s->cursor_y <= w->y + w->height + 24) {
                            ayui_wm_focus_window(s, i);
                            /* Check close button */
                            if (s->cursor_x >= w->x + w->width - 20 && s->cursor_x <= w->x + w->width - 4 &&
                                s->cursor_y >= w->y + 4 && s->cursor_y <= w->y + 20) {
                                ayui_wm_close_window(s, i);
                            }
                            break;
                        }
                    }
                }
            }
        }

        /* Render Scene */
        ayui_shell_render_wallpaper(&s->fb, &s->theme);
        ayui_shell_render_panel(s);
        ayui_wm_render_all(s);

        if (s->launcher_open) {
            ayui_shell_render_launcher(s);
        }

        ayui_shell_render_cursor(&s->fb, s->cursor_x, s->cursor_y);
        aweos_gfx_swap_buffers(&s->fb);
        if (!ready_logged) {
            printf("AWEOS AYUI FRAMEBUFFER READY: device=/dev/fb0 width=%u height=%u bpp=%u\n",
                   s->fb.width, s->fb.height, s->fb.bpp);
            fflush(stdout);
            ready_logged = true;
        }

        if (s->test_mode && frame_counter >= 30) {
            /* In automated test mode, loop enough frames to dump screenshot and exit gracefully */
            break;
        }

        usleep(16000);
    }
}

void ayui_session_close(ayui_session_t *s) {
    for (int i = 0; i < s->window_count; i++) {
        if (s->windows[i].surface.buffer) free(s->windows[i].surface.buffer);
        if (s->windows[i].pty_fd >= 0) close(s->windows[i].pty_fd);
    }
    aweos_input_close(&s->input);
    aweos_gfx_close(&s->fb);
}
