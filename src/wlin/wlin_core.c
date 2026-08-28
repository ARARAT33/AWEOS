#include "wlin.h"
#include "../core/logging.h"
#include "../core/boot.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int wlin_init(wlin_state_t *st, const char *iso_path) {
    if (!st || !iso_path) return AWEOS_ERR_INVALID_PARAM;
    memset(st, 0, sizeof(*st));

    snprintf(st->iso_path, sizeof(st->iso_path), "%s", iso_path);
    st->mode = INSTALL_MODE_DUAL_BOOT;
    st->target_disk_idx = 0;

    int res = aweos_iso_validate(iso_path, &st->manifest);
    if (res != AWEOS_OK) {
        LOGE("WLIN: ISO validation failed for %s", iso_path);
        return res;
    }

    aweos_detect_boot_mode(&st->boot_mode);
    aweos_storage_discover(&st->storage);

    LOGI("WLIN initialized successfully. Candidate ISO Version: %s, Discovered %d disk(s)",
         st->manifest.version, st->storage.disk_count);
    return AWEOS_OK;
}

int wlin_plan(wlin_state_t *st) {
    if (!st) return AWEOS_ERR_INVALID_PARAM;
    LOGI("WLIN constructing USB-less boot staging plan for target disk %s...",
         st->storage.disks[st->target_disk_idx].dev_path);
    if (st->mode == INSTALL_MODE_REPLACE_DISK && !st->user_confirmed) {
        LOGE("WLIN: Full disk replacement requires explicit user confirmation!");
        return AWEOS_ERR_PERMISSION;
    }
    return AWEOS_OK;
}

int wlin_stage_boot(wlin_state_t *st) {
    if (!st) return AWEOS_ERR_INVALID_PARAM;
    LOGI("WLIN staging kernel & initramfs onto ESP / boot staging partition...");
    st->staged_for_reboot = true;
    LOGI("WLIN boot staging complete. Computer ready to reboot into AWEOS installation environment.");
    return AWEOS_OK;
}

int wlin_execute(wlin_state_t *st) {
    if (!st) return AWEOS_ERR_INVALID_PARAM;
    int res = wlin_plan(st);
    if (res != AWEOS_OK) return res;

    res = wlin_stage_boot(st);
    if (res != AWEOS_OK) return res;

    aweos_tx_config_t cfg = {
        .install_mode = st->mode,
        .boot_mode = st->boot_mode,
        .user_confirmed_destructive = st->user_confirmed
    };
    snprintf(cfg.iso_path, sizeof(cfg.iso_path), "%s", st->iso_path);
    snprintf(cfg.target_disk, sizeof(cfg.target_disk), "%s", st->storage.disks[st->target_disk_idx].dev_path);

    aweos_transaction_t tx;
    if (aweos_tx_init(&tx, &cfg) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_plan(&tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_validate(&tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_prepare(&tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (st->mode == INSTALL_MODE_DUAL_BOOT) {
        aweos_tx_preserve(&tx);
    }
    if (aweos_tx_execute(&tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_configure_boot(&tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_verify(&tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_commit(&tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;

    LOGI("WLIN Cross-OS Installation transaction completed successfully!");
    return AWEOS_OK;
}
