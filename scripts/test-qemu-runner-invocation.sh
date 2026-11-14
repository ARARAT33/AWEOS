#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
MAKEFILE="$REPO_ROOT/Makefile"

# run-qemu-tests.sh is currently stored as mode 100644. The Makefile must
# invoke it through Bash rather than asking the kernel to execute it directly.
tracked_mode="$(git -C "$REPO_ROOT" ls-files --stage -- scripts/run-qemu-tests.sh | awk 'NR == 1 { print $1 }')"
if [ "$tracked_mode" != "100644" ]; then
    echo "ERROR: expected scripts/run-qemu-tests.sh to be tracked as mode 100644; got ${tracked_mode:-untracked}." >&2
    exit 1
fi

target_recipe="$(
    awk '
        /^test-qemu:[[:space:]]/ { in_target = 1; next }
        in_target && /^[^[:space:]]/ { exit }
        in_target { print }
    ' "$MAKEFILE"
)"

if ! grep -Eq '^[[:space:]]*@?[[:space:]]*bash[[:space:]]+\./scripts/run-qemu-tests\.sh[[:space:]]+\$\(BUILD_DIR\)[[:space:]]*$' <<< "$target_recipe"; then
    echo "ERROR: test-qemu must invoke the non-executable QEMU runner through Bash." >&2
    printf '%s\n' "$target_recipe" >&2
    exit 1
fi

echo "PASS: test-qemu invokes the mode-100644 QEMU runner through Bash."
