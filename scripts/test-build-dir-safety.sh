#!/usr/bin/env bash
# Regression tests for safe build-directory selection and cleanup.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$repo_root/scripts/lib/build-safety.sh"

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-build-safety.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT

fixture_repo="$tmp_root/repo"
mkdir -p "$fixture_repo/linux"
printf 'fixture kernel tree\n' > "$fixture_repo/linux/Makefile"

expect_rejected() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "ERROR: expected rejection: $label" >&2
        exit 1
    fi
    echo "PASS: rejected $label"
}

# A new empty build directory is marked before any build output is written.
empty_build="$fixture_repo/build"
mkdir -p "$empty_build"
resolved="$(aweos_prepare_build_dir "$empty_build" "$fixture_repo")"
test "$resolved" = "$empty_build"
test "$(cat "$empty_build/.aweos-build-dir")" = "$AWEOS_BUILD_DIR_MARKER_CONTENT"
echo "PASS: empty build directory receives an ownership marker."

# Non-empty unmarked directories are not silently adopted or cleaned.
user_data="$fixture_repo/user-data"
mkdir -p "$user_data"
printf 'keep me\n' > "$user_data/important.txt"
expect_rejected "non-empty unmarked directory" aweos_prepare_build_dir "$user_data" "$fixture_repo"
expect_rejected "cleanup of unmarked directory" aweos_clean_build_dir "$user_data" "$fixture_repo"
test "$(cat "$user_data/important.txt")" = 'keep me'
test ! -e "$user_data/.aweos-build-dir"
echo "PASS: unmarked user data remains untouched."

# Explicit adoption is required before an existing non-empty directory can
# become a build output directory.
adopted="$(AWEOS_ADOPT_BUILD_DIR=1 aweos_prepare_build_dir "$user_data" "$fixture_repo")"
test "$adopted" = "$user_data"
test "$(cat "$user_data/.aweos-build-dir")" = "$AWEOS_BUILD_DIR_MARKER_CONTENT"
echo "PASS: existing output is adopted only with explicit opt-in."

# Refuse root, repository root, ancestors containing the repository, and all
# locations inside the protected kernel source tree.
expect_rejected "filesystem root" aweos_prepare_build_dir / "$fixture_repo"
expect_rejected "repository root" aweos_prepare_build_dir "$fixture_repo" "$fixture_repo"
expect_rejected "ancestor containing the repository" aweos_prepare_build_dir "$tmp_root" "$fixture_repo"
expect_rejected "the read-only linux tree" aweos_prepare_build_dir "$fixture_repo/linux" "$fixture_repo"
expect_rejected "a nested path under linux" aweos_prepare_build_dir "$fixture_repo/linux/build/output" "$fixture_repo"

ln -s "$fixture_repo/linux" "$fixture_repo/linux-link"
expect_rejected "a symlink resolving into linux" aweos_prepare_build_dir "$fixture_repo/linux-link/output" "$fixture_repo"

# A symlink used as the build directory itself is rejected even when its
# target is otherwise a valid marked build directory.
symlink_target="$fixture_repo/marked-target"
mkdir -p "$symlink_target"
: > "$symlink_target/.aweos-build-dir"
printf '%s\n' "$AWEOS_BUILD_DIR_MARKER_CONTENT" > "$symlink_target/.aweos-build-dir"
ln -s "$symlink_target" "$fixture_repo/build-link"
expect_rejected "a symlink used as BUILD_DIR" aweos_prepare_build_dir "$fixture_repo/build-link" "$fixture_repo"

# Cleanup only removes a directory with the exact AWEOS marker.
aweos_clean_build_dir "$adopted" "$fixture_repo"
test ! -e "$user_data"
echo "PASS: marked AWEOS build directory can be explicitly cleaned."

# Exercise the real build entry points with a path under the actual /linux.
# They must reject it before creating anything there.
unsafe_repo_path="$repo_root/linux/.aweos-build-dir-safety-probe"
for script in \
    build-rootfs.sh \
    build-rootfs-gnome.sh \
    build-initramfs.sh \
    build-iso.sh \
    build-disk-image.sh \
    clean-build.sh; do
    if AWEOS_DESKTOP=ayui bash "$repo_root/scripts/$script" "$unsafe_repo_path" >/dev/null 2>&1; then
        echo "ERROR: $script accepted a build path under /linux." >&2
        exit 1
    fi
done
test ! -e "$unsafe_repo_path"
test ! -L "$unsafe_repo_path"
echo "PASS: all build entry points reject /linux before writing."

echo "PASS: AWEOS build-directory safety and cleanup regressions."
