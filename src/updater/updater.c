#include "updater.h"
#include "../core/logging.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int aweos_updater_init(aweos_updater_state_t *st, const char *iso_path) {
    if (!st || !iso_path) return AWEOS_ERR_INVALID_PARAM;
    memset(st, 0, sizeof(*st));

    snprintf(st->current_version, sizeof(st->current_version), "%s", AWEOS_VERSION);
    snprintf(st->iso_path, sizeof(st->iso_path), "%s", iso_path);
    st->preserve_user_data = true;

    aweos_iso_manifest_t manifest;
    int res = aweos_iso_validate(iso_path, &manifest);
    if (res != AWEOS_OK) {
        LOGE("Updater failed: ISO validation error for %s", iso_path);
        return res;
    }

    snprintf(st->candidate_version, sizeof(st->candidate_version), "%s", manifest.version);
    st->ready_to_update = true;

    LOGI("AWEOS Updater initialized: Current v%s -> Candidate v%s (ISO: %s)",
         st->current_version, st->candidate_version, st->iso_path);
    return AWEOS_OK;
}

int aweos_updater_run(aweos_updater_state_t *st) {
    if (!st || !st->ready_to_update) return AWEOS_ERR_TRANSACTION;

    LOGI("Starting safe AWEOS OS update to version %s...", st->candidate_version);

    aweos_tx_config_t cfg = {
        .install_mode = INSTALL_MODE_DUAL_BOOT,
        .boot_mode = BOOT_MODE_BIOS,
        .user_confirmed_destructive = false
    };
    snprintf(cfg.iso_path, sizeof(cfg.iso_path), "%s", st->iso_path);
    snprintf(cfg.preserve_src, sizeof(cfg.preserve_src), "/home");
    snprintf(cfg.preserve_dst, sizeof(cfg.preserve_dst), "/archiveddata/home");

    aweos_transaction_t tx;
    if (aweos_tx_init(&tx, &cfg) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_plan(&tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_validate(&tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_prepare(&tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (st->preserve_user_data) {
        aweos_tx_preserve(&tx);
    }
    if (aweos_tx_execute(&tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_configure_boot(&tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_verify(&tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    if (aweos_tx_commit(&tx) != AWEOS_OK) return AWEOS_ERR_TRANSACTION;

    LOGI("AWEOS System Update to v%s completed successfully! User data preserved.", st->candidate_version);
    return AWEOS_OK;
}
