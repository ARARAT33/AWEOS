#include "boot.h"
#include "logging.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int aweos_boot_configure_limine(const char *target_dir, aweos_boot_mode_t boot_mode) {
    if (!target_dir) return AWEOS_ERR_INVALID_PARAM;
    LOGI("Configuring Limine bootloader in '%s' (Boot mode: %s)...",
         target_dir, boot_mode == BOOT_MODE_UEFI ? "UEFI" : "BIOS");

    char conf_path[256];
    snprintf(conf_path, sizeof(conf_path), "%s/limine.conf", target_dir);
    FILE *f = fopen(conf_path, "w");
    if (!f) {
        LOGE("Failed to write Limine configuration at %s", conf_path);
        return AWEOS_ERR_IO;
    }

    fprintf(f, "timeout: 3\n\n");
    fprintf(f, "/AWEOS x86_64 Operating System\n");
    fprintf(f, "    protocol: linux\n");
    fprintf(f, "    kernel_path: boot():/boot/bzImage\n");
    fprintf(f, "    initrd_path: boot():/boot/aweos-initramfs.cpio.gz\n");
    fprintf(f, "    cmdline: aweos.mode=gui quiet\n");
    fclose(f);

    LOGI("Limine bootloader configuration written successfully at %s", conf_path);
    return AWEOS_OK;
}
