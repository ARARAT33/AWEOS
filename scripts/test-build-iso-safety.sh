#!/usr/bin/env bash
# Regression test for safe, atomic hybrid ISO assembly and xorriso EFI syntax.
# Uses the real build script with mocked xorriso and Limine; no disk devices.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-iso-test.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT
work="$tmp_root/work"
bin="$tmp_root/bin"
args_file="$tmp_root/xorriso-args.txt"

mkdir -p "$work/Bootloader/x86_64" "$work/build/linux-x86_64/arch/x86/boot" "$work/lib" "$bin"
cp "$repo_root/scripts/build-iso.sh" "$work/scripts-build-iso.sh"
cp "$repo_root/scripts/lib/build-safety.sh" "$work/lib/build-safety.sh"

for file in limine-bios.sys limine-bios-cd.bin limine-uefi-cd.bin BOOTX64.EFI limine.conf; do
    printf 'mock %s\n' "$file" > "$work/Bootloader/x86_64/$file"
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
args=("$@")
printf '%s\n' "${args[@]}" > "$XORRISO_ARGS_FILE"

found_efi_part=0
for ((i = 0; i < ${#args[@]}; i++)); do
    if [[ "${args[$i]}" == "-efi-boot-part" ]]; then
        [[ $((i + 1)) -lt ${#args[@]} ]] || {
            echo "missing -efi-boot-part argument" >&2
            exit 41
        }
        [[ "${args[$((i + 1))]}" == "--efi-boot-image" ]] || {
            echo "expected literal --efi-boot-image after -efi-boot-part" >&2
            exit 42
        }
        found_efi_part=1
    fi
done
[[ "$found_efi_part" == "1" ]] || {
    echo "EFI system partition exposure is missing" >&2
    exit 43
}
[[ -s limine-uefi-cd.bin && -s limine-bios-cd.bin && -s EFI/BOOT/BOOTX64.EFI ]]
if [[ "${EXPECT_DEBUG_CONFIG:-0}" == "1" ]]; then
    grep -q '^serial: yes$' limine.conf
    grep -q 'earlycon=uart8250' limine.conf
fi

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
chmod 0755 "$bin/xorriso" "$bin/limine"

mkdir -p "$work/build/iso"
printf 'AWEOS build directory v1\n' > "$work/build/.aweos-build-dir"
printf 'user staging data\n' > "$work/build/iso/keep.txt"
printf 'previous valid ISO\n' > "$work/build/AWEOS-x86_64.iso"

if (
    cd "$work"
    PATH="$bin:$PATH" \
        LIMINE_TOOL="$bin/limine" \
        XORRISO_ARGS_FILE="$args_file" \
        FAIL_BIOS_INSTALL=1 \
        bash ./scripts-build-iso.sh "$work/build"
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
    PATH="$bin:$PATH" \
        LIMINE_TOOL="$bin/limine" \
        XORRISO_ARGS_FILE="$args_file" \
        AWEOS_LIMINE_CONFIG=Bootloader/x86_64/limine-debug.conf \
        EXPECT_DEBUG_CONFIG=1 \
        bash ./scripts-build-iso.sh "$work/build"
)

grep -q '^mock ISO image$' "$work/build/AWEOS-x86_64.iso"
grep -q '^BIOS boot data$' "$work/build/AWEOS-x86_64.iso"
test "$(cat "$work/build/iso/keep.txt")" = 'user staging data'
awk 'previous == "-efi-boot-part" && $0 == "--efi-boot-image" { found = 1 } { previous = $0 } END { exit !found }' "$args_file"
grep -Fx -- '--efi-boot' "$args_file"
grep -Fx -- 'limine-uefi-cd.bin' "$args_file"
if compgen -G "$work/build/.aweos-iso-work.*" >/dev/null; then
    echo "ERROR: temporary ISO workspace leaked after success" >&2
    exit 1
fi

echo "PASS: hybrid ISO uses the correct EFI partition token, preserves prior artifacts/staging data, and publishes only after Limine succeeds."
