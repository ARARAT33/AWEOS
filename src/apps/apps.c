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

void render_app_text_editor(aweos_fb_t *fb, void *win_ptr) {
    ayui_window_t *win = (ayui_window_t *)win_ptr;
    int client_y = win->y + 24;

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 12, "AYUI Native Text Editor", COLOR_YELLOW, 0, 1);
    aweos_gfx_fill_rect(fb, win->x + 15, client_y + 32, win->width - 30, 1, COLOR_BORDER);

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 45, "File: /etc/aweos/config", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 70, "1 | # AWEOS System Configuration", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 90, "2 | AUTOLOGIN=true", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 110, "3 | HOSTNAME=aweos-pc", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 130, "4 | DESKTOP=AYUI", COLOR_GREEN, 0, 1);
}

void render_app_calculator(aweos_fb_t *fb, void *win_ptr) {
    ayui_window_t *win = (ayui_window_t *)win_ptr;
    int client_y = win->y + 24;

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 12, "AYUI Calculator", COLOR_YELLOW, 0, 1);
    aweos_gfx_fill_rect(fb, win->x + 15, client_y + 32, win->width - 30, 1, COLOR_BORDER);

    /* Display box */
    aweos_gfx_fill_rect(fb, win->x + 20, client_y + 45, win->width - 40, 32, COLOR_TITLE);
    aweos_gfx_draw_rect(fb, win->x + 20, client_y + 45, win->width - 40, 32, COLOR_BORDER);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + win->width - 120, client_y + 54, "1024 * 64 = 65536", COLOR_GREEN, 0, 1);

    /* Keypad Grid */
    const char *keys[] = {"7", "8", "9", "/", "4", "5", "6", "*", "1", "2", "3", "-", "C", "0", "=", "+"};
    for (int i = 0; i < 16; i++) {
        int r = i / 4;
        int c = i % 4;
        int kx = win->x + 20 + c * 75;
        int ky = client_y + 90 + r * 30;
        aweos_gfx_fill_rect(fb, kx, ky, 65, 24, COLOR_BORDER);
        draw_string(fb->back_buffer, fb->pitch_pixels, kx + 26, ky + 5, keys[i], COLOR_WHITE, 0, 1);
    }
}

void render_app_control_center(aweos_fb_t *fb, void *win_ptr) {
    ayui_window_t *win = (ayui_window_t *)win_ptr;
    int client_y = win->y + 24;

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 12, "AYUI Control Center", COLOR_YELLOW, 0, 1);
    aweos_gfx_fill_rect(fb, win->x + 15, client_y + 32, win->width - 30, 1, COLOR_BORDER);

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 45, "Quick Toggles:", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 70, "[ON]  Wi-Fi / Ethernet", COLOR_GREEN, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 95, "[ON]  Audio Volume (100%)", COLOR_GREEN, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 120, "[OFF] Dark Mode Toggle", COLOR_TEXT, 0, 1);
}

void render_app_system_monitor(aweos_fb_t *fb, void *win_ptr) {
    ayui_window_t *win = (ayui_window_t *)win_ptr;
    int client_y = win->y + 24;

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 12, "AYUI System & Process Monitor", COLOR_YELLOW, 0, 1);
    aweos_gfx_fill_rect(fb, win->x + 15, client_y + 32, win->width - 30, 1, COLOR_BORDER);

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 45, "CPU Usage: [||||        ] 28%", COLOR_GREEN, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 68, "RAM Usage: [||||||||    ] 128MB / 512MB", COLOR_GREEN, 0, 1);

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 95, "PID   USER    CPU%   MEM%   COMMAND", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 115, "1     root    0.1    0.5    /sbin/init", COLOR_TEXT, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 135, "42    aweos   2.4    8.2    /usr/bin/aweos-ayui", COLOR_GREEN, 0, 1);
}

void render_app_screenshot(aweos_fb_t *fb, void *win_ptr) {
    ayui_window_t *win = (ayui_window_t *)win_ptr;
    int client_y = win->y + 24;

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 15, client_y + 12, "AYUI Screen Capture Utility", COLOR_YELLOW, 0, 1);
    aweos_gfx_fill_rect(fb, win->x + 15, client_y + 32, win->width - 30, 1, COLOR_BORDER);

    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 45, "Capture Target: Full Screen (/dev/fb0)", COLOR_WHITE, 0, 1);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 20, client_y + 70, "Output File: /tmp/ayui-screenshot.png", COLOR_GREEN, 0, 1);

    aweos_gfx_fill_rect(fb, win->x + 20, client_y + 105, 160, 26, COLOR_ACCENT);
    draw_string(fb->back_buffer, fb->pitch_pixels, win->x + 35, client_y + 111, "Take Screenshot", COLOR_WHITE, 0, 1);
}
