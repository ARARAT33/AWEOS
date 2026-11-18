#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT="$SCRIPT_DIR/awepkg.sh"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/awepkg-fail-closed.XXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

DB_DIR="$TEMP_ROOT/db"
mkdir -p "$DB_DIR" "$TEMP_ROOT/archive/root" "$TEMP_ROOT/system"
cat > "$DB_DIR/demo.meta" <<'META'
PKG_NAME=demo
PKG_VER=1.2.3
PKG_DESC=Read-only fixture
META
printf 'keep me\n' > "$TEMP_ROOT/system/keep.txt"
printf 'must not be installed\n' > "$TEMP_ROOT/archive/root/payload.txt"
cat > "$TEMP_ROOT/archive/manifest.meta" <<'META'
PKG_NAME=demo
PKG_VER=9.9.9
META
tar -czf "$TEMP_ROOT/demo.awe" -C "$TEMP_ROOT/archive" .

list_output="$(AWEOS_AWEPKG_DB_DIR="$DB_DIR" sh "$SCRIPT" list)"
grep -Fq 'demo' <<<"$list_output"
info_output="$(AWEOS_AWEPKG_DB_DIR="$DB_DIR" sh "$SCRIPT" info demo)"
grep -Fq 'PKG_VER=1.2.3' <<<"$info_output"

if AWEOS_AWEPKG_DB_DIR="$DB_DIR" sh "$SCRIPT" info ../system/keep >"$TEMP_ROOT/path.out" 2>&1; then
    echo "ERROR: package info accepted a path-traversal package name." >&2
    exit 1
fi
grep -Fq 'invalid package name' "$TEMP_ROOT/path.out"

if AWEOS_AWEPKG_DB_DIR="$DB_DIR" sh "$SCRIPT" install "$TEMP_ROOT/demo.awe" >"$TEMP_ROOT/install.out" 2>&1; then
    echo "ERROR: package install reported success without a trusted installer." >&2
    exit 1
fi
grep -Fq 'no files were extracted or copied' "$TEMP_ROOT/install.out"
test ! -e "$TEMP_ROOT/system/payload.txt"
test ! -e /payload.txt

if AWEOS_AWEPKG_DB_DIR="$DB_DIR" sh "$SCRIPT" remove demo >"$TEMP_ROOT/remove.out" 2>&1; then
    echo "ERROR: package removal reported success without an ownership/rollback backend." >&2
    exit 1
fi
grep -Fq 'no files or metadata were deleted' "$TEMP_ROOT/remove.out"
test -f "$DB_DIR/demo.meta"
test "$(cat "$TEMP_ROOT/system/keep.txt")" = "keep me"

MISSING_DB="$TEMP_ROOT/missing-db"
if AWEOS_AWEPKG_DB_DIR="$MISSING_DB" sh "$SCRIPT" install "$TEMP_ROOT/demo.awe" >"$TEMP_ROOT/missing.out" 2>&1; then
    echo "ERROR: install unexpectedly succeeded with a missing package database." >&2
    exit 1
fi
test ! -e "$MISSING_DB"

echo "PASS: awepkg read-only queries work; install/remove and path traversal fail closed without filesystem mutation."
