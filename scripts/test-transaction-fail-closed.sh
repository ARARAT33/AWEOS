#!/usr/bin/env bash
# Compile and exercise the C transaction state machine with side-effect stubs.
# No real block devices, filesystems, or bootloader files are touched.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-tx-safety.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT
cd "$tmp_root"

cat > transaction_test.c <<'C_TEST'
#include "transaction.h"
#include "boot.h"
#include "logging.h"
#include <stdio.h>
#include <string.h>

static int archive_calls;
static int boot_calls;
static int iso_calls;

static int check(int ok, const char *what) {
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        return 1;
    }
    return 0;
}

void aweos_log(aweos_log_level_t level, const char *fmt, ...) {
    (void)level;
    (void)fmt;
}

int aweos_iso_validate(const char *path, aweos_iso_manifest_t *manifest) {
    (void)path;
    (void)manifest;
    iso_calls++;
    return AWEOS_OK;
}

int aweos_archive_directory(const char *src, const char *dst, aweos_archive_stats_t *stats) {
    (void)src;
    (void)dst;
    (void)stats;
    archive_calls++;
    return AWEOS_OK;
}

int aweos_boot_configure_limine(const char *target, aweos_boot_mode_t mode) {
    (void)target;
    (void)mode;
    boot_calls++;
    FILE *file = fopen("limine.conf", "w");
    if (file) {
        fputs("must not be written by an unsupported transaction\\n", file);
        fclose(file);
    }
    return AWEOS_OK;
}

int main(void) {
    aweos_tx_config_t config = {
        .install_mode = INSTALL_MODE_DUAL_BOOT,
        .boot_mode = BOOT_MODE_BIOS,
        .user_confirmed_destructive = false
    };
    snprintf(config.target_disk, sizeof(config.target_disk), "/dev/test-disk");
    snprintf(config.target_partition, sizeof(config.target_partition), "/dev/test-partition");
    snprintf(config.preserve_src, sizeof(config.preserve_src), "/home");
    snprintf(config.preserve_dst, sizeof(config.preserve_dst), "/backup/home");

    aweos_transaction_t tx;
    if (check(aweos_tx_init(&tx, &config) == AWEOS_OK, "transaction initialization")) return 1;
    if (check(aweos_tx_plan(&tx) == AWEOS_OK, "non-destructive plan")) return 1;
    if (check(aweos_tx_validate(&tx) == AWEOS_OK, "preflight validation")) return 1;
    if (check(tx.state == TX_STATE_VALIDATE, "validation state")) return 1;

    if (check(aweos_tx_prepare(&tx) == AWEOS_ERR_TRANSACTION, "unimplemented staging must fail closed")) return 1;
    if (check(tx.state == TX_STATE_FAILED, "failed state after unsupported staging")) return 1;
    if (check(tx.progress_percent == 25, "progress must not claim staging or deployment")) return 1;
    if (check(strstr(tx.error_msg, "not implemented") != NULL, "explicit unsupported-backend error")) return 1;

    if (check(aweos_tx_preserve(&tx) == AWEOS_ERR_TRANSACTION, "preservation cannot run after failed staging")) return 1;
    if (check(aweos_tx_execute(&tx) == AWEOS_ERR_TRANSACTION, "deployment cannot run after failed staging")) return 1;
    if (check(aweos_tx_configure_boot(&tx) == AWEOS_ERR_TRANSACTION, "boot configuration cannot run after failed staging")) return 1;
    if (check(aweos_tx_verify(&tx) == AWEOS_ERR_TRANSACTION, "verification cannot run after failed deployment")) return 1;
    if (check(aweos_tx_commit(&tx) == AWEOS_ERR_TRANSACTION, "commit cannot run after failed verification")) return 1;

    if (check(archive_calls == 0, "user data must not be copied before a real staging backend exists")) return 1;
    if (check(boot_calls == 0, "bootloader configuration must not be called")) return 1;
    if (check(iso_calls == 0, "empty ISO path must not invoke ISO validation")) return 1;
    if (check(tx.state == TX_STATE_FAILED, "failed transaction must remain failed")) return 1;
    if (check(tx.progress_percent < 100, "failed transaction must never report 100 percent")) return 1;

    config.install_mode = INSTALL_MODE_REPLACE_DISK;
    config.user_confirmed_destructive = false;
    if (check(aweos_tx_init(&tx, &config) == AWEOS_OK, "destructive transaction initialization")) return 1;
    if (check(aweos_tx_plan(&tx) == AWEOS_ERR_PERMISSION, "unconfirmed disk replacement must be rejected")) return 1;
    if (check(tx.state == TX_STATE_FAILED, "unconfirmed destructive plan must fail")) return 1;
    if (check(archive_calls == 0 && boot_calls == 0, "rejected destructive plan must have no side effects")) return 1;

    FILE *unexpected = fopen("limine.conf", "r");
    if (unexpected) {
        fclose(unexpected);
        return check(0, "unsupported transaction must not write limine.conf");
    }
    puts("PASS: transaction engine refuses unimplemented staging/deployment, never fakes 100% success, and performs no backup or bootloader side effects.");
    return 0;
}
C_TEST

cc -std=c11 -Wall -Wextra -Werror -I"$repo_root/src/core" \
    "$repo_root/src/core/transaction.c" transaction_test.c -o transaction_test
./transaction_test
