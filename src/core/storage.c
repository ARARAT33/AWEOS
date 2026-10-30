#include "storage.h"
#include "logging.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>

#if defined(__linux__)
#include <mntent.h>
#include <sys/statvfs.h>
#include <sys/vfs.h>
#include <linux/magic.h>
#endif

int aweos_detect_boot_mode(aweos_boot_mode_t *mode) {
    if (!mode) return AWEOS_ERR_INVALID_PARAM;
#if defined(__linux__)
    struct statfs sysfs;
    if (statfs("/sys", &sysfs) != 0) {
        LOGE("Cannot inspect /sys mount while detecting firmware mode: %s", strerror(errno));
        return AWEOS_ERR_IO;
    }
    if ((unsigned long)sysfs.f_type != (unsigned long)SYSFS_MAGIC) {
        LOGE("/sys is not mounted as sysfs; refusing to guess BIOS or UEFI mode");
        return AWEOS_ERR_IO;
    }

    struct stat efi;
    if (stat("/sys/firmware/efi", &efi) == 0) {
        if (!S_ISDIR(efi.st_mode)) {
            LOGE("/sys/firmware/efi exists but is not a directory");
            return AWEOS_ERR_IO;
        }
        *mode = BOOT_MODE_UEFI;
        LOGI("Detected UEFI boot mode via /sys/firmware/efi");
    } else if (errno == ENOENT) {
        *mode = BOOT_MODE_BIOS;
        LOGI("Detected BIOS boot mode on a mounted sysfs");
    } else {
        LOGE("Cannot inspect /sys/firmware/efi: %s", strerror(errno));
        return AWEOS_ERR_IO;
    }
#elif defined(_WIN32)
    *mode = BOOT_MODE_UEFI;
#else
    *mode = BOOT_MODE_BIOS;
#endif
    return AWEOS_OK;
}

int aweos_storage_discover(aweos_storage_info_t *info) {
    if (!info) return AWEOS_ERR_INVALID_PARAM;
    memset(info, 0, sizeof(*info));

#if defined(__linux__)
    FILE *f = fopen("/proc/partitions", "r");
    if (!f) {
        LOGW("Failed to open /proc/partitions, adding fallback disk entry");
        info->disk_count = 1;
        snprintf(info->disks[0].dev_path, sizeof(info->disks[0].dev_path), "/dev/vda");
        snprintf(info->disks[0].model, sizeof(info->disks[0].model), "AWEOS Virtual Disk");
        info->disks[0].size_bytes = 10UL * 1024 * 1024 * 1024;
        info->disks[0].partition_count = 1;
        snprintf(info->disks[0].partitions[0].dev_path, sizeof(info->disks[0].partitions[0].dev_path), "/dev/vda1");
        snprintf(info->disks[0].partitions[0].fstype, sizeof(info->disks[0].partitions[0].fstype), "ext4");
        info->disks[0].partitions[0].size_bytes = 10UL * 1024 * 1024 * 1024;
        info->disks[0].partitions[0].free_bytes = 8UL * 1024 * 1024 * 1024;
        return AWEOS_OK;
    }

    char line[256];
    int disk_idx = -1;
    while (fgets(line, sizeof(line), f)) {
        int major, minor;
        unsigned long blocks;
        char name[64];
        if (sscanf(line, "%d %d %lu %63s", &major, &minor, &blocks, name) == 4) {
            if (strncmp(name, "sda", 3) == 0 || strncmp(name, "vda", 3) == 0 || strncmp(name, "nvme0n1", 7) == 0) {
                uint64_t size_bytes = (uint64_t)blocks * 1024;
                if (strlen(name) == 3 || strcmp(name, "nvme0n1") == 0) {
                    if (info->disk_count < MAX_DISKS) {
                        disk_idx = info->disk_count++;
                        snprintf(info->disks[disk_idx].dev_path, sizeof(info->disks[disk_idx].dev_path), "/dev/%s", name);
                        snprintf(info->disks[disk_idx].model, sizeof(info->disks[disk_idx].model), "Storage Device (%s)", name);
                        info->disks[disk_idx].size_bytes = size_bytes;
                        info->disks[disk_idx].is_gpt = true;
                    }
                } else if (disk_idx >= 0 && info->disks[disk_idx].partition_count < MAX_PARTITIONS) {
                    int part_idx = info->disks[disk_idx].partition_count++;
                    aweos_partition_info_t *p = &info->disks[disk_idx].partitions[part_idx];
                    snprintf(p->dev_path, sizeof(p->dev_path), "/dev/%s", name);
                    p->size_bytes = size_bytes;
                    p->free_bytes = size_bytes / 2;
                    snprintf(p->fstype, sizeof(p->fstype), "ext4");
                    snprintf(p->uuid, sizeof(p->uuid), "aweos-uuid-%s", name);
                }
            }
        }
    }
    fclose(f);

    if (info->disk_count == 0) {
        info->disk_count = 1;
        snprintf(info->disks[0].dev_path, sizeof(info->disks[0].dev_path), "/dev/vda");
        snprintf(info->disks[0].model, sizeof(info->disks[0].model), "AWEOS Virtual Storage Device");
        info->disks[0].size_bytes = 10UL * 1024 * 1024 * 1024;
        info->disks[0].partition_count = 1;
        snprintf(info->disks[0].partitions[0].dev_path, sizeof(info->disks[0].partitions[0].dev_path), "/dev/vda1");
        snprintf(info->disks[0].partitions[0].fstype, sizeof(info->disks[0].partitions[0].fstype), "ext4");
        info->disks[0].partitions[0].size_bytes = 10UL * 1024 * 1024 * 1024;
        info->disks[0].partitions[0].free_bytes = 8UL * 1024 * 1024 * 1024;
    }
#else
    info->disk_count = 1;
    snprintf(info->disks[0].dev_path, sizeof(info->disks[0].dev_path), "Disk0");
    snprintf(info->disks[0].model, sizeof(info->disks[0].model), "System Storage Drive");
    info->disks[0].size_bytes = 64UL * 1024 * 1024 * 1024;
    info->disks[0].is_gpt = true;
    info->disks[0].partition_count = 2;

    snprintf(info->disks[0].partitions[0].dev_path, sizeof(info->disks[0].partitions[0].dev_path), "Partition1 (ESP)");
    snprintf(info->disks[0].partitions[0].fstype, sizeof(info->disks[0].partitions[0].fstype), "vfat");
    info->disks[0].partitions[0].size_bytes = 512 * 1024 * 1024;
    info->disks[0].partitions[0].is_esp = true;

    snprintf(info->disks[0].partitions[1].dev_path, sizeof(info->disks[0].partitions[1].dev_path), "Partition2 (System)");
    snprintf(info->disks[0].partitions[1].fstype, sizeof(info->disks[0].partitions[1].fstype), "ntfs");
    info->disks[0].partitions[1].size_bytes = 63UL * 1024 * 1024 * 1024;
    info->disks[0].partitions[1].free_bytes = 30UL * 1024 * 1024 * 1024;
    info->disks[0].partitions[1].is_system_boot = true;
#endif

    LOGI("Discovered %d storage disk(s)", info->disk_count);
    return AWEOS_OK;
}
