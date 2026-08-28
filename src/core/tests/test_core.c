#include "../types.h"
#include "../logging.h"
#include "../storage.h"
#include "../iso_verify.h"
#include "../archive.h"
#include "../boot.h"
#include "../transaction.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>

int main(void) {
    LOGI("Running AWEOS Shared Core Unit Tests...");

    // Test 1: Boot Mode Detection
    aweos_boot_mode_t bmode;
    assert(aweos_detect_boot_mode(&bmode) == AWEOS_OK);

    // Test 2: Storage Discovery
    aweos_storage_info_t sinfo;
    assert(aweos_storage_discover(&sinfo) == AWEOS_OK);
    assert(sinfo.disk_count >= 1);

    // Test 3: Transaction Engine (Plan, Validate, Prepare, Preserve, Execute, Boot, Verify, Commit)
    aweos_tx_config_t cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.install_mode = INSTALL_MODE_DUAL_BOOT;
    cfg.boot_mode = bmode;
    cfg.user_confirmed_destructive = false;
    snprintf(cfg.target_disk, sizeof(cfg.target_disk), "/dev/vda");
    snprintf(cfg.target_partition, sizeof(cfg.target_partition), "/dev/vda1");

    aweos_transaction_t tx;
    assert(aweos_tx_init(&tx, &cfg) == AWEOS_OK);
    assert(aweos_tx_plan(&tx) == AWEOS_OK);
    assert(aweos_tx_validate(&tx) == AWEOS_OK);
    assert(aweos_tx_prepare(&tx) == AWEOS_OK);
    assert(aweos_tx_preserve(&tx) == AWEOS_OK);
    assert(aweos_tx_execute(&tx) == AWEOS_OK);
    assert(aweos_tx_configure_boot(&tx) == AWEOS_OK);
    assert(aweos_tx_verify(&tx) == AWEOS_OK);
    assert(aweos_tx_commit(&tx) == AWEOS_OK);

    LOGI("All AWEOS Shared Core Unit Tests PASSED successfully!");
    return 0;
}
