#!/usr/bin/env bash
# Exercise Linux block-device discovery using a fixture, never real block devices.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-storage-test.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT
fixture="${tmp_root}/partitions"
cd "$tmp_root"

cat > storage_test.c <<'C_TEST'
#include "storage.h"
#include "logging.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

void aweos_log(aweos_log_level_t level, const char *fmt, ...) {
    (void)level;
    (void)fmt;
}

static void write_fixture(const char *path, const char *contents) {
    FILE *file = fopen(path, "w");
    assert(file != NULL);
    assert(fputs(contents, file) >= 0);
    assert(fclose(file) == 0);
}

int main(int argc, char **argv) {
    assert(argc == 2);
    const char *fixture = argv[1];
    aweos_storage_info_t info;

    /* Missing inventory is an error, not a synthetic /dev/vda. */
    assert(aweos_storage_discover(&info) == AWEOS_ERR_IO);
    assert(info.disk_count == 0);

    write_fixture(fixture,
        "major minor  #blocks  name\n"
        "7 0 4096 loop0\n"
        "11 0 2048 sr0\n");
    assert(aweos_storage_discover(&info) == AWEOS_ERR_NOT_FOUND);
    assert(info.disk_count == 0);

    write_fixture(fixture,
        "major minor  #blocks  name\n"
        "259 0 976762584 nvme1n1\n"
        "259 1 512000 nvme1n1p1\n"
        "259 2 976250000 nvme1n1p2\n"
        "8 16 1953525168 sdb\n"
        "8 17 1953520000 sdb1\n"
        "8 18 1000 sdb2\n"
        "179 0 62521344 mmcblk0\n"
        "179 1 524288 mmcblk0p1\n");

    assert(aweos_storage_discover(&info) == AWEOS_OK);
    assert(info.disk_count == 3);

    assert(strcmp(info.disks[0].dev_path, "/dev/nvme1n1") == 0);
    assert(info.disks[0].partition_count == 2);
    assert(strcmp(info.disks[0].partitions[0].dev_path, "/dev/nvme1n1p1") == 0);
    assert(strcmp(info.disks[0].partitions[1].dev_path, "/dev/nvme1n1p2") == 0);
    assert(info.disks[0].size_bytes == UINT64_C(976762584) * 1024U);

    assert(strcmp(info.disks[1].dev_path, "/dev/sdb") == 0);
    assert(info.disks[1].partition_count == 2);
    assert(strcmp(info.disks[1].partitions[0].dev_path, "/dev/sdb1") == 0);
    assert(strcmp(info.disks[1].partitions[1].dev_path, "/dev/sdb2") == 0);

    assert(strcmp(info.disks[2].dev_path, "/dev/mmcblk0") == 0);
    assert(info.disks[2].partition_count == 1);
    assert(strcmp(info.disks[2].partitions[0].dev_path, "/dev/mmcblk0p1") == 0);

    /* /proc/partitions does not prove filesystem type, UUID, free space or GPT.
       Keep those fields unknown instead of filling in plausible-looking guesses. */
    assert(info.disks[0].is_gpt == false);
    assert(info.disks[0].partitions[0].fstype[0] == '\0');
    assert(info.disks[0].partitions[0].uuid[0] == '\0');
    assert(info.disks[0].partitions[0].free_bytes == 0);

    puts("PASS: storage discovery reports only observed block devices and never fabricates disks, partitions, filesystems, UUIDs, or free space.");
    return 0;
}
C_TEST

cc -std=c11 -Wall -Wextra -Werror \
    -I"$repo_root/src/core" \
    "-DAWEOS_PROC_PARTITIONS_PATH=\"$fixture\"" \
    "$repo_root/src/core/storage.c" storage_test.c -o storage_test
./storage_test "$fixture"
