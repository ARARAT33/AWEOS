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
    *mode = BOOT_MODE_UNKNOWN;
    return AWEOS_ERR_NOT_FOUND;
#endif
    return AWEOS_OK;
}

#if defined(__linux__)
#ifndef AWEOS_PROC_PARTITIONS_PATH
#define AWEOS_PROC_PARTITIONS_PATH "/proc/partitions"
#endif

static bool all_digits(const char *value) {
    if (!value || !*value) return false;
    for (const unsigned char *p = (const unsigned char *)value; *p; ++p) {
        if (*p < '0' || *p > '9') return false;
    }
    return true;
}

static bool all_lowercase_letters(const char *value) {
    if (!value || !*value) return false;
    for (const unsigned char *p = (const unsigned char *)value; *p; ++p) {
        if (*p < 'a' || *p > 'z') return false;
    }
    return true;
}

static bool is_nvme_namespace_name(const char *name) {
    const char *p = name;
    if (strncmp(p, "nvme", 4) != 0) return false;
    p += 4;
    const char *controller = p;
    while (*p >= '0' && *p <= '9') ++p;
    if (p == controller || *p++ != 'n') return false;
    const char *namespace_id = p;
    while (*p >= '0' && *p <= '9') ++p;
    return p != namespace_id && *p == '\0';
}

static bool is_disk_name(const char *name) {
    if (!name || !*name) return false;
    if (strncmp(name, "sd", 2) == 0) return all_lowercase_letters(name + 2);
    if (strncmp(name, "vd", 2) == 0) return all_lowercase_letters(name + 2);
    if (strncmp(name, "xvd", 3) == 0) return all_lowercase_letters(name + 3);
    if (strncmp(name, "mmcblk", 6) == 0) return all_digits(name + 6);
    return is_nvme_namespace_name(name);
}

static bool is_partition_of(const char *disk, const char *candidate) {
    size_t disk_len = strlen(disk);
    if (strncmp(disk, candidate, disk_len) != 0) return false;
    const char *suffix = candidate + disk_len;
    if (strncmp(disk, "nvme", 4) == 0 || strncmp(disk, "mmcblk", 6) == 0) {
        if (*suffix != 'p') return false;
        ++suffix;
    }
    return all_digits(suffix);
}

static int find_parent_disk(const aweos_storage_info_t *info, const char *partition_name) {
    int match = -1;
    size_t longest = 0;
    for (int i = 0; i < info->disk_count; ++i) {
        const char *path = info->disks[i].dev_path;
        const char *name = strrchr(path, '/');
        name = name ? name + 1 : path;
        size_t length = strlen(name);
        if (length > longest && is_partition_of(name, partition_name)) {
            match = i;
            longest = length;
        }
    }
    return match;
}
#endif

int aweos_storage_discover(aweos_storage_info_t *info) {
    if (!info) return AWEOS_ERR_INVALID_PARAM;
    memset(info, 0, sizeof(*info));

#if defined(__linux__)
    FILE *f = fopen(AWEOS_PROC_PARTITIONS_PATH, "r");
    if (!f) {
        LOGE("Cannot read %s; refusing to invent a target disk: %s",
             AWEOS_PROC_PARTITIONS_PATH, strerror(errno));
        return AWEOS_ERR_IO;
    }

    char line[256];
    while (fgets(line, sizeof(line), f)) {
        int major, minor;
        unsigned long blocks;
        char name[64];
        if (sscanf(line, "%d %d %lu %63s", &major, &minor, &blocks, name) != 4) continue;
        (void)major;
        (void)minor;
        if ((uint64_t)blocks > UINT64_MAX / 1024U) continue;
        uint64_t size_bytes = (uint64_t)blocks * 1024U;

        if (is_disk_name(name)) {
            if (info->disk_count >= MAX_DISKS) continue;
            int disk_idx = info->disk_count++;
            aweos_disk_info_t *disk = &info->disks[disk_idx];
            snprintf(disk->dev_path, sizeof(disk->dev_path), "/dev/%s", name);
            snprintf(disk->model, sizeof(disk->model), "Block device (%s)", name);
            disk->size_bytes = size_bytes;
            /* Partition-table type, filesystem, UUID and free space are unknown here.
             * Do not populate guessed values; a later probe must establish them.
             */
            continue;
        }

        int parent_idx = find_parent_disk(info, name);
        if (parent_idx < 0) continue;
        aweos_disk_info_t *disk = &info->disks[parent_idx];
        if (disk->partition_count >= MAX_PARTITIONS) continue;
        aweos_partition_info_t *partition = &disk->partitions[disk->partition_count++];
        snprintf(partition->dev_path, sizeof(partition->dev_path), "/dev/%s", name);
        partition->size_bytes = size_bytes;
    }
    int read_error = ferror(f);
    fclose(f);
    if (read_error) {
        memset(info, 0, sizeof(*info));
        LOGE("Failed while reading %s", AWEOS_PROC_PARTITIONS_PATH);
        return AWEOS_ERR_IO;
    }

    if (info->disk_count == 0) {
        LOGW("No supported physical block devices were discovered; refusing to create a synthetic /dev/vda entry");
        return AWEOS_ERR_NOT_FOUND;
    }
#else
    LOGE("Storage discovery is not implemented on this platform; refusing to invent a target disk");
    return AWEOS_ERR_NOT_FOUND;
#endif

    LOGI("Discovered %d storage disk(s)", info->disk_count);
    return AWEOS_OK;
}
