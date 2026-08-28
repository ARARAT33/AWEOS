#ifndef AWEOS_INPUT_H
#define AWEOS_INPUT_H

#include "ayui.h"

typedef ayui_input_state_t aweos_input_state_t;

#define EVENT_NONE       AYUI_EVENT_NONE
#define EVENT_KEY_DOWN   AYUI_EVENT_KEY_DOWN
#define EVENT_KEY_UP     AYUI_EVENT_KEY_UP
#define EVENT_MOUSE_MOVE AYUI_EVENT_MOUSE_MOVE
#define EVENT_MOUSE_BTN  AYUI_EVENT_MOUSE_BTN

typedef ayui_event_t aweos_input_event_t;

int aweos_input_init(aweos_input_state_t *st, int max_x, int max_y);
void aweos_input_close(aweos_input_state_t *st);
int aweos_input_poll(aweos_input_state_t *st, aweos_input_event_t *ev, int timeout_ms);

#endif
