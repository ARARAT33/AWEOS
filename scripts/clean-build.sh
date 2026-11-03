#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
source "$SCRIPT_DIR/lib/build-safety.sh"

BUILD_DIR="${1:-$REPO_ROOT/build}"
if [[ ! -e "$BUILD_DIR" && ! -L "$BUILD_DIR" ]]; then
    echo "No AWEOS build directory exists at $BUILD_DIR."
    exit 0
fi
aweos_clean_build_dir "$BUILD_DIR" "$REPO_ROOT"
