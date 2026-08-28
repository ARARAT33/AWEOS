#ifndef AWEOS_INPUT_H
#define AWEOS_INPUT_H

#include <stdint.h>

#define EVENT_NONE       0
#define EVENT_KEY_DOWN   1
#define EVENT_KEY_UP     2
#define EVENT_MOUSE_MOVE 3
#define EVENT_MOUSE_BTN  4

typedef struct {
    int type;
    uint16_t keycode;
    char ascii;
    int mouse_dx;
    int mouse_dy;
    int mouse_abs_x;
    int mouse_abs_y;
    uint32_t mouse_buttons;
} aweos_input_event_t;

typedef struct {
    int kbd_fd;
    int mouse_fd;
    int mouse_x;
    int mouse_y;
    uint32_t mouse_btn;
    int shift_pressed;
    int ctrl_pressed;
    int alt_pressed;
} aweos_input_state_t;

int aweos_input_init(aweos_input_state_t *st, int max_x, int max_y);
void aweos_input_close(aweos_input_state_t *st);
int aweos_input_poll(aweos_input_state_t *st, aweos_input_event_t *ev, int timeout_ms);

#endif
