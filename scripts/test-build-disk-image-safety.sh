#!/usr/bin/env bash
# Exercise disk-image publication with mocked partitioning and bootloader tools.
# No block devices are opened and no real partition table is written.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-disk-image-test.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT

build_dir="$tmp_root/build"
mock_bin="$tmp_root/bin"
mkdir -p "$build_dir" "$mock_bin"
printf 'AWEOS build directory v1\n' > "$build_dir/.aweos-build-dir"
printf 'rootfs fixture\n' > "$build_dir/rootfs.img"
printf 'previous valid disk image\n' > "$build_dir/AWEOS-x86_64-disk.img"

cat > "$mock_bin/dd" <<'MOCK_DD'
#!/usr/bin/env bash
set -euo pipefail
input=""
output=""
for arg in "$@"; do
    case "$arg" in
        if=*) input="${arg#if=}" ;;
        of=*) output="${arg#of=}" ;;
    esac
done
[[ -n "$input" && -n "$output" ]]
if [[ "$input" == "/dev/zero" ]]; then
    printf 'new disk image\n' > "$output"
else
    cat -- "$input" >> "$output"
fi
MOCK_DD

cat > "$mock_bin/sfdisk" <<'MOCK_SFDISK'
#!/usr/bin/env bash
set -euo pipefail
image="${1:?missing image path}"
cat >/dev/null
printf 'partition table\n' >> "$image"
MOCK_SFDISK

cat > "$mock_bin/limine" <<'MOCK_LIMINE'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "bios-install" && -s "${2:-}" ]]
if [[ "${FAIL_LIMINE:-0}" == "1" ]]; then
    exit 42
fi
printf 'Limine BIOS boot data\n' >> "$2"
MOCK_LIMINE
chmod 0755 "$mock_bin"/*

# A bootloader failure must leave the previous image byte-for-byte intact.
if PATH="$mock_bin:$PATH" FAIL_LIMINE=1 LIMINE_TOOL="$mock_bin/limine" \
    bash "$repo_root/scripts/build-disk-image.sh" "$build_dir"; then
    echo "ERROR: expected the simulated Limine installation failure." >&2
    exit 1
fi
test "$(cat "$build_dir/AWEOS-x86_64-disk.img")" = 'previous valid disk image'
test "$(cat "$build_dir/rootfs.img")" = 'rootfs fixture'
if compgen -G "$build_dir/.aweos-disk-image.*" >/dev/null; then
    echo "ERROR: failed disk-image build leaked its temporary workspace." >&2
    exit 1
fi
echo "PASS: failed disk-image build preserves the previous image and rootfs."

# A complete build publishes the new image only after Limine succeeds.
PATH="$mock_bin:$PATH" LIMINE_TOOL="$mock_bin/limine" \
    bash "$repo_root/scripts/build-disk-image.sh" "$build_dir"
grep -q '^new disk image$' "$build_dir/AWEOS-x86_64-disk.img"
grep -q '^partition table$' "$build_dir/AWEOS-x86_64-disk.img"
grep -q '^rootfs fixture$' "$build_dir/AWEOS-x86_64-disk.img"
grep -q '^Limine BIOS boot data$' "$build_dir/AWEOS-x86_64-disk.img"
test "$(cat "$build_dir/rootfs.img")" = 'rootfs fixture'
if compgen -G "$build_dir/.aweos-disk-image.*" >/dev/null; then
    echo "ERROR: successful disk-image build leaked its temporary workspace." >&2
    exit 1
fi
echo "PASS: disk image is atomically published after all build stages succeed."

# Never follow or replace a symlink destination.
sentinel="$tmp_root/user-data.txt"
printf 'keep user data\n' > "$sentinel"
mv "$build_dir/AWEOS-x86_64-disk.img" "$build_dir/real-disk-image"
ln -s "$sentinel" "$build_dir/AWEOS-x86_64-disk.img"
if PATH="$mock_bin:$PATH" LIMINE_TOOL="$mock_bin/limine" \
    bash "$repo_root/scripts/build-disk-image.sh" "$build_dir"; then
    echo "ERROR: disk-image builder accepted a symlink destination." >&2
    exit 1
fi
test -L "$build_dir/AWEOS-x86_64-disk.img"
test "$(cat "$sentinel")" = 'keep user data'
echo "PASS: symlink destinations are rejected without touching their targets."

# A symlinked rootfs input is not accepted as a trusted build artifact.
rm -f "$build_dir/AWEOS-x86_64-disk.img"
mv "$build_dir/rootfs.img" "$build_dir/rootfs.real"
ln -s "$build_dir/rootfs.real" "$build_dir/rootfs.img"
if PATH="$mock_bin:$PATH" LIMINE_TOOL="$mock_bin/limine" \
    bash "$repo_root/scripts/build-disk-image.sh" "$build_dir"; then
    echo "ERROR: disk-image builder accepted a symlink rootfs input." >&2
    exit 1
fi
test -L "$build_dir/rootfs.img"
echo "PASS: symlink rootfs inputs are rejected."

echo "PASS: AWEOS disk-image atomic publication regressions."
