#!/usr/bin/env bash
# Regression test for atomic disk-image assembly with mocked host utilities.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf -- "$tmp_root"' EXIT
work="$tmp_root/work"
bin="$tmp_root/bin"
mkdir -p "$work/build" "$bin"
cp "$repo_root/scripts/build-disk-image.sh" "$work/build-disk-image.sh"
printf 'rootfs payload\n' > "$work/build/rootfs.img"

cat > "$bin/dd" <<'MOCK_DD'
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
test -n "$output"
if [[ "$input" == "/dev/zero" ]]; then
    printf 'new disk image\n' > "$output"
else
    printf 'rootfs payload\n' >> "$output"
fi
MOCK_DD

cat > "$bin/sfdisk" <<'MOCK_SFDISK'
#!/usr/bin/env bash
set -euo pipefail
layout="$(cat)"
[[ "$layout" == *"2048,,L,*"* ]]
MOCK_SFDISK

cat > "$bin/limine" <<'MOCK_LIMINE'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "bios-install" && -s "${2:-}" ]] || exit 3
if [[ "${FAIL_BIOS_INSTALL:-0}" == "1" ]]; then
    exit 42
fi
printf 'BIOS boot data\n' >> "$2"
MOCK_LIMINE
chmod 0755 "$bin/dd" "$bin/sfdisk" "$bin/limine"

printf 'previous valid disk image\n' > "$work/build/AWEOS-x86_64-disk.img"

if (
    cd "$work"
    PATH="$bin:$PATH" LIMINE_TOOL="$bin/limine" FAIL_BIOS_INSTALL=1 \
        bash ./build-disk-image.sh "$work/build"
); then
    echo "ERROR: expected simulated BIOS-install failure." >&2
    exit 1
fi

test "$(cat "$work/build/AWEOS-x86_64-disk.img")" = 'previous valid disk image'
test "$(cat "$work/build/rootfs.img")" = 'rootfs payload'
if compgen -G "$work/build/.aweos-disk-work.*" >/dev/null; then
    echo "ERROR: temporary disk-image workspace leaked after failure." >&2
    exit 1
fi

(
    cd "$work"
    PATH="$bin:$PATH" LIMINE_TOOL="$bin/limine" \
        bash ./build-disk-image.sh "$work/build"
)

grep -q '^new disk image$' "$work/build/AWEOS-x86_64-disk.img"
grep -q '^rootfs payload$' "$work/build/AWEOS-x86_64-disk.img"
grep -q '^BIOS boot data$' "$work/build/AWEOS-x86_64-disk.img"
test "$(cat "$work/build/rootfs.img")" = 'rootfs payload'
if compgen -G "$work/build/.aweos-disk-work.*" >/dev/null; then
    echo "ERROR: temporary disk-image workspace leaked after success." >&2
    exit 1
fi

echo "PASS: disk-image assembly preserves the previous image and rootfs on failure and success."
