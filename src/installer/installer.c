#include "installer.h"
#include "../core/logging.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int aweos_installer_init(aweos_installer_state_t *st) {
    if (!st) return AWEOS_ERR_INVALID_PARAM;
    memset(st, 0, sizeof(*st));

    aweos_detect_boot_mode(&st->boot_mode);
    aweos_storage_discover(&st->storage);

    st->selected_disk_idx = 0;
    st->selected_part_idx = 0;
    st->mode = INSTALL_MODE_DUAL_BOOT;
    st->confirmed_destructive = false;

    LOGI("AWEOS Installer initialized: %d disk(s) found, Boot Mode: %s",
         st->storage.disk_count, st->boot_mode == BOOT_MODE_UEFI ? "UEFI" : "BIOS");
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

    if (st->storage.disk_count > 0) {
        snprintf(cfg.target_disk, sizeof(cfg.target_disk), "%s", st->storage.disks[st->selected_disk_idx].dev_path);
        if (st->storage.disks[st->selected_disk_idx].partition_count > 0) {
            snprintf(cfg.target_partition, sizeof(cfg.target_partition), "%s",
                     st->storage.disks[st->selected_disk_idx].partitions[st->selected_part_idx].dev_path);
        }
    }

    if (st->mode == INSTALL_MODE_DUAL_BOOT) {
        snprintf(cfg.preserve_src, sizeof(cfg.preserve_src), "/home");
        snprintf(cfg.preserve_dst, sizeof(cfg.preserve_dst), "/archiveddata/home");
    }

    if (aweos_tx_init(&st->tx, &cfg) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_plan(&st->tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_validate(&st->tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_prepare(&st->tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (st->mode == INSTALL_MODE_DUAL_BOOT) {
        aweos_tx_preserve(&st->tx);
    }
    if (aweos_tx_execute(&st->tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_configure_boot(&st->tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_verify(&st->tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_commit(&st->tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;

    LOGI("AWEOS Installation to %s completed successfully!", cfg.target_disk);
    return AWEOS_OK;
}
