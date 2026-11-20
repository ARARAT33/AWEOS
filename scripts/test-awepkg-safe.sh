#!/usr/bin/env bash
# Ensure the legacy tar installer cannot write/delete arbitrary system paths.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="$repo_root/scripts/awepkg.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aweos-awepkg-safe.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT

mkdir -p "$tmp/db" "$tmp/empty-bin"
printf 'demo\n1.2\n1\n4 readme.txt\n' >"$tmp/db/demo.meta"
cat >"$tmp/db/base-system.meta" <<'META'
PKG_NAME=base-system
PKG_VER=0.1.0
PKG_DESC=AWEOS Base Userspace
META

AWEOS_AWEPKG_DB_DIR="$tmp/db" /bin/sh "$wrapper" list >"$tmp/list.out"
grep -Fq 'demo' "$tmp/list.out"
grep -Fq 'base-system' "$tmp/list.out"
AWEOS_AWEPKG_DB_DIR="$tmp/db" /bin/sh "$wrapper" info demo >"$tmp/info.out"
grep -Fq 'demo' "$tmp/info.out"

if AWEOS_AWEPKG_DB_DIR="$tmp/db" /bin/sh "$wrapper" info ../../etc/passwd >/dev/null 2>&1; then
    echo "ERROR: awepkg info accepted a path-traversal package name." >&2
    exit 1
fi

printf 'not a real package\n' >"$tmp/untrusted.awe"
if PATH="$tmp/empty-bin" AWEOS_INSTALL_ROOT="$tmp/root" /bin/sh "$wrapper" install "$tmp/untrusted.awe" >"$tmp/install.out" 2>&1; then
    echo "ERROR: legacy tar installation unexpectedly succeeded without aosin." >&2
    exit 1
fi
grep -Fq 'legacy tar installation is disabled' "$tmp/install.out"
[ ! -e "$tmp/root/etc/should-not-exist" ]

if PATH="$tmp/empty-bin" AWEOS_INSTALL_ROOT="$tmp/root" /bin/sh "$wrapper" remove demo >"$tmp/remove.out" 2>&1; then
    echo "ERROR: legacy removal unexpectedly succeeded without aosin." >&2
    exit 1
fi
grep -Fq 'legacy removal is disabled' "$tmp/remove.out"

mkdir -p "$tmp/fake-bin"
cat >"$tmp/fake-bin/aosin" <<'FAKE'
#!/bin/sh
printf '%s\n' "$@" >"$AWEOS_FAKE_AOSIN_ARGS"
FAKE
chmod +x "$tmp/fake-bin/aosin"
printf 'package bytes' >"$tmp/demo.asp"
PATH="$tmp/fake-bin:/usr/bin:/bin" AWEOS_FAKE_AOSIN_ARGS="$tmp/install.args" AWEOS_INSTALL_ROOT="$tmp/root" \
    /bin/sh "$wrapper" install "$tmp/demo.asp"
grep -Fxq 'install' "$tmp/install.args"
grep -Fxq "$tmp/demo.asp" "$tmp/install.args"
grep -Fxq "$tmp/root" "$tmp/install.args"

PATH="$tmp/fake-bin:/usr/bin:/bin" AWEOS_FAKE_AOSIN_ARGS="$tmp/remove.args" AWEOS_INSTALL_ROOT="$tmp/root" \
    /bin/sh "$wrapper" remove demo
grep -Fxq 'remove' "$tmp/remove.args"
grep -Fxq 'demo' "$tmp/remove.args"
grep -Fxq "$tmp/root" "$tmp/remove.args"

echo "PASS: awepkg rejects unsafe names, disables legacy tar writes/deletes, and delegates only to native aosin."
