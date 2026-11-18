#!/usr/bin/env bash
# Replace only the tracked /linux worktree with an upstream root tree.
# This is intended for the disposable GitHub Actions sync checkout.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "ERROR: usage: $0 <upstream-ref>" >&2
    exit 2
fi

if [[ "${AWEOS_ALLOW_LINUX_REPLACEMENT:-}" != "1" ]]; then
    echo "ERROR: refusing /linux replacement without AWEOS_ALLOW_LINUX_REPLACEMENT=1." >&2
    exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
upstream_ref="$1"

if [[ -L linux || ! -d linux ]]; then
    echo "ERROR: /linux must be a real directory; refusing to replace it." >&2
    exit 1
fi
for required in linux/Makefile linux/Kconfig linux/kernel linux/arch; do
    [[ -e "$required" ]] || {
        echo "ERROR: expected tracked kernel path is missing: $required" >&2
        exit 1
    }
done
if ! git rev-parse --verify "${upstream_ref}^{tree}" >/dev/null 2>&1; then
    echo "ERROR: upstream ref does not resolve to a tree: $upstream_ref" >&2
    exit 1
fi

# Never discard tracked, staged, or ordinary untracked changes. Ignored build
# leftovers are handled separately and only inside the exact /linux subtree.
if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
    echo "ERROR: working tree contains changes; refusing to replace /linux." >&2
    git status --short
    exit 1
fi

if ! git ls-files --error-unmatch linux/Makefile >/dev/null 2>&1; then
    echo "ERROR: /linux/Makefile is not tracked; refusing to replace the subtree." >&2
    exit 1
fi

git rm -r --quiet -- linux

# git rm removes indexed files, but ignored files can keep the directory alive.
# Clean only ignored/untracked leftovers under /linux; never use a repository-
# wide clean and never force-remove nested repositories.
if [[ -L linux ]]; then
    echo "ERROR: /linux became a symlink during replacement; refusing cleanup." >&2
    exit 1
fi
if [[ -d linux ]]; then
    git clean -fdx -- linux/
    if [[ -d linux ]]; then
        rmdir -- linux || {
            echo "ERROR: /linux still contains files after scoped cleanup; refusing to continue." >&2
            find linux -mindepth 1 -maxdepth 2 -print | head -n 40 >&2 || true
            exit 1
        }
    fi
fi
if [[ -e linux || -L linux ]]; then
    echo "ERROR: /linux path remains after scoped cleanup; refusing to overlay upstream." >&2
    exit 1
fi

git read-tree --prefix=linux/ -u "$upstream_ref"
bash scripts/verify-index-subtree.sh linux "$upstream_ref"

for required in linux/Makefile linux/Kconfig linux/kernel linux/arch; do
    [[ -e "$required" ]] || {
        echo "ERROR: upstream replacement is missing required path: $required" >&2
        exit 1
    }
done

outside="$(git diff --cached --name-only | awk '$0 != "linux" && $0 !~ /^linux\//')"
if [[ -n "$outside" ]]; then
    echo "ERROR: replacement staged changes outside /linux:" >&2
    printf '%s\n' "$outside" >&2
    exit 1
fi

echo "SAFE: /linux worktree replaced and staged subtree exactly matches $upstream_ref."
