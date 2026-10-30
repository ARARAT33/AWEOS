#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT

"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -D_GNU_SOURCE \
    -I "$REPO_ROOT/src/core" \
    "$REPO_ROOT/src/core/storage.c" \
    "$REPO_ROOT/src/core/logging.c" \
    "$SCRIPT_DIR/test_boot_mode.c" \
    -o "$TMP_DIR/test_boot_mode"

"$TMP_DIR/test_boot_mode"
