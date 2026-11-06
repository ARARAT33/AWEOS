#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-aosin-fail-closed.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT
cc -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror -fsanitize=address,undefined -fno-omit-frame-pointer \
 -I"$repo_root/src/aosin" -I"$repo_root/src/core" "$repo_root/src/aosin/aosin_core.c" "$repo_root/src/aosin/tests/test_aosin.c" -o "$tmp_root/test_aosin"
ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=1:halt_on_error=1}" UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1}" "$tmp_root/test_aosin" "$tmp_root"
echo "PASS: AOSIN C API regression (ASan/UBSan)."
