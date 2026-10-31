#!/usr/bin/env bash
# Regression test for safe, atomic ISO assembly.
# Runs the real build script with mocked xorriso/Limine and temporary inputs.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf -- "$tmp_root"' EXIT
work="$tmp_root/work"
bin="$tmp_root/bin"

mkdir -p "$work/scripts" "$work/Bootloader/x86_64" "$work/build/linux-x86_64/arch/x86/boot" "$bin"
cp "$repo_root/scripts/build-iso.sh" "$work/scripts/build-iso.sh"

for file in \
    limine-bios.sys \
    limine-bios-cd.bin \
    limine-uefi-cd.bin \
    BOOTX64.EFI \
    limine.conf; do
    case "$file" in
        limine-bios.sys) dest="$work/Bootloader/x86_64/$file" ;;
        limine-bios-cd.bin) dest="$work/Bootloader/x86_64/$file" ;;
        limine-uefi-cd.bin) dest="$work/Bootloader/x86_64/$file" ;;
        BOOTX64.EFI) dest="$work/Bootloader/x86_64/$file" ;;
        limine.conf) dest="$work/Bootloader/x86_64/$file" ;;
    esac
    printf 'mock %s\n' "$file" > "$dest"
done
cat > "$work/Bootloader/x86_64/limine-debug.conf" <<'DEBUG_CONFIG'
serial: yes
verbose: yes
cmdline: earlycon=uart8250,io,0x3f8,115200 loglevel=7 ignore_loglevel
DEBUG_CONFIG

printf 'kernel\n' > "$work/build/linux-x86_64/arch/x86/boot/bzImage"
printf 'initramfs\n' > "$work/build/aweos-initramfs.cpio.gz"
printf 'rootfs\n' > "$work/build/rootfs.img"

cat > "$bin/xorriso" <<'MOCK_XORRISO'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (($#)); do
    if [[ "$1" == "-o" ]]; then
        output="$2"
        shift 2
    else
        shift
    fi
done
test -n "$output"
if [[ "${EXPECT_DEBUG_CONFIG:-0}" == "1" ]]; then
    grep -q '^serial: yes$' limine.conf
    grep -q 'earlycon=uart8250' limine.conf
fi
printf 'mock ISO image\n' > "$output"
MOCK_XORRISO

cat > "$bin/limine" <<'MOCK_LIMINE'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "bios-install" && -s "${2:-}" ]] || exit 3
if [[ "${FAIL_BIOS_INSTALL:-0}" == "1" ]]; then
    exit 42
fi
printf 'BIOS boot data\n' >> "$2"
MOCK_LIMINE
chmod +x "$bin/xorriso" "$bin/limine"

# Existing staging data must never be recursively deleted by the build script.
mkdir -p "$work/build/iso"
printf 'user staging data\n' > "$work/build/iso/keep.txt"
printf 'previous valid ISO\n' > "$work/build/AWEOS-x86_64.iso"

if (
    cd "$work"
    PATH="$bin:$PATH" LIMINE_TOOL="$bin/limine" FAIL_BIOS_INSTALL=1 \
        bash ./scripts/build-iso.sh "$work/build"
); then
    echo "ERROR: expected the simulated BIOS-install failure" >&2
    exit 1
fi

test "$(cat "$work/build/AWEOS-x86_64.iso")" = 'previous valid ISO'
test "$(cat "$work/build/iso/keep.txt")" = 'user staging data'
if compgen -G "$work/build/.aweos-iso-work.*" >/dev/null; then
    echo "ERROR: temporary ISO workspace leaked after failure" >&2
    exit 1
fi

(
    cd "$work"
    PATH="$bin:$PATH" LIMINE_TOOL="$bin/limine" \
        AWEOS_LIMINE_CONFIG=Bootloader/x86_64/limine-debug.conf EXPECT_DEBUG_CONFIG=1 \
        bash ./scripts/build-iso.sh "$work/build"
)

grep -q '^mock ISO image$' "$work/build/AWEOS-x86_64.iso"
grep -q '^BIOS boot data$' "$work/build/AWEOS-x86_64.iso"
test "$(cat "$work/build/iso/keep.txt")" = 'user staging data'
if compgen -G "$work/build/.aweos-iso-work.*" >/dev/null; then
    echo "ERROR: temporary ISO workspace leaked after success" >&2
    exit 1
fi

echo "PASS: ISO assembly preserves prior artifacts and staging data, and honors the diagnostic boot config."
