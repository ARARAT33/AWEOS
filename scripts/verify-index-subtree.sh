#!/usr/bin/env bash
# Compare a staged index subtree with the root tree of an upstream ref.
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "ERROR: usage: $0 <index-subtree-path> <upstream-ref>" >&2
    exit 2
fi

subtree_path="$1"
upstream_ref="$2"

if ! index_tree="$(git write-tree)"; then
    echo "ERROR: could not write the staged Git index tree." >&2
    exit 1
fi
if ! actual_tree="$(git rev-parse --verify "${index_tree}:${subtree_path}" 2>/dev/null)"; then
    echo "ERROR: staged index does not contain subtree: $subtree_path" >&2
    exit 1
fi
if ! expected_tree="$(git rev-parse --verify "${upstream_ref}^{tree}" 2>/dev/null)"; then
    echo "ERROR: upstream ref does not resolve to a tree: $upstream_ref" >&2
    exit 1
fi

if [[ "$actual_tree" != "$expected_tree" ]]; then
    echo "ERROR: staged index subtree differs from $upstream_ref." >&2
    echo "  path:     $subtree_path" >&2
    echo "  actual:   $actual_tree" >&2
    echo "  expected: $expected_tree" >&2
    exit 1
fi

echo "PASS: staged index subtree '$subtree_path' exactly matches $upstream_ref."
