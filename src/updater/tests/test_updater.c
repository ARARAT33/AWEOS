#define _GNU_SOURCE
#include "../updater.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static aweos_boot_mode_t simulated_boot_mode = BOOT_MODE_BIOS;
static int detect_result = AWEOS_OK;
static int iso_validate_result = AWEOS_OK;
static int preserve_result = AWEOS_OK;
static int detect_calls, init_calls, preserve_calls, execute_calls;
static int configure_calls, verify_calls, commit_calls;
static aweos_tx_config_t captured_config;

static void reset_simulation(aweos_boot_mode_t mode) {
    simulated_boot_mode = mode;
    detect_result = AWEOS_OK;
    iso_validate_result = AWEOS_OK;
    preserve_result = AWEOS_OK;
    detect_calls = init_calls = preserve_calls = execute_calls = 0;
    configure_calls = verify_calls = commit_calls = 0;
    memset(&captured_config, 0, sizeof(captured_config));
}

int aweos_detect_boot_mode(aweos_boot_mode_t *mode) {
    detect_calls++;
    if (detect_result != AWEOS_OK) return detect_result;
    *mode = simulated_boot_mode;
    return AWEOS_OK;
}

int aweos_iso_validate(const char *iso_path, aweos_iso_manifest_t *manifest) {
    if (!iso_path || !manifest) return AWEOS_ERR_INVALID_PARAM;
    if (iso_validate_result != AWEOS_OK) return iso_validate_result;
    snprintf(manifest->version, sizeof(manifest->version), "2.0.0");
    return AWEOS_OK;
}

int aweos_tx_init(aweos_transaction_t *tx, const aweos_tx_config_t *config) {
    assert(tx && config);
    init_calls++;
    memset(tx, 0, sizeof(*tx));
    tx->config = *config;
    captured_config = *config;
    return AWEOS_OK;
}
int aweos_tx_plan(aweos_transaction_t *tx) { assert(tx); return AWEOS_OK; }
int aweos_tx_validate(aweos_transaction_t *tx) { assert(tx); return AWEOS_OK; }
int aweos_tx_prepare(aweos_transaction_t *tx) { assert(tx); return AWEOS_OK; }
int aweos_tx_preserve(aweos_transaction_t *tx) {
    assert(tx);
    preserve_calls++;
    if (preserve_result != AWEOS_OK) {
        snprintf(tx->error_msg, sizeof(tx->error_msg), "simulated backup failure");
        tx->state = TX_STATE_FAILED;
    }
    return preserve_result;
}
int aweos_tx_execute(aweos_transaction_t *tx) {
    assert(tx);
    execute_calls++;
    return AWEOS_OK;
}
int aweos_tx_configure_boot(aweos_transaction_t *tx) {
    assert(tx);
    configure_calls++;
    return AWEOS_OK;
}
int aweos_tx_verify(aweos_transaction_t *tx) { assert(tx); verify_calls++; return AWEOS_OK; }
int aweos_tx_commit(aweos_transaction_t *tx) { assert(tx); commit_calls++; return AWEOS_OK; }
int aweos_tx_abort(aweos_transaction_t *tx, const char *reason) {
    (void)tx; (void)reason; return AWEOS_OK;
}

static void init_ready_updater(aweos_updater_state_t *st) {
    assert(aweos_updater_init(st, "/tmp/aweos-update.iso") == AWEOS_OK);
    assert(st->ready_to_update);
    assert(st->preserve_user_data);
    assert(strcmp(st->candidate_version, "2.0.0") == 0);
}

static void test_detected_boot_mode(aweos_boot_mode_t mode) {
    reset_simulation(mode);
    aweos_updater_state_t st;
    init_ready_updater(&st);
    assert(aweos_updater_run(&st) == AWEOS_OK);
    assert(detect_calls == 1);
    assert(init_calls == 1);
    assert(captured_config.boot_mode == mode);
    assert(captured_config.install_mode == INSTALL_MODE_DUAL_BOOT);
    assert(!captured_config.user_confirmed_destructive);
    assert(strcmp(captured_config.preserve_src, "/home") == 0);
    assert(strcmp(captured_config.preserve_dst, "/archiveddata/home") == 0);
    assert(preserve_calls == 1);
    assert(execute_calls == 1);
    assert(configure_calls == 1 && verify_calls == 1 && commit_calls == 1);
}

static void test_preservation_failure_stops_update(void) {
    reset_simulation(BOOT_MODE_UEFI);
    preserve_result = AWEOS_ERR_IO;
    aweos_updater_state_t st;
    init_ready_updater(&st);
    assert(aweos_updater_run(&st) == AWEOS_ERR_TRANSACTION);
    assert(preserve_calls == 1);
    assert(execute_calls == 0);
    assert(configure_calls == 0 && verify_calls == 0 && commit_calls == 0);
}

static void test_unknown_or_unavailable_boot_mode_stops_update(void) {
    reset_simulation(BOOT_MODE_UNKNOWN);
    aweos_updater_state_t st;
    init_ready_updater(&st);
    assert(aweos_updater_run(&st) == AWEOS_ERR_TRANSACTION);
    assert(init_calls == 0 && execute_calls == 0);

    reset_simulation(BOOT_MODE_BIOS);
    detect_result = AWEOS_ERR_IO;
    init_ready_updater(&st);
    assert(aweos_updater_run(&st) == AWEOS_ERR_TRANSACTION);
    assert(init_calls == 0 && execute_calls == 0);
}

static void test_disabling_preservation_is_rejected(void) {
    reset_simulation(BOOT_MODE_UEFI);
    aweos_updater_state_t st;
    init_ready_updater(&st);
    st.preserve_user_data = false;
    assert(aweos_updater_run(&st) == AWEOS_ERR_PERMISSION);
    assert(detect_calls == 0 && init_calls == 0);
    assert(preserve_calls == 0 && execute_calls == 0);
}

static void test_invalid_iso_is_rejected(void) {
    reset_simulation(BOOT_MODE_BIOS);
    iso_validate_result = AWEOS_ERR_VERIFY;
    aweos_updater_state_t st;
    assert(aweos_updater_init(&st, "/tmp/bad.iso") == AWEOS_ERR_VERIFY);
    assert(!st.ready_to_update);
    assert(st.preserve_user_data);
}

int main(void) {
    test_detected_boot_mode(BOOT_MODE_BIOS);
    test_detected_boot_mode(BOOT_MODE_UEFI);
    test_preservation_failure_stops_update();
    test_unknown_or_unavailable_boot_mode_stops_update();
    test_disabling_preservation_is_rejected();
    test_invalid_iso_is_rejected();
    puts("PASS: updater detects BIOS/UEFI, rejects unknown modes, and never executes after backup failure or disabled preservation.");
    return 0;
}
