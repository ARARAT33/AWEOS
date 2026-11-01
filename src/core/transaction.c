#include "transaction.h"
#include "logging.h"
#include "boot.h"
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

static int fail_transaction(aweos_transaction_t *tx, const char *message, int result) {
    if (!tx) return AWEOS_ERR_INVALID_PARAM;
    int saved_errno = errno;
    snprintf(tx->error_msg, sizeof(tx->error_msg), "%s", message);
    snprintf(tx->status_msg, sizeof(tx->status_msg), "Stopped safely: %.210s", message);
    tx->state = TX_STATE_FAILED;
    LOGE("%s", tx->error_msg);
    errno = saved_errno;
    return result;
}

static int require_state(aweos_transaction_t *tx, aweos_tx_state_t expected, const char *stage) {
    if (!tx) return AWEOS_ERR_INVALID_PARAM;
    if (tx->state != expected) {
        char message[192];
        snprintf(message, sizeof(message),
                 "Refusing transaction stage '%.64s' from state %d (expected %d)",
                 stage, (int)tx->state, (int)expected);
        return fail_transaction(tx, message, AWEOS_ERR_TRANSACTION);
    }
    return AWEOS_OK;
}

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
    if (require_state(tx, TX_STATE_PLAN, "plan") != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    LOGI("Planning installation transaction...");
    if (tx->config.install_mode == INSTALL_MODE_REPLACE_DISK && !tx->config.user_confirmed_destructive) {
        return fail_transaction(tx,
            "Full disk replacement requires explicit user confirmation; no disk changes were made",
            AWEOS_ERR_PERMISSION);
    }
    tx->progress_percent = 10;
    snprintf(tx->status_msg, sizeof(tx->status_msg), "Transaction plan constructed successfully");
    return AWEOS_OK;
}

int aweos_tx_validate(aweos_transaction_t *tx) {
    if (require_state(tx, TX_STATE_PLAN, "validate") != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    tx->state = TX_STATE_VALIDATE;
    LOGI("Validating transaction assets and target storage...");
    if (strlen(tx->config.iso_path) > 0) {
        int res = aweos_iso_validate(tx->config.iso_path, &tx->manifest);
        if (res != AWEOS_OK) {
            return fail_transaction(tx, "ISO validation failed; refusing to continue", res);
        }
    }
    tx->progress_percent = 25;
    snprintf(tx->status_msg, sizeof(tx->status_msg), "Transaction validation passed");
    return AWEOS_OK;
}

int aweos_tx_prepare(aweos_transaction_t *tx) {
    if (require_state(tx, TX_STATE_VALIDATE, "prepare") != AWEOS_OK) return AWEOS_ERR_TRANSACTION;

    /*
     * The repository does not yet contain a tested target-volume staging
     * backend. Returning success here previously let installer/updater flow
     * through no-op deployment/verification/commit stages and claim success.
     * Stop before archiving user data or touching disks.
     */
    return fail_transaction(tx,
        "Target-volume staging backend is not implemented; refusing to install or update",
        AWEOS_ERR_TRANSACTION);
}

int aweos_tx_preserve(aweos_transaction_t *tx) {
    if (require_state(tx, TX_STATE_PREPARE, "preserve") != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    tx->state = TX_STATE_PRESERVE;

    bool has_source = tx->config.preserve_src[0] != '\0';
    bool has_destination = tx->config.preserve_dst[0] != '\0';
    if (has_source != has_destination) {
        errno = EINVAL;
        return fail_transaction(tx,
            "Both preservation source and destination are required; refusing to continue",
            AWEOS_ERR_INVALID_PARAM);
    }

    if (has_source) {
        LOGI("Preserving user data '%s' -> '%s'...", tx->config.preserve_src, tx->config.preserve_dst);
        int res = aweos_archive_directory(tx->config.preserve_src, tx->config.preserve_dst, &tx->archive_stats);
        if (res != AWEOS_OK) {
            int saved_errno = errno;
            const char *reason = saved_errno ? strerror(saved_errno) : "unknown I/O error";
            char message[224];
            snprintf(message, sizeof(message), "Data preservation failed: %.180s", reason);
            int result = fail_transaction(tx, message, res);
            errno = saved_errno;
            return result;
        }
    }
    tx->progress_percent = 60;
    snprintf(tx->status_msg, sizeof(tx->status_msg), "Data preservation completed successfully");
    return AWEOS_OK;
}

int aweos_tx_execute(aweos_transaction_t *tx) {
    if (!tx) return AWEOS_ERR_INVALID_PARAM;
    aweos_tx_state_t expected = tx->config.install_mode == INSTALL_MODE_DUAL_BOOT
        ? TX_STATE_PRESERVE : TX_STATE_PREPARE;
    if (require_state(tx, expected, "execute") != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    return fail_transaction(tx,
        "System deployment backend is not implemented; refusing to write the target disk",
        AWEOS_ERR_TRANSACTION);
}

int aweos_tx_configure_boot(aweos_transaction_t *tx) {
    if (require_state(tx, TX_STATE_EXECUTE, "configure boot") != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    return fail_transaction(tx,
        "Target bootloader installation backend is not implemented; refusing to write boot files",
        AWEOS_ERR_TRANSACTION);
}

int aweos_tx_verify(aweos_transaction_t *tx) {
    if (require_state(tx, TX_STATE_BOOTCFG, "verify") != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    return fail_transaction(tx,
        "Installed-system verification backend is not implemented; refusing to report success",
        AWEOS_ERR_TRANSACTION);
}

int aweos_tx_commit(aweos_transaction_t *tx) {
    if (require_state(tx, TX_STATE_VERIFY, "commit") != AWEOS_OK) return AWEOS_ERR_TRANSACTION;
    return fail_transaction(tx,
        "Durable transaction commit backend is not implemented; refusing to report success",
        AWEOS_ERR_TRANSACTION);
}

int aweos_tx_abort(aweos_transaction_t *tx, const char *reason) {
    if (!tx) return AWEOS_ERR_INVALID_PARAM;
    tx->state = TX_STATE_ABORTED;
    snprintf(tx->error_msg, sizeof(tx->error_msg), "%s", reason ? reason : "Transaction aborted by user");
    snprintf(tx->status_msg, sizeof(tx->status_msg), "Transaction ABORTED");
    LOGW("Transaction ABORTED: %s", tx->error_msg);
    return AWEOS_OK;
}
