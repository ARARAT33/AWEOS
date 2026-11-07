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
#include "installer.h"
#include "updater.h"
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
    iso_calls++;
    if (manifest) snprintf(manifest->version, sizeof(manifest->version), "9.9.9");
    return AWEOS_OK;
}

int aweos_archive_directory(const char *src, const char *dst, aweos_archive_stats_t *stats) {
    (void)src;
    (void)dst;
    (void)stats;
    archive_calls++;
    return AWEOS_OK;
}

static int detect_boot_mode_result = AWEOS_OK;
static aweos_boot_mode_t detected_boot_mode = BOOT_MODE_BIOS;
static int storage_discover_result = AWEOS_OK;
static int storage_disk_count;
static int storage_partition_count;
static int storage_discover_calls;

int aweos_detect_boot_mode(aweos_boot_mode_t *mode) {
    if (!mode) return AWEOS_ERR_INVALID_PARAM;
    if (detect_boot_mode_result != AWEOS_OK) return detect_boot_mode_result;
    *mode = detected_boot_mode;
    return AWEOS_OK;
}

int aweos_storage_discover(aweos_storage_info_t *info) {
    if (!info) return AWEOS_ERR_INVALID_PARAM;
    storage_discover_calls++;
    memset(info, 0, sizeof(*info));
    if (storage_discover_result != AWEOS_OK) return storage_discover_result;
    info->disk_count = storage_disk_count;
    if (storage_disk_count > 0) {
        snprintf(info->disks[0].dev_path, sizeof(info->disks[0].dev_path), "/dev/test-disk");
        info->disks[0].partition_count = storage_partition_count;
        if (storage_partition_count > 0) {
            snprintf(info->disks[0].partitions[0].dev_path,
                     sizeof(info->disks[0].partitions[0].dev_path), "/dev/test-partition");
        }
    }
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

    aweos_installer_state_t installer_probe = {0};
    detect_boot_mode_result = AWEOS_ERR_IO;
    storage_discover_calls = 0;
    if (check(aweos_installer_init(&installer_probe) == AWEOS_ERR_IO,
              "installer must reject firmware-detection failure")) return 1;
    if (check(storage_discover_calls == 0,
              "installer must not enumerate or select disks after firmware detection fails")) return 1;
    if (check(installer_probe.boot_mode == BOOT_MODE_UNKNOWN,
              "failed firmware detection must remain explicitly unknown")) return 1;

    detect_boot_mode_result = AWEOS_OK;
    detected_boot_mode = BOOT_MODE_UNKNOWN;
    if (check(aweos_installer_init(&installer_probe) == AWEOS_ERR_TRANSACTION,
              "installer must reject an unknown firmware mode")) return 1;

    detected_boot_mode = BOOT_MODE_UEFI;
    storage_discover_result = AWEOS_ERR_IO;
    if (check(aweos_installer_init(&installer_probe) == AWEOS_ERR_IO,
              "installer must reject storage-discovery errors")) return 1;

    storage_discover_result = AWEOS_OK;
    storage_disk_count = 0;
    if (check(aweos_installer_init(&installer_probe) == AWEOS_ERR_NOT_FOUND,
              "installer must reject an empty disk inventory instead of inventing a target")) return 1;

    storage_disk_count = 1;
    storage_partition_count = 0;
    if (check(aweos_installer_init(&installer_probe) == AWEOS_OK,
              "installer may display a real unpartitioned disk for a future partitioning flow")) return 1;
    if (check(installer_probe.boot_mode == BOOT_MODE_UEFI &&
              installer_probe.selected_disk_idx == -1 &&
              installer_probe.selected_part_idx == -1 &&
              !installer_probe.confirmed_destructive,
              "installer must not auto-select any discovered disk or partition")) return 1;
    if (check(aweos_installer_run_cli(&installer_probe) == AWEOS_ERR_INVALID_PARAM,
              "installer must refuse to run before an explicit target is selected")) return 1;
    if (check(installer_probe.tx.status_msg[0] == '\0',
              "missing target selection must be rejected before a transaction is initialized")) return 1;

    detected_boot_mode = BOOT_MODE_BIOS;
    storage_disk_count = 1;
    storage_partition_count = 1;
    if (check(aweos_installer_init(&installer_probe) == AWEOS_OK,
              "installer must rediscover a real disk without selecting it")) return 1;
    if (check(aweos_installer_select_target(&installer_probe, -1, 0) == AWEOS_ERR_INVALID_PARAM &&
              aweos_installer_select_target(&installer_probe, 1, 0) == AWEOS_ERR_INVALID_PARAM &&
              aweos_installer_select_target(&installer_probe, 0, -1) == AWEOS_ERR_INVALID_PARAM &&
              aweos_installer_select_target(&installer_probe, 0, 1) == AWEOS_ERR_INVALID_PARAM,
              "installer must reject negative and out-of-range disk/partition selections")) return 1;
    if (check(installer_probe.selected_disk_idx == -1 && installer_probe.selected_part_idx == -1,
              "rejected target selections must not mutate the current selection")) return 1;
    if (check(aweos_installer_select_target(&installer_probe, 0, 0) == AWEOS_OK,
              "dual-boot target selection must require and accept an explicit valid disk and partition")) return 1;
    if (check(installer_probe.selected_disk_idx == 0 && installer_probe.selected_part_idx == 0,
              "explicit target selection must be recorded")) return 1;
    if (check(aweos_installer_run_cli(&installer_probe) == AWEOS_ERR_TRANSACTION,
              "selected installer must still stop when the staging backend is unavailable")) return 1;
    if (check(installer_probe.tx.state == TX_STATE_FAILED,
              "selected installer must expose the fail-closed transaction state")) return 1;

    installer_probe.mode = INSTALL_MODE_REPLACE_DISK;
    if (check(aweos_installer_select_target(&installer_probe, 0, 0) == AWEOS_ERR_INVALID_PARAM,
              "full-disk replacement must not carry a partition selection")) return 1;
    if (check(aweos_installer_select_target(&installer_probe, 0, -1) == AWEOS_OK,
              "full-disk replacement may explicitly select a disk without selecting a partition")) return 1;
    if (check(!installer_probe.confirmed_destructive,
              "selecting a disk must never imply destructive confirmation")) return 1;
    if (check(aweos_installer_run_cli(&installer_probe) == AWEOS_ERR_PERMISSION,
              "full-disk replacement must remain blocked without explicit destructive confirmation")) return 1;
    if (check(installer_probe.tx.state == TX_STATE_FAILED,
              "unconfirmed full-disk replacement must fail before staging")) return 1;
    if (check(archive_calls == 0 && boot_calls == 0,
              "installer target selection tests must never archive data or write boot files")) return 1;

    aweos_updater_state_t updater;
    if (check(aweos_updater_init(&updater, "/tmp/fake-aweos.iso") == AWEOS_OK,
              "updater preflight initialization with a test ISO stub")) return 1;
    if (check(updater.ready_to_update, "updater preflight state")) return 1;
    if (check(aweos_updater_run(&updater) == AWEOS_ERR_TRANSACTION,
              "updater must stop when staging backend is unavailable")) return 1;

    if (check(archive_calls == 0, "installer/updater must not archive or overwrite user data before staging exists")) return 1;
    if (check(boot_calls == 0, "installer/updater must not write bootloader files")) return 1;
    if (check(iso_calls == 2, "updater should validate the candidate ISO during preflight and transaction validation")) return 1;

    FILE *unexpected = fopen("limine.conf", "r");
    if (unexpected) {
        fclose(unexpected);
        return check(0, "unsupported transaction must not write limine.conf");
    }
    puts("PASS: transaction engine refuses unimplemented staging/deployment, never fakes 100% success, and performs no backup or bootloader side effects.");
    return 0;
}
C_TEST

cc -std=c11 -Wall -Wextra -Werror \
    -I"$repo_root/src/core" -I"$repo_root/src/installer" -I"$repo_root/src/updater" \
    "$repo_root/src/core/transaction.c" \
    "$repo_root/src/installer/installer.c" \
    "$repo_root/src/updater/updater.c" \
    transaction_test.c -o transaction_test
./transaction_test
