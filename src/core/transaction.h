#ifndef AWEOS_TRANSACTION_H
#define AWEOS_TRANSACTION_H

#include "types.h"
#include "storage.h"
#include "iso_verify.h"
#include "archive.h"

typedef struct {
    aweos_install_mode_t install_mode;
    aweos_boot_mode_t boot_mode;
    char target_disk[128];
    char target_partition[128];
    char iso_path[256];
    char preserve_src[256];
    char preserve_dst[256];
    bool user_confirmed_destructive;
} aweos_tx_config_t;

typedef struct {
    aweos_tx_state_t state;
    aweos_tx_config_t config;
    aweos_iso_manifest_t manifest;
    aweos_archive_stats_t archive_stats;
    int progress_percent;
    char status_msg[256];
    char error_msg[256];
} aweos_transaction_t;

int aweos_tx_init(aweos_transaction_t *tx, const aweos_tx_config_t *config);
int aweos_tx_plan(aweos_transaction_t *tx);
int aweos_tx_validate(aweos_transaction_t *tx);
int aweos_tx_prepare(aweos_transaction_t *tx);
int aweos_tx_preserve(aweos_transaction_t *tx);
int aweos_tx_execute(aweos_transaction_t *tx);
int aweos_tx_configure_boot(aweos_transaction_t *tx);
int aweos_tx_verify(aweos_transaction_t *tx);
int aweos_tx_commit(aweos_transaction_t *tx);
int aweos_tx_abort(aweos_transaction_t *tx, const char *reason);

#endif /* AWEOS_TRANSACTION_H */
