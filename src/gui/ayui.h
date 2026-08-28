#ifndef AWEOS_AYUI_H
#define AWEOS_AYUI_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <sys/types.h>

/* AYUI Theme Color Definitions */
typedef struct {
    uint32_t bg;
    uint32_t panel;
    uint32_t title;
    uint32_t title_active;
    uint32_t title_inactive;
    uint32_t accent;
    uint32_t text;
    uint32_t text_secondary;
    uint32_t white;
    uint32_t black;
    uint32_t red;
    uint32_t green;
    uint32_t yellow;
    uint32_t button;
    uint32_t border;
    uint32_t selection;
} ayui_theme_t;

/* Default AYUI Dark/Modern Theme */
static const ayui_theme_t AYUI_THEME_DEFAULT = {
    .bg             = 0x00101820,
    .panel          = 0x000B121A,
    .title          = 0x001F2D3D,
    .title_active   = 0x002B3E50,
    .title_inactive = 0x0015202B,
    .accent         = 0x000080FF,
    .text           = 0x00E1E6EB,
    .text_secondary = 0x008C9BA5,
    .white          = 0x00FFFFFF,
    .black          = 0x00000000,
    .red            = 0x00E63946,
    .green          = 0x002A9D8F,
    .yellow         = 0x00E9C46A,
    .button         = 0x001D2B3A,
    .border         = 0x003A4D61,
    .selection      = 0x000055A5
};

/* Framebuffer Abstraction */
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
} ayui_fb_t;

/* Input Events */
typedef enum {
    AYUI_EVENT_NONE = 0,
    AYUI_EVENT_KEY_DOWN,
    AYUI_EVENT_KEY_UP,
    AYUI_EVENT_MOUSE_MOVE,
    AYUI_EVENT_MOUSE_BTN,
    AYUI_EVENT_WINDOW_CLOSE,
    AYUI_EVENT_WINDOW_FOCUS,
    AYUI_EVENT_APP_LAUNCH
} ayui_event_type_t;

typedef struct {
    ayui_event_type_t type;
    uint16_t keycode;
    char ascii;
    int mouse_dx;
    int mouse_dy;
    uint8_t mouse_buttons;
    int window_id;
    int app_id;
} ayui_event_t;

typedef struct {
    int kbd_fd;
    int mouse_fd;
    int mouse_x;
    int mouse_y;
    uint8_t mouse_btn;
    bool shift_pressed;
    bool ctrl_pressed;
    bool alt_pressed;
} ayui_input_state_t;

/* Surface System */
typedef struct {
    uint32_t *buffer;
    int width;
    int height;
    int stride;
    bool visible;
    bool damaged;
    int owner_app_id;
} ayui_surface_t;

/* Window System */
#define AYUI_MAX_WINDOWS 16
#define AYUI_TERM_ROWS 28
#define AYUI_TERM_COLS 80

typedef struct ayui_window {
    int id;
    int x, y;
    int width, height;
    char title[64];
    bool visible;
    bool focused;
    bool minimized;
    bool maximized;
    ayui_surface_t surface;

    // Terminal PTY Integration
    int pty_fd;
    pid_t child_pid;
    char grid[AYUI_TERM_ROWS][AYUI_TERM_COLS];
    uint32_t fg_grid[AYUI_TERM_ROWS][AYUI_TERM_COLS];
    int cursor_r;
    int cursor_c;

    // Application render callback
    void (*render_cb)(ayui_fb_t *fb, void *win_ptr);
    void *app_data;
} ayui_window_t;

/* Dynamic Application Registry Item */
typedef struct {
    int id;
    char name[64];
    char version[32];
    char description[128];
    char icon[32];
    char executable[64];
    char category[32];
    void (*launch_cb)(void *session_ptr, int app_id);
} ayui_app_info_t;

#define AYUI_MAX_APPS 32

/* AYUI Desktop Session */
typedef struct {
    ayui_fb_t fb;
    ayui_input_state_t input;
    ayui_theme_t theme;
    ayui_window_t windows[AYUI_MAX_WINDOWS];
    int window_count;
    int active_window_idx;
    int cursor_x, cursor_y;
    bool running;
    bool launcher_open;

    ayui_app_info_t apps[AYUI_MAX_APPS];
    int app_count;

    bool test_mode;
} ayui_session_t;

#endif /* AWEOS_AYUI_H */
