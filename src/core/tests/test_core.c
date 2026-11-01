#include "../types.h"
#include "../logging.h"
#include "../storage.h"
#include "../transaction.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>

int main(void) {
    LOGI("Running AWEOS Shared Core Unit Tests...");

    aweos_boot_mode_t bmode = BOOT_MODE_UNKNOWN;
    assert(aweos_detect_boot_mode(&bmode) == AWEOS_OK);
    assert(bmode == BOOT_MODE_BIOS || bmode == BOOT_MODE_UEFI);

    aweos_storage_info_t sinfo;
    assert(aweos_storage_discover(&sinfo) == AWEOS_OK);

    /*
     * The target-volume staging/deployment backend is not implemented yet.
     * The transaction must stop here rather than claim a successful install.
     */
    aweos_tx_config_t cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.install_mode = INSTALL_MODE_DUAL_BOOT;
    cfg.boot_mode = bmode;
    cfg.user_confirmed_destructive = false;
    snprintf(cfg.target_disk, sizeof(cfg.target_disk), "/dev/aweos-test-disk");
    snprintf(cfg.target_partition, sizeof(cfg.target_partition), "/dev/aweos-test-partition");

    aweos_transaction_t tx;
    assert(aweos_tx_init(&tx, &cfg) == AWEOS_OK);
    assert(aweos_tx_plan(&tx) == AWEOS_OK);
    assert(aweos_tx_validate(&tx) == AWEOS_OK);
    assert(aweos_tx_prepare(&tx) == AWEOS_ERR_TRANSACTION);
    assert(tx.state == TX_STATE_FAILED);
    assert(tx.progress_percent < 100);
    assert(strstr(tx.error_msg, "not implemented") != NULL);

    assert(aweos_tx_preserve(&tx) == AWEOS_ERR_TRANSACTION);
    assert(aweos_tx_execute(&tx) == AWEOS_ERR_TRANSACTION);
    assert(aweos_tx_configure_boot(&tx) == AWEOS_ERR_TRANSACTION);
    assert(aweos_tx_verify(&tx) == AWEOS_ERR_TRANSACTION);
    assert(aweos_tx_commit(&tx) == AWEOS_ERR_TRANSACTION);

    LOGI("AWEOS shared core correctly refuses to report installation success while deployment backends are unavailable.");
    return 0;
}
