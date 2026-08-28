#ifndef AYUI_SESSION_H
#define AYUI_SESSION_H

#include "ayui.h"

int ayui_session_init(ayui_session_t *s, bool test_mode);
void ayui_session_register_apps(ayui_session_t *s);
void ayui_session_run(ayui_session_t *s);
void ayui_session_close(ayui_session_t *s);
void ayui_session_launch_app(ayui_session_t *s, int app_id);

#endif /* AYUI_SESSION_H */
