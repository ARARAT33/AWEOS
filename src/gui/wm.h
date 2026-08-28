#ifndef AWEOS_WM_H
#define AWEOS_WM_H

#include "graphics.h"
#include "input.h"
#include <stdint.h>
#include <sys/types.h>

#define MAX_WINDOWS 16
#define TERM_ROWS 24
#define TERM_COLS 80

typedef struct {
    int id;
    int x, y, width, height;
    char title[64];
    int visible;
    int focused;
    uint32_t *buffer;

    // PTY integration for terminal window
    int pty_fd;
    pid_t child_pid;
    char grid[TERM_ROWS][TERM_COLS];
    uint32_t fg_grid[TERM_ROWS][TERM_COLS];
    int cursor_r, cursor_c;
} aweos_window_t;

typedef struct {
    aweos_fb_t fb;
    aweos_input_state_t input;
    aweos_window_t windows[MAX_WINDOWS];
    int window_count;
    int active_window_idx;
    int cursor_x, cursor_y;
    int running;
} aweos_wm_t;

int aweos_wm_init(aweos_wm_t *wm);
void aweos_wm_run(aweos_wm_t *wm);
void aweos_wm_close(aweos_wm_t *wm);

aweos_window_t *aweos_wm_create_window(aweos_wm_t *wm, int x, int y, int w, int h, const char *title);
void aweos_wm_destroy_window(aweos_wm_t *wm, aweos_window_t *win);
int aweos_wm_spawn_terminal(aweos_wm_t *wm, aweos_window_t *win);

#endif
