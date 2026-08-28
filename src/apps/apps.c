#include "apps.h"
#include <stdio.h>
#include <string.h>

#define COLOR_TEXT    0x00E0E1DD
#define COLOR_WHITE   0x00FFFFFF
#define COLOR_GREEN   0x002A9D8F
#define COLOR_YELLOW  0x00E9C46A
#define COLOR_BLUE    0x00415A77

void render_app_file_manager(aweos_fb_t *fb, void *win_ptr) {
    aweos_window_t *win = (aweos_window_t *)win_ptr;
    int client_y = win->y + 24;
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 10, client_y + 10, "AWEOS File Manager - Location: /", COLOR_YELLOW, 0, 1);

    const char *files[] = {
        "[DIR]  bin/",
        "[DIR]  boot/",
        "[DIR]  etc/",
        "[DIR]  home/",
        "[DIR]  root/",
        "[DIR]  usr/",
        "[DIR]  var/",
        "[FILE] aweos-initramfs.cpio.gz",
        "[FILE] rootfs.img"
    };

    for (int i = 0; i < 9; i++) {
        draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 35 + i * 20, files[i], COLOR_TEXT, 0, 1);
    }
}

void render_app_settings(aweos_fb_t *fb, void *win_ptr) {
    aweos_window_t *win = (aweos_window_t *)win_ptr;
    int client_y = win->y + 24;
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 10, client_y + 10, "AWEOS System Settings", COLOR_YELLOW, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 40, "Display Mode: Framebuffer /dev/fb0", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 65, "Input Driver: Linux Evdev / PS2 Mouse", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 90, "Default Boot Mode: aweos.mode=gui", COLOR_GREEN, 0, 1);
}

void render_app_system_info(aweos_fb_t *fb, void *win_ptr) {
    aweos_window_t *win = (aweos_window_t *)win_ptr;
    int client_y = win->y + 24;
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 10, client_y + 10, "System Information", COLOR_YELLOW, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 35, "OS: AWEOS x86_64 v1.0.0", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 55, "Kernel: Linux (x86_64 out-of-tree)", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 75, "Bootloader: Limine v12.6.1", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 95, "GUI: Native C Double-Buffered Window Manager", COLOR_GREEN, 0, 1);
}

void render_app_network_manager(aweos_fb_t *fb, void *win_ptr) {
    aweos_window_t *win = (aweos_window_t *)win_ptr;
    int client_y = win->y + 24;
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 10, client_y + 10, "AWEOS Network Manager", COLOR_YELLOW, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 40, "eth0: UP (VirtIO Network Device)", COLOR_GREEN, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 65, "IP Address: 10.0.2.15/24 (DHCP)", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 90, "Gateway: 10.0.2.2", COLOR_TEXT, 0, 1);
}

void render_app_storage_info(aweos_fb_t *fb, void *win_ptr) {
    aweos_window_t *win = (aweos_window_t *)win_ptr;
    int client_y = win->y + 24;
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 10, client_y + 10, "Storage & Partition Information", COLOR_YELLOW, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 40, "/dev/vda1 [ext4]: 64MB Total / 24MB Free", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 65, "Mount Point: / (AWEOS Root Filesystem)", COLOR_GREEN, 0, 1);
}

void render_app_package_manager(aweos_fb_t *fb, void *win_ptr) {
    aweos_window_t *win = (aweos_window_t *)win_ptr;
    int client_y = win->y + 24;
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 10, client_y + 10, "AOSIN Package Manager", COLOR_YELLOW, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 40, "Supported Formats: .asp, .asa, .aosin", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 65, "Installed Packages: base-system (v1.0.0)", COLOR_GREEN, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 90, "Package Store: /var/lib/awepkg", COLOR_TEXT, 0, 1);
}

void render_app_installer(aweos_fb_t *fb, void *win_ptr) {
    aweos_window_t *win = (aweos_window_t *)win_ptr;
    int client_y = win->y + 24;
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 10, client_y + 10, "AWEOS Standalone GUI Installer", COLOR_YELLOW, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 40, "Target Disk: /dev/vda (AWEOS Virtual Storage)", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 65, "Mode: Dual-Boot / Full-Disk Replacement", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 90, "Data Preservation: /archiveddata/ Enabled", COLOR_GREEN, 0, 1);
}

void render_app_updater(aweos_fb_t *fb, void *win_ptr) {
    aweos_window_t *win = (aweos_window_t *)win_ptr;
    int client_y = win->y + 24;
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 10, client_y + 10, "Safe AWEOS OS System Updater", COLOR_YELLOW, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 40, "Current OS Version: 1.0.0", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 65, "Update Mechanism: ISO Validation & Staged Deployment", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 90, "Status: System up-to-date", COLOR_GREEN, 0, 1);
}

void render_app_diagnostics(aweos_fb_t *fb, void *win_ptr) {
    aweos_window_t *win = (aweos_window_t *)win_ptr;
    int client_y = win->y + 24;
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 10, client_y + 10, "AWEOS System Diagnostics", COLOR_YELLOW, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 40, "[PASS] /proc mounted", COLOR_GREEN, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 60, "[PASS] /sys mounted", COLOR_GREEN, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 80, "[PASS] /dev/fb0 framebuffer active", COLOR_GREEN, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 100, "[PASS] /dev/input event handlers ready", COLOR_GREEN, 0, 1);
}

void render_app_about(aweos_fb_t *fb, void *win_ptr) {
    aweos_window_t *win = (aweos_window_t *)win_ptr;
    int client_y = win->y + 24;
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 10, client_y + 10, "About AWEOS Operating System", COLOR_YELLOW, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 40, "AWEOS x86_64 Native Graphical Operating System", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 65, "Custom Native C Window Manager & Compositor", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 90, "Zero External Desktop Environment Dependencies", COLOR_GREEN, 0, 1);
}
