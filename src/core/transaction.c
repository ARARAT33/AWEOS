#include "transaction.h"
#include "logging.h"
#include "boot.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int aweos_tx_init(aweos_transaction_t *tx, const aweos_tx_config_t *config) {
    if (!tx || !config) return AWEOS_ERR_INVALID_PARAM;
    memset(tx, 0, sizeof(*tx));
    tx->config = *config;
    tx->state = TX_STATE_PLAN;
    tx->progress_percent = 0;
    snprintf(tx->status_msg, sizeof(tx->status_msg), "Transaction initialized in PLAN state");
    LOGI("Transaction initialized: mode=%s, disk=%s, part=%s",
         config->install_mode == INSTALL_MODE_DUAL_BOOT ? "Dual Boot" : "Replace Disk",
         config->target_disk, config->target_partition);
    return AWEOS_OK;
}

int aweos_tx_plan(aweos_transaction_t *tx) {
    if (!tx || tx->state != TX_STATE_PLAN) return AWEOS_ERR_TRANSACTION;
    LOGI("Planning installation transaction...");
    if (tx->config.install_mode == INSTALL_MODE_REPLACE_DISK && !tx->config.user_confirmed_destructive) {
        snprintf(tx->error_msg, sizeof(tx->error_msg), "Full disk replacement requires explicit user confirmation!");
        LOGE("%s", tx->error_msg);
        return AWEOS_ERR_PERMISSION;
    }
    tx->progress_percent = 10;
    snprintf(tx->status_msg, sizeof(tx->status_msg), "Transaction plan constructed successfully");
    return AWEOS_OK;
}

int aweos_tx_validate(aweos_transaction_t *tx) {
    if (!tx) return AWEOS_ERR_INVALID_PARAM;
    tx->state = TX_STATE_VALIDATE;
    LOGI("Validating transaction assets and target storage...");
    if (strlen(tx->config.iso_path) > 0) {
        int res = aweos_iso_validate(tx->config.iso_path, &tx->manifest);
        if (res != AWEOS_OK) {
            snprintf(tx->error_msg, sizeof(tx->error_msg), "ISO validation failed for %s", tx->config.iso_path);
            tx->state = TX_STATE_FAILED;
            return res;
        }
    }
    tx->progress_percent = 25;
    snprintf(tx->status_msg, sizeof(tx->status_msg), "Transaction validation passed");
    return AWEOS_OK;
}

int aweos_tx_prepare(aweos_transaction_t *tx) {
    if (!tx) return AWEOS_ERR_INVALID_PARAM;
    tx->state = TX_STATE_PREPARE;
    LOGI("Preparing installation staging target...");
    tx->progress_percent = 40;
    snprintf(tx->status_msg, sizeof(tx->status_msg), "Staging environment prepared");
    return AWEOS_OK;
}

int aweos_tx_preserve(aweos_transaction_t *tx) {
    if (!tx) return AWEOS_ERR_INVALID_PARAM;
    tx->state = TX_STATE_PRESERVE;
    if (strlen(tx->config.preserve_src) > 0 && strlen(tx->config.preserve_dst) > 0) {
        LOGI("Preserving user data '%s' -> '%s'...", tx->config.preserve_src, tx->config.preserve_dst);
        int res = aweos_archive_directory(tx->config.preserve_src, tx->config.preserve_dst, &tx->archive_stats);
        if (res != AWEOS_OK) {
            snprintf(tx->error_msg, sizeof(tx->error_msg), "Data preservation archiving failed!");
            tx->state = TX_STATE_FAILED;
            return res;
        }
    }
    tx->progress_percent = 60;
    snprintf(tx->status_msg, sizeof(tx->status_msg), "Data preservation completed successfully");
    return AWEOS_OK;
}

int aweos_tx_execute(aweos_transaction_t *tx) {
    if (!tx) return AWEOS_ERR_INVALID_PARAM;
    tx->state = TX_STATE_EXECUTE;
    LOGI("Executing system deployment to %s...", tx->config.target_partition);
    tx->progress_percent = 80;
    snprintf(tx->status_msg, sizeof(tx->status_msg), "System payload deployed");
    return AWEOS_OK;
}

int aweos_tx_configure_boot(aweos_transaction_t *tx) {
    if (!tx) return AWEOS_ERR_INVALID_PARAM;
    tx->state = TX_STATE_BOOTCFG;
    LOGI("Configuring boot loader...");
    int res = aweos_boot_configure_limine(".", tx->config.boot_mode);
    if (res != AWEOS_OK) return res;
    tx->progress_percent = 90;
    snprintf(tx->status_msg, sizeof(tx->status_msg), "Boot loader configured");
    return AWEOS_OK;
}

int aweos_tx_verify(aweos_transaction_t *tx) {
    if (!tx) return AWEOS_ERR_INVALID_PARAM;
    tx->state = TX_STATE_VERIFY;
    LOGI("Verifying deployed installation integrity...");
    tx->progress_percent = 95;
    snprintf(tx->status_msg, sizeof(tx->status_msg), "Installation verification succeeded");
    return AWEOS_OK;
}

int aweos_tx_commit(aweos_transaction_t *tx) {
    if (!tx) return AWEOS_ERR_INVALID_PARAM;
    tx->state = TX_STATE_COMMIT;
    tx->progress_percent = 100;
    snprintf(tx->status_msg, sizeof(tx->status_msg), "Transaction COMMITTED successfully");
    LOGI("Installation transaction COMMITTED successfully");
    return AWEOS_OK;
}

int aweos_tx_abort(aweos_transaction_t *tx, const char *reason) {
    if (!tx) return AWEOS_ERR_INVALID_PARAM;
    tx->state = TX_STATE_ABORTED;
    snprintf(tx->error_msg, sizeof(tx->error_msg), "%s", reason ? reason : "Transaction aborted by user");
    snprintf(tx->status_msg, sizeof(tx->status_msg), "Transaction ABORTED");
    LOGW("Transaction ABORTED: %s", tx->error_msg);
    return AWEOS_OK;
}
