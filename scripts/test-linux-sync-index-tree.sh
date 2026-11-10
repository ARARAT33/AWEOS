#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aweos-index-subtree-test.XXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

REPO="$TEMP_ROOT/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.name "AWEOS Test"
git -C "$REPO" config user.email "aweos-test@example.invalid"

mkdir -p "$REPO/linux/kernel" "$REPO/linux/arch"
printf 'VERSION = test\n' > "$REPO/linux/Makefile"
printf 'mainmenu "fixture"\n' > "$REPO/linux/Kconfig"
printf 'kernel fixture\n' > "$REPO/linux/kernel/fixture.c"
printf 'ARCH = x86\n' > "$REPO/linux/arch/Makefile"
git -C "$REPO" add linux
git -C "$REPO" commit -qm "Create upstream fixture tree"

upstream_tree="$(git -C "$REPO" rev-parse HEAD:linux)"
upstream_commit="$(printf 'upstream fixture root tree\n' | git -C "$REPO" commit-tree "$upstream_tree")"
git -C "$REPO" update-ref refs/remotes/linux-upstream/master "$upstream_commit"

# AWEOS files outside /linux may coexist in the index; only the linux subtree
# is compared with the upstream repository's root tree.
printf 'AWEOS\n' > "$REPO/README.md"
git -C "$REPO" add README.md
(
    cd "$REPO"
    bash "$REPO_ROOT/scripts/verify-index-subtree.sh" linux linux-upstream/master
)

# A staged kernel change must be rejected.
printf 'local change\n' >> "$REPO/linux/Makefile"
git -C "$REPO" add linux/Makefile
if (
    cd "$REPO"
    bash "$REPO_ROOT/scripts/verify-index-subtree.sh" linux linux-upstream/master
) >"$TEMP_ROOT/mismatch.out" 2>&1; then
    echo "ERROR: index subtree verifier accepted a mismatched /linux tree." >&2
    exit 1
fi
grep -Fq 'staged index subtree differs' "$TEMP_ROOT/mismatch.out"

echo "PASS: Linux index subtree verification accepts exact trees and rejects mismatches."
