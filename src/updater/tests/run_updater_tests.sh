#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT

CC_BIN="${CC:-cc}"
command -v "$CC_BIN" >/dev/null 2>&1 || {
    echo "ERROR: C compiler '$CC_BIN' is required for updater regression tests" >&2
    exit 1
}

"$CC_BIN" \
    -std=c11 -Wall -Wextra -Werror \
    -fsanitize=address,undefined -fno-omit-frame-pointer \
    -I "$REPO_ROOT/src/core" \
    -I "$REPO_ROOT/src/updater" \
    "$REPO_ROOT/src/updater/updater.c" \
    "$REPO_ROOT/src/core/logging.c" \
    "$SCRIPT_DIR/test_updater.c" \
    -o "$TMP_DIR/test_updater"

ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=1:halt_on_error=1}" \
UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1}" \
    "$TMP_DIR/test_updater"
