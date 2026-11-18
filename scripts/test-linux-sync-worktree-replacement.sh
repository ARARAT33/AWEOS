#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aweos-linux-replace-test.XXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

REPO="$TEMP_ROOT/repo"
UPSTREAM="$TEMP_ROOT/upstream"
mkdir -p "$REPO" "$UPSTREAM"
git -C "$REPO" init -q
git -C "$REPO" config user.name "AWEOS Test"
git -C "$REPO" config user.email "aweos-test@example.invalid"

mkdir -p "$REPO/linux/kernel" "$REPO/linux/arch"
printf 'VERSION = old\n' > "$REPO/linux/Makefile"
printf 'mainmenu "old fixture"\n' > "$REPO/linux/Kconfig"
printf 'old kernel fixture\n' > "$REPO/linux/kernel/old.c"
printf 'ARCH = old\n' > "$REPO/linux/arch/Makefile"
printf '*.cache\n' > "$REPO/linux/.gitignore"
printf 'outside sentinel\n' > "$REPO/README.md"
git -C "$REPO" add linux README.md
git -C "$REPO" commit -qm "Create old AWEOS fixture"

git -C "$UPSTREAM" init -q
git -C "$UPSTREAM" config user.name "Linux Upstream Fixture"
git -C "$UPSTREAM" config user.email "upstream@example.invalid"
mkdir -p "$UPSTREAM/kernel" "$UPSTREAM/arch"
printf 'VERSION = upstream\n' > "$UPSTREAM/Makefile"
printf 'mainmenu "upstream fixture"\n' > "$UPSTREAM/Kconfig"
printf 'new kernel fixture\n' > "$UPSTREAM/kernel/new.c"
printf 'ARCH = upstream\n' > "$UPSTREAM/arch/Makefile"
git -C "$UPSTREAM" add .
git -C "$UPSTREAM" commit -qm "Create upstream fixture"
git -C "$REPO" fetch --no-tags "$UPSTREAM" HEAD:refs/remotes/linux-upstream/master

# An ignored file models generated kernel output that survives git rm.
printf 'generated cache\n' > "$REPO/linux/kernel/generated.cache"
(
    cd "$REPO"
    AWEOS_ALLOW_LINUX_REPLACEMENT=1 bash "$REPO_ROOT/scripts/replace-linux-worktree.sh" linux-upstream/master
)

test -f "$REPO/linux/kernel/new.c"
test ! -e "$REPO/linux/kernel/old.c"
test ! -e "$REPO/linux/kernel/generated.cache"
test "$(cat "$REPO/README.md")" = "outside sentinel"
(
    cd "$REPO"
    bash "$REPO_ROOT/scripts/verify-index-subtree.sh" linux linux-upstream/master
)
outside="$(git -C "$REPO" diff --cached --name-only | awk '$0 != "linux" && $0 !~ /^linux\//')"
test -z "$outside"

# The explicit opt-in is mandatory and must fail before touching the tree.
git -C "$REPO" reset --hard -q HEAD
if (
    cd "$REPO"
    env -u AWEOS_ALLOW_LINUX_REPLACEMENT bash "$REPO_ROOT/scripts/replace-linux-worktree.sh" linux-upstream/master
) >"$TEMP_ROOT/guard.out" 2>&1; then
    echo "ERROR: replacement ran without its explicit opt-in." >&2
    exit 1
fi
grep -Fq 'refusing /linux replacement' "$TEMP_ROOT/guard.out"
test -f "$REPO/linux/kernel/old.c"

# Dirty worktrees must also fail before deleting or cleaning anything.
printf 'local user change\n' >> "$REPO/README.md"
if (
    cd "$REPO"
    AWEOS_ALLOW_LINUX_REPLACEMENT=1 bash "$REPO_ROOT/scripts/replace-linux-worktree.sh" linux-upstream/master
) >"$TEMP_ROOT/dirty.out" 2>&1; then
    echo "ERROR: replacement accepted a dirty worktree." >&2
    exit 1
fi
grep -Fq 'working tree contains changes' "$TEMP_ROOT/dirty.out"
test -f "$REPO/linux/kernel/old.c"

echo "PASS: Linux sync removes only ignored /linux leftovers, verifies the upstream tree, and fails closed otherwise."
