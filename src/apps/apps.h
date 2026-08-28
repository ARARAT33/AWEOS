#ifndef AWEOS_APPS_H
#define AWEOS_APPS_H

#include "../gui/wm.h"
#include "../gui/font.h"
#include "../core/storage.h"

void render_app_file_manager(aweos_fb_t *fb, void *win_ptr);
void render_app_settings(aweos_fb_t *fb, void *win_ptr);
void render_app_system_info(aweos_fb_t *fb, void *win_ptr);
void render_app_network_manager(aweos_fb_t *fb, void *win_ptr);
void render_app_storage_info(aweos_fb_t *fb, void *win_ptr);
void render_app_package_manager(aweos_fb_t *fb, void *win_ptr);
void render_app_installer(aweos_fb_t *fb, void *win_ptr);
void render_app_updater(aweos_fb_t *fb, void *win_ptr);
void render_app_diagnostics(aweos_fb_t *fb, void *win_ptr);
void render_app_about(aweos_fb_t *fb, void *win_ptr);

#endif /* AWEOS_APPS_H */
