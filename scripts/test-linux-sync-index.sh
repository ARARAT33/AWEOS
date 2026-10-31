#!/usr/bin/env bash
# Regression test for the AWEOS Linux sync index-only replacement.
# Uses temporary repositories and never accesses the real /linux tree.
set -euo pipefail

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
repo="$root/aweos"
upstream="$root/linux-upstream"
mkdir -p "$repo" "$upstream"

git -C "$repo" init -q -b master
git -C "$repo" config user.name 'AWEOS sync test'
git -C "$repo" config user.email 'aweos-sync-test@example.invalid'
mkdir -p "$repo/linux/kernel" "$repo/src"
printf 'old kernel\n' > "$repo/linux/Makefile"
printf 'old config\n' > "$repo/linux/Kconfig"
printf 'old source\n' > "$repo/linux/kernel/old.c"
printf 'keep me\n' > "$repo/src/keep.txt"
printf 'linux/.build-cache\n' > "$repo/.gitignore"
git -C "$repo" add .
git -C "$repo" commit -qm 'initial AWEOS tree'

# Simulate ignored local data that a destructive rm -rf would erase.
printf 'preserve this ignored data\n' > "$repo/linux/.build-cache"

git -C "$upstream" init -q -b master
git -C "$upstream" config user.name 'Linux upstream test'
git -C "$upstream" config user.email 'linux-upstream-test@example.invalid'
mkdir -p "$upstream/kernel" "$upstream/arch"
printf 'new kernel\n' > "$upstream/Makefile"
printf 'new config\n' > "$upstream/Kconfig"
printf 'new source\n' > "$upstream/kernel/new.c"
printf 'arch tree\n' > "$upstream/arch/README"
git -C "$upstream" add .
git -C "$upstream" commit -qm 'upstream tree'

git -C "$repo" remote add linux-upstream "$upstream"
git -C "$repo" fetch -q --no-tags linux-upstream master

# Mirror the workflow: stage removal/addition in the index only. Never rewrite
# or delete the working tree, which can contain ignored or untracked leftovers.
git -C "$repo" rm -r --cached --quiet -- linux
git -C "$repo" read-tree --prefix=linux/ linux-upstream/master

index_tree="$(git -C "$repo" write-tree)"
staged_linux_tree="$(git -C "$repo" rev-parse "${index_tree}:linux")"
upstream_tree="$(git -C "$repo" rev-parse 'linux-upstream/master^{tree}')"
test "$staged_linux_tree" = "$upstream_tree"
git -C "$repo" cat-file -e "${staged_linux_tree}:Makefile"
git -C "$repo" cat-file -e "${staged_linux_tree}:Kconfig"
git -C "$repo" cat-file -e "${staged_linux_tree}:kernel"
git -C "$repo" cat-file -e "${staged_linux_tree}:arch"

# The ignored file and unrelated tracked file must remain untouched.
test "$(cat "$repo/linux/.build-cache")" = 'preserve this ignored data'
test "$(cat "$repo/src/keep.txt")" = 'keep me'

outside="$(git -C "$repo" diff --cached --name-only -- . ':(exclude)linux/**')"
test -z "$outside"

git -C "$repo" commit -qm 'sync /linux in index only'
test "$(git -C "$repo" rev-parse 'HEAD:linux')" = "$upstream_tree"
changed="$(git -C "$repo" diff-tree --no-commit-id --name-only -r HEAD)"
if printf '%s\n' "$changed" | grep -Ev '^linux/' >/dev/null; then
  echo "ERROR: test commit changes a path outside linux/" >&2
  printf '%s\n' "$changed" >&2
  exit 1
fi

echo "PASS: staged /linux exactly matches upstream; ignored data and outside files are preserved."
