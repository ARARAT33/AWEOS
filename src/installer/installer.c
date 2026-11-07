#include "installer.h"
#include "../core/logging.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int aweos_installer_init(aweos_installer_state_t *st) {
    if (!st) return AWEOS_ERR_INVALID_PARAM;
    memset(st, 0, sizeof(*st));
    st->selected_disk_idx = -1;
    st->selected_part_idx = -1;
    st->boot_mode = BOOT_MODE_UNKNOWN;

    int result = aweos_detect_boot_mode(&st->boot_mode);
    if (result != AWEOS_OK ||
        (st->boot_mode != BOOT_MODE_BIOS && st->boot_mode != BOOT_MODE_UEFI)) {
        st->boot_mode = BOOT_MODE_UNKNOWN;
        LOGE("Installer cannot determine a supported BIOS/UEFI boot mode; refusing to continue");
        return result != AWEOS_OK ? result : AWEOS_ERR_TRANSACTION;
    }

    result = aweos_storage_discover(&st->storage);
    if (result != AWEOS_OK) {
        LOGE("Installer storage discovery failed; no target disk will be assumed");
        return result;
    }
    if (st->storage.disk_count <= 0) {
        LOGE("No real target disk was discovered; refusing to show a synthetic device");
        return AWEOS_ERR_NOT_FOUND;
    }

    /* Discovery is informational only. A caller must explicitly select
     * a target through aweos_installer_select_target() before installation. */
    st->mode = INSTALL_MODE_DUAL_BOOT;
    st->confirmed_destructive = false;

    LOGI("AWEOS Installer initialized: %d discovered disk(s), Boot Mode: %s",
         st->storage.disk_count, st->boot_mode == BOOT_MODE_UEFI ? "UEFI" : "BIOS");
    return AWEOS_OK;
}

int aweos_installer_select_target(aweos_installer_state_t *st, int disk_idx, int partition_idx) {
    if (!st) return AWEOS_ERR_INVALID_PARAM;
    if (disk_idx < 0 || disk_idx >= st->storage.disk_count) {
        LOGE("Target disk selection is out of range; refusing to assume a disk");
        return AWEOS_ERR_INVALID_PARAM;
    }

    const aweos_disk_info_t *disk = &st->storage.disks[disk_idx];
    if (disk->dev_path[0] == '\0') {
        LOGE("Selected target disk has no verified device path");
        return AWEOS_ERR_INVALID_PARAM;
    }

    if (st->mode == INSTALL_MODE_DUAL_BOOT) {
        if (partition_idx < 0 || partition_idx >= disk->partition_count ||
            disk->partitions[partition_idx].dev_path[0] == '\0') {
            LOGE("Dual-boot installation requires an explicitly selected valid partition");
            return AWEOS_ERR_INVALID_PARAM;
        }
    } else if (st->mode == INSTALL_MODE_REPLACE_DISK) {
        if (partition_idx != -1) {
            LOGE("Full-disk replacement selects a disk, not a partition");
            return AWEOS_ERR_INVALID_PARAM;
        }
    } else {
        LOGE("Unsupported installer mode; refusing target selection");
        return AWEOS_ERR_INVALID_PARAM;
    }

    st->selected_disk_idx = disk_idx;
    st->selected_part_idx = partition_idx;
    return AWEOS_OK;
}

int aweos_installer_run_cli(aweos_installer_state_t *st) {
    if (!st) return AWEOS_ERR_INVALID_PARAM;

    LOGI("Running AWEOS Installer Execution Flow...");
    aweos_tx_config_t cfg = {
        .install_mode = st->mode,
        .boot_mode = st->boot_mode,
        .user_confirmed_destructive = st->confirmed_destructive
    };

    if ((st->mode != INSTALL_MODE_DUAL_BOOT && st->mode != INSTALL_MODE_REPLACE_DISK) ||
        (st->boot_mode != BOOT_MODE_BIOS && st->boot_mode != BOOT_MODE_UEFI) ||
        st->storage.disk_count <= 0 || st->selected_disk_idx < 0 ||
        st->selected_disk_idx >= st->storage.disk_count) {
        LOGE("No valid, explicitly selected target disk or supported boot mode; refusing to install");
        return AWEOS_ERR_INVALID_PARAM;
    }

    const aweos_disk_info_t *target_disk = &st->storage.disks[st->selected_disk_idx];
    if (target_disk->dev_path[0] == '\0') {
        LOGE("Selected target disk has no verified device path; refusing to install");
        return AWEOS_ERR_INVALID_PARAM;
    }
    snprintf(cfg.target_disk, sizeof(cfg.target_disk), "%s", target_disk->dev_path);

    if (st->mode == INSTALL_MODE_DUAL_BOOT) {
        if (st->selected_part_idx < 0 ||
            st->selected_part_idx >= target_disk->partition_count ||
            target_disk->partitions[st->selected_part_idx].dev_path[0] == '\0') {
            LOGE("Dual-boot installation requires an explicitly selected valid target partition");
            return AWEOS_ERR_INVALID_PARAM;
        }
        snprintf(cfg.target_partition, sizeof(cfg.target_partition), "%s",
                 target_disk->partitions[st->selected_part_idx].dev_path);
    } else if (st->selected_part_idx != -1) {
        LOGE("Full-disk replacement must not carry an implicit partition selection");
        return AWEOS_ERR_INVALID_PARAM;
    }

    if (st->mode == INSTALL_MODE_DUAL_BOOT) {
        snprintf(cfg.preserve_src, sizeof(cfg.preserve_src), "/home");
        snprintf(cfg.preserve_dst, sizeof(cfg.preserve_dst), "/archiveddata/home");
    }

    if (aweos_tx_init(&st->tx, &cfg) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_plan(&st->tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_validate(&st->tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_prepare(&st->tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (st->mode == INSTALL_MODE_DUAL_BOOT && aweos_tx_preserve(&st->tx) != AWEOS_OK) {
        LOGE("User-data preservation failed; installation aborted before execution: %s", st->tx.error_msg);
        return AWEOS_ERR_TRANSACTION;
    }
    if (aweos_tx_execute(&st->tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_configure_boot(&st->tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_verify(&st->tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_commit(&st->tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;

    LOGI("AWEOS Installation to %s completed successfully!", cfg.target_disk);
    return AWEOS_OK;
}
