#ifndef AWEOS_STORAGE_H
#define AWEOS_STORAGE_H

#include "types.h"

#define MAX_DISKS 16
#define MAX_PARTITIONS 16

typedef struct {
    char dev_path[128];     /* e.g., /dev/sda1 or C: */
    char uuid[64];          /* Filesystem UUID */
    char fstype[32];        /* e.g., ext4, ntfs, vfat */
    char label[64];         /* Volume label */
    uint64_t size_bytes;    /* Size in bytes */
    uint64_t free_bytes;    /* Free space in bytes */
    bool is_system_boot;   /* Is active OS partition */
    bool is_esp;           /* Is EFI System Partition */
    char mount_point[128];  /* Current mount point if mounted */
} aweos_partition_info_t;

typedef struct {
    char dev_path[128];     /* e.g., /dev/sda */
    char model[128];        /* Disk model name */
    uint64_t size_bytes;    /* Total disk size */
    bool is_gpt;           /* GPT vs MBR */
    int partition_count;
    aweos_partition_info_t partitions[MAX_PARTITIONS];
} aweos_disk_info_t;

typedef struct {
    int disk_count;
    aweos_disk_info_t disks[MAX_DISKS];
} aweos_storage_info_t;

int aweos_storage_discover(aweos_storage_info_t *info);
int aweos_detect_boot_mode(aweos_boot_mode_t *mode);

#endif /* AWEOS_STORAGE_H */
