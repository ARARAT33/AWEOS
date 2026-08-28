#ifndef AYUI_SHELL_H
#define AYUI_SHELL_H

#include "ayui.h"

void ayui_shell_render_wallpaper(ayui_fb_t *fb, const ayui_theme_t *theme);
void ayui_shell_render_panel(ayui_session_t *s);
void ayui_shell_render_launcher(ayui_session_t *s);
void ayui_shell_render_cursor(ayui_fb_t *fb, int x, int y);

#endif /* AYUI_SHELL_H */
