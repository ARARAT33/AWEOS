#ifndef AYUI_WM_H
#define AYUI_WM_H

#include "ayui.h"

ayui_window_t *ayui_wm_create_window(ayui_session_t *s, int x, int y, int w, int h, const char *title);
void ayui_wm_close_window(ayui_session_t *s, int window_idx);
void ayui_wm_focus_window(ayui_session_t *s, int window_idx);
int ayui_wm_spawn_terminal(ayui_session_t *s, ayui_window_t *win);
void ayui_wm_read_pty(ayui_window_t *win);
void ayui_wm_render_window(ayui_session_t *s, ayui_window_t *win);
void ayui_wm_render_all(ayui_session_t *s);

#endif /* AYUI_WM_H */
