#!/usr/bin/env bash
# AOSIN v2 package system regression: real payload packaging, streamed
# SHA-256 verification, tamper rejection, path-traversal rejection,
# legacy fail-closed behavior, and atomic staged extraction.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-aosin-test.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT
cd "$tmp_root"

flags="-std=c11 -Wall -Wextra -Werror -I$repo_root/src/core -I$repo_root/src/aosin"

cp "$repo_root/src/aosin/tests/test_aosin.c" aosin_test.c

cc $flags "$repo_root/src/core/netid.c" "$repo_root/src/core/logging.c" \
    "$repo_root/src/aosin/aosin_core.c" aosin_test.c -o aosin_test
./aosin_test

# The CLI tool must also compile cleanly against the same core.
cc $flags "$repo_root/src/core/netid.c" "$repo_root/src/core/logging.c" \
    "$repo_root/src/aosin/aosin_core.c" "$repo_root/src/aosin/main.c" -o aosin_cli
./aosin_cli verify build/app2.asp
