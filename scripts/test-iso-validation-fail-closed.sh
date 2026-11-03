#!/usr/bin/env bash
# Ensure an untrusted file cannot be accepted as an update ISO by size alone.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-iso-verify.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT

cat > "$tmp_root/test_iso_verify.c" <<'C_TEST'
#include "iso_verify.h"
#include "logging.h"
#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

void aweos_log(aweos_log_level_t level, const char *fmt, ...) {
    (void)level;
    (void)fmt;
}

static void assert_untrusted(const char *path, int expected_result, uint64_t expected_size) {
    aweos_iso_manifest_t manifest;
    memset(&manifest, 0xA5, sizeof(manifest));

    int result = aweos_iso_validate(path, &manifest);
    assert(result == expected_result);
    assert(!manifest.is_valid);
    assert(manifest.size_bytes == expected_size);
    assert(manifest.version[0] == '\0');
    assert(manifest.arch[0] == '\0');
    assert(manifest.build_id[0] == '\0');
    assert(manifest.checksum_sha256[0] == '\0');
}

int main(int argc, char **argv) {
    assert(argc == 4);
    assert_untrusted(argv[1], AWEOS_ERR_VERIFY, 2U * 1024U * 1024U);
    assert_untrusted(argv[2], AWEOS_ERR_VERIFY, 4U);
    assert_untrusted(argv[3], AWEOS_ERR_IO, 0U);
    assert(aweos_iso_validate(NULL, &(aweos_iso_manifest_t){0}) == AWEOS_ERR_INVALID_PARAM);
    puts("PASS: ISO candidates are never marked valid without a trusted expected SHA-256; symlinks and undersized files are rejected.");
    return 0;
}
C_TEST

cc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-omit-frame-pointer \
    -I"$repo_root/src/core" \
    "$repo_root/src/core/iso_verify.c" \
    "$tmp_root/test_iso_verify.c" \
    -o "$tmp_root/test_iso_verify"

dd if=/dev/zero of="$tmp_root/large.iso" bs=1M count=2 status=none
printf 'tiny' > "$tmp_root/small.iso"
ln -s large.iso "$tmp_root/symlink.iso"

ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=1:halt_on_error=1}" \
UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1}" \
    "$tmp_root/test_iso_verify" \
    "$tmp_root/large.iso" "$tmp_root/small.iso" "$tmp_root/symlink.iso"

echo "PASS: ISO verification fails closed for size-only candidates and symlink paths."
