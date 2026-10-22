#!/usr/bin/env bash
# Regression test for replacing the vendored /linux tree when ignored build
# leftovers remain on disk after git rm removes tracked files.
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git init --quiet --bare "$tmp/linux-upstream.git"
git init --quiet "$tmp/upstream-work"
git -C "$tmp/upstream-work" config user.name "AWEOS test"
git -C "$tmp/upstream-work" config user.email "aweos-test@example.invalid"
mkdir -p "$tmp/upstream-work/arch" "$tmp/upstream-work/kernel"
printf 'upstream makefile\n' > "$tmp/upstream-work/Makefile"
printf 'upstream kconfig\n' > "$tmp/upstream-work/Kconfig"
printf 'upstream kernel\n' > "$tmp/upstream-work/kernel/core.c"
printf 'upstream arch\n' > "$tmp/upstream-work/arch/core.c"
git -C "$tmp/upstream-work" add .
git -C "$tmp/upstream-work" commit --quiet -m "upstream fixture"
git -C "$tmp/upstream-work" branch -M master
git -C "$tmp/upstream-work" remote add origin "$tmp/linux-upstream.git"
git -C "$tmp/upstream-work" push --quiet origin master

git init --quiet "$tmp/aweos"
git -C "$tmp/aweos" config user.name "AWEOS test"
git -C "$tmp/aweos" config user.email "aweos-test@example.invalid"
mkdir -p "$tmp/aweos/linux/arch" "$tmp/aweos/linux/kernel"
printf 'old makefile\n' > "$tmp/aweos/linux/Makefile"
printf 'old kconfig\n' > "$tmp/aweos/linux/Kconfig"
printf 'old kernel\n' > "$tmp/aweos/linux/kernel/core.c"
printf 'old arch\n' > "$tmp/aweos/linux/arch/core.c"
printf '/.generated/\n' > "$tmp/aweos/linux/.gitignore"
printf 'must remain untouched\n' > "$tmp/aweos/README.md"
git -C "$tmp/aweos" add .
git -C "$tmp/aweos" commit --quiet -m "AWEOS fixture"
git -C "$tmp/aweos" remote add linux-upstream "$tmp/linux-upstream.git"
git -C "$tmp/aweos" fetch --quiet --no-tags linux-upstream master

# This file is ignored and therefore does not make git status dirty, but it
# leaves the directory on disk after tracked files are removed.
mkdir -p "$tmp/aweos/linux/.generated"
printf 'stale generated content\n' > "$tmp/aweos/linux/.generated/cache"
test -z "$(git -C "$tmp/aweos" status --porcelain)"

git -C "$tmp/aweos" rm -r --quiet -- linux
rm -rf -- "$tmp/aweos/linux"
test ! -e "$tmp/aweos/linux"
git -C "$tmp/aweos" read-tree --prefix=linux/ -u linux-upstream/master

expected_tree="$(git -C "$tmp/aweos" rev-parse linux-upstream/master^{tree})"
actual_tree="$(git -C "$tmp/aweos" rev-parse :linux)"
test "$actual_tree" = "$expected_tree"
test -f "$tmp/aweos/linux/Makefile"
test -f "$tmp/aweos/linux/Kconfig"
test -d "$tmp/aweos/linux/kernel"
test -d "$tmp/aweos/linux/arch"
test "$(git -C "$tmp/aweos" show HEAD:README.md)" = "must remain untouched"

outside="$(git -C "$tmp/aweos" diff --cached --name-only -- . ':(exclude)linux/**')"
test -z "$outside"
echo "PASS: ignored leftovers removed; staged /linux tree exactly matches upstream; files outside /linux unchanged."
