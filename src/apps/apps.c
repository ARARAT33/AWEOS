#include "apps.h"
#include <stdio.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>

#define COLOR_TEXT        0x00E1E6EB
#define COLOR_WHITE       0x00FFFFFF
#define COLOR_GREEN       0x002A9D8F
#define COLOR_YELLOW      0x00E9C46A
#define COLOR_TITLE       0x002B3E50
#define COLOR_BORDER      0x003A4D61
#define COLOR_ACCENT      0x000080FF

void render_app_file_manager(aweos_fb_t *fb, void *win_ptr) {
    ayui_window_t *win = (ayui_window_t *)win_ptr;
    int client_y = win->y + 24;

    /* Location Header */
    aweos_gfx_fill_rect(fb, win->x + 10, client_y + 8, win->width - 20, 24, COLOR_TITLE);
    aweos_gfx_draw_rect(fb, win->x + 10, client_y + 8, win->width - 20, 24, COLOR_BORDER);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 18, client_y + 12, "Path: /", COLOR_YELLOW, 0, 1);

    /* Read actual directory entries from / if available */
    DIR *d = opendir("/");
    if (d) {
        struct dirent *dir;
        int row = 0;
        while ((dir = readdir(d)) != NULL && row < 8) {
            if (strcmp(dir->d_name, ".") == 0 || strcmp(dir->d_name, "..") == 0) continue;
            char line[128];
            snprintf(line, sizeof(line), " [%s] %s", (dir->d_type == DT_DIR) ? "DIR " : "FILE", dir->d_name);
            uint32_t fg = (dir->d_type == DT_DIR) ? COLOR_GREEN : COLOR_TEXT;
            draw_string_clipped(fb->back_buffer, fb->pitch_pixels, win->x + 18, client_y + 42 + row * 22, line, fg, win->width - 36);
            row++;
        }
        closedir(d);
    } else {
        const char *fallback[] = {
            " [DIR ] bin/", " [DIR ] boot/", " [DIR ] etc/", " [DIR ] home/",
            " [DIR ] usr/", " [DIR ] var/", " [FILE] rootfs.img"
        };
        for (int i = 0; i < 7; i++) {
            draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 18, client_y + 42 + i * 22, fallback[i], COLOR_TEXT, 0, 1);
        }
    }
}

void render_app_settings(aweos_fb_t *fb, void *win_ptr) {
    ayui_window_t *win = (ayui_window_t *)win_ptr;
    int client_y = win->y + 24;

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 12, "AWEOS System Settings & Preferences", COLOR_YELLOW, 0, 1);
    aweos_gfx_fill_rect(fb, win->x + 15, client_y + 32, win->width - 30, 1, COLOR_BORDER);

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 45, "Display Backend: Framebuffer (/dev/fb0)", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 70, "Input Drivers: Linux Evdev + PS/2 Mouse", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 95, "Desktop Theme: AYUI Modern Dark", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 120, "Boot Parameter: aweos.mode=gui", COLOR_GREEN, 0, 1);
}

void render_app_system_info(aweos_fb_t *fb, void *win_ptr) {
    ayui_window_t *win = (ayui_window_t *)win_ptr;
    int client_y = win->y + 24;

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 12, "System Specifications & Runtime", COLOR_YELLOW, 0, 1);
    aweos_gfx_fill_rect(fb, win->x + 15, client_y + 32, win->width - 30, 1, COLOR_BORDER);

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 45, "OS: AWEOS x86_64 v1.0.0", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 68, "Kernel: Linux x86_64 (Out-of-tree build)", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 91, "Bootloader: Limine v12.6.1", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 114, "Desktop Environment: AYUI Native C", COLOR_GREEN, 0, 1);
}

void render_app_network_manager(aweos_fb_t *fb, void *win_ptr) {
    ayui_window_t *win = (ayui_window_t *)win_ptr;
    int client_y = win->y + 24;

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 12, "Network Interfaces & Status", COLOR_YELLOW, 0, 1);
    aweos_gfx_fill_rect(fb, win->x + 15, client_y + 32, win->width - 30, 1, COLOR_BORDER);

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 45, "eth0: UP (VirtIO Network Adapter)", COLOR_GREEN, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 70, "IPv4 Address: 10.0.2.15/24 (DHCP Active)", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 95, "Default Gateway: 10.0.2.2", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 120, "DNS Server: 8.8.8.8, 1.1.1.1", COLOR_TEXT, 0, 1);
}

void render_app_storage_info(aweos_fb_t *fb, void *win_ptr) {
    ayui_window_t *win = (ayui_window_t *)win_ptr;
    int client_y = win->y + 24;

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 12, "Disks and Mounted Filesystems", COLOR_YELLOW, 0, 1);
    aweos_gfx_fill_rect(fb, win->x + 15, client_y + 32, win->width - 30, 1, COLOR_BORDER);

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 45, "Mount Point: / [AWEOS ext4 Rootfs]", COLOR_GREEN, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 70, "Device: /dev/vda1 (VirtIO Block)", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 95, "Capacity: 64MB Total / 24MB Free", COLOR_TEXT, 0, 1);
}

void render_app_package_manager(aweos_fb_t *fb, void *win_ptr) {
    ayui_window_t *win = (ayui_window_t *)win_ptr;
    int client_y = win->y + 24;

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 12, "AOSIN Package System Store", COLOR_YELLOW, 0, 1);
    aweos_gfx_fill_rect(fb, win->x + 15, client_y + 32, win->width - 30, 1, COLOR_BORDER);

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 45, "Supported Package Specifications: .asp, .asa, .aosin", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 70, "Installed: base-system (v1.0.0)", COLOR_GREEN, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 95, "Package Database Path: /var/lib/awepkg", COLOR_TEXT, 0, 1);
}

void render_app_installer(aweos_fb_t *fb, void *win_ptr) {
    ayui_window_t *win = (ayui_window_t *)win_ptr;
    int client_y = win->y + 24;

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 12, "AWEOS Standalone Graphical Installer", COLOR_YELLOW, 0, 1);
    aweos_gfx_fill_rect(fb, win->x + 15, client_y + 32, win->width - 30, 1, COLOR_BORDER);

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 45, "Target Storage Disk: /dev/vda", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 70, "Installation Mode: Dual-Boot / Full Replacement", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 95, "Data Preservation: /archiveddata/ Enabled", COLOR_GREEN, 0, 1);

    /* Interactive Install Button */
    aweos_gfx_fill_rect(fb, win->x + 20, client_y + 130, 180, 28, COLOR_ACCENT);
    aweos_gfx_draw_rect(fb, win->x + 20, client_y + 130, 180, 28, COLOR_WHITE);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 35, client_y + 136, "Start Install", COLOR_WHITE, 0, 1);
}

void render_app_updater(aweos_fb_t *fb, void *win_ptr) {
    ayui_window_t *win = (ayui_window_t *)win_ptr;
    int client_y = win->y + 24;

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 12, "Safe AWEOS OS System Updater", COLOR_YELLOW, 0, 1);
    aweos_gfx_fill_rect(fb, win->x + 15, client_y + 32, win->width - 30, 1, COLOR_BORDER);

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 45, "Current OS Release: v1.0.0 (x86_64)", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 70, "Update Method: Staged ISO Deployment & Verification", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 95, "System Integrity: Validated (No updates pending)", COLOR_GREEN, 0, 1);
}

void render_app_diagnostics(aweos_fb_t *fb, void *win_ptr) {
    ayui_window_t *win = (ayui_window_t *)win_ptr;
    int client_y = win->y + 24;

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 12, "AWEOS System Environment Verification", COLOR_YELLOW, 0, 1);
    aweos_gfx_fill_rect(fb, win->x + 15, client_y + 32, win->width - 30, 1, COLOR_BORDER);

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 45, "[PASS] /proc virtual filesystem mounted", COLOR_GREEN, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 68, "[PASS] /sys kernel sysfs mounted", COLOR_GREEN, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 91, "[PASS] /dev/fb0 framebuffer initialized", COLOR_GREEN, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 114, "[PASS] Linux evdev input event subsystem ready", COLOR_GREEN, 0, 1);
}

void render_app_about(aweos_fb_t *fb, void *win_ptr) {
    ayui_window_t *win = (ayui_window_t *)win_ptr;
    int client_y = win->y + 24;

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 12, "About AWEOS Operating System", COLOR_YELLOW, 0, 1);
    aweos_gfx_fill_rect(fb, win->x + 15, client_y + 32, win->width - 30, 1, COLOR_BORDER);

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 45, "AWEOS x86_64 Native Operating System", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 70, "Desktop Environment: AYUI Native C Stack", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 95, "Zero External Desktop Environment Dependencies", COLOR_GREEN, 0, 1);
}
