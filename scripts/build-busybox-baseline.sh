#!/usr/bin/env bash
# Build the initramfs/rootfs BusyBox ourselves instead of copying the host
# distribution binary, which may be an amd64v3/AVX-optimized package.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
source "$SCRIPT_DIR/lib/build-safety.sh"

BUILD_DIR="$(aweos_prepare_build_dir "${1:-build}" "$REPO_ROOT")"
VERSION="1.38.0"
ARCHIVE="busybox-${VERSION}.tar.bz2"
URL="https://busybox.net/downloads/${ARCHIVE}"
# Pinned upstream tarball digest (also recorded by Buildroot's BusyBox recipe).
SHA256="34f9ea6ff8636f2c9241153b9114eefa9e65674a45318ae1ef95bb5f31c53bb2"

MUSL_CC="${MUSL_CC:-musl-gcc}"
for tool in curl sha256sum tar make readelf; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: $tool is required to build the baseline BusyBox." >&2
        exit 2
    }
done
command -v "$MUSL_CC" >/dev/null 2>&1 || {
    echo "ERROR: $MUSL_CC is required to build the baseline BusyBox." >&2
    exit 2
}

# BusyBox's default console-tools configuration builds kbd_mode, which
# includes <linux/kd.h>. musl provides libc headers but not the Linux UAPI
# development headers. Check this before downloading and compiling BusyBox so
# a missing linux-libc-dev package produces an actionable error.
# musl-gcc uses -nostdinc, so distro UAPI headers are not searched by
# default. Add them after musl's own headers to avoid mixing glibc headers
# into the target's libc include chain.
UAPI_INCLUDE_FLAGS=(-idirafter /usr/include -idirafter /usr/include/x86_64-linux-gnu)
if ! printf '#include <linux/kd.h>\n' |
    AWEOS_MUSL_CC="$MUSL_CC" bash "$SCRIPT_DIR/cc-x86_64-baseline.sh" \
        "${UAPI_INCLUDE_FLAGS[@]}" -x c -fsyntax-only - >/dev/null 2>&1; then
    echo "ERROR: Linux UAPI header <linux/kd.h> is unavailable to musl-gcc even with explicit UAPI include paths; install linux-libc-dev and verify the system UAPI headers." >&2
    exit 2
fi

# Verify the real compiler's effective target state, not just the wrapper's
# argument ordering. This catches a toolchain/specs mismatch before compiling
# the bootstrap binary.
TARGET_REPORT="$BUILD_DIR/busybox-compiler-target-report.txt"
AWEOS_MUSL_CC="$MUSL_CC" bash "$SCRIPT_DIR/cc-x86_64-baseline.sh" \
    -Q --help=target > "$TARGET_REPORT"
for option in -mavx -mavx2 -mavx512f -mbmi -mbmi2 -mmovbe \
              -mpopcnt -mlzcnt -msse3 -mssse3 -msse4.1 -msse4.2 \
              -maes -mpclmul -mrdrnd -mrdseed -madx; do
    if ! awk -v wanted="$option" \
        '$1 == wanted && $2 == "[disabled]" { found = 1 } END { exit !found }' \
        "$TARGET_REPORT"; then
        echo "ERROR: compiler target policy did not disable $option." >&2
        grep -E "^[[:space:]]*$option[[:space:]]" "$TARGET_REPORT" >&2 || true
        exit 2
    fi
done
awk '$1 == "-msse2" && $2 == "[enabled]" { found = 1 } END { exit !found }' \
    "$TARGET_REPORT" || {
    echo "ERROR: compiler target policy does not retain baseline SSE2." >&2
    exit 2
}
echo "Effective BusyBox compiler target policy:"
grep -E '^[[:space:]]+-(mavx|mavx2|mavx512f|mbmi|mbmi2|mmovbe|mpopcnt|mlzcnt|msse2|msse3|mssse3|msse4\.1|msse4\.2|maes|mpclmul|mrdrnd|mrdseed|madx)[[:space:]]' \
    "$TARGET_REPORT" || true
echo "PASS: the actual BusyBox compiler reports the required x86-64 baseline."

WORK_DIR="$(mktemp -d "$BUILD_DIR/.busybox-build.XXXXXX")"
TOOLS_DIR="$BUILD_DIR/tools"
OUTPUT="$TOOLS_DIR/busybox"
OUTPUT_TMP=""
CHECKSUM_TMP=""
cleanup() {
    rm -rf -- "$WORK_DIR"
    [ -z "$OUTPUT_TMP" ] || rm -f -- "$OUTPUT_TMP"
    [ -z "$CHECKSUM_TMP" ] || rm -f -- "$CHECKSUM_TMP"
}
trap cleanup EXIT

mkdir -p "$TOOLS_DIR"
TARBALL="$WORK_DIR/$ARCHIVE"

echo "Downloading pinned BusyBox $VERSION source..."
curl --fail --location --retry 3 --retry-all-errors --proto '=https' --tlsv1.2 \
    "$URL" -o "$TARBALL"
printf '%s  %s\n' "$SHA256" "$TARBALL" | sha256sum --check --status || {
    echo "ERROR: BusyBox source archive SHA-256 mismatch." >&2
    exit 1
}

tar -xjf "$TARBALL" -C "$WORK_DIR" --no-same-owner --no-same-permissions
SOURCE_DIR="$WORK_DIR/busybox-$VERSION"
[ -d "$SOURCE_DIR" ] || {
    echo "ERROR: BusyBox source directory is missing after extraction." >&2
    exit 1
}

make -C "$SOURCE_DIR" defconfig
bash "$SCRIPT_DIR/configure-busybox-baseline.sh" "$SOURCE_DIR"

jobs="${AWEOS_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLO 2>/dev/null || printf '2')}"
case "$jobs" in
    ''|*[!0-9]*) jobs=2 ;;
esac
[ "$jobs" -gt 0 ] || jobs=2
echo "Building static BusyBox with the enforced x86-64-v1 compiler policy..."
AWEOS_MUSL_CC="$MUSL_CC" make -C "$SOURCE_DIR" -j"$jobs" \
    HOSTCC="${HOSTCC:-cc}" \
    CC="bash $SCRIPT_DIR/cc-x86_64-baseline.sh ${UAPI_INCLUDE_FLAGS[*]}" \
    busybox

BUILT="$SOURCE_DIR/busybox"
[ -x "$BUILT" ] || {
    echo "ERROR: BusyBox build did not produce an executable." >&2
    exit 1
}
if readelf -l "$BUILT" 2>/dev/null | grep -q 'INTERP'; then
    echo "ERROR: BusyBox is dynamically linked; the bootstrap binary must be static." >&2
    exit 1
fi

required_applets=(
    awk cat chmod cp cttyhack dd find grep hostname ln mkdir mktemp mknod
    mount mv rm rmdir sed sha256sum sh sleep sort switch_root tar tr umount wc
)
applets="$("$BUILT" --list)"
for applet in "${required_applets[@]}"; do
    printf '%s\n' "$applet" | grep -Fxq "$applet" || {
        echo "ERROR: baseline BusyBox is missing required applet: $applet" >&2
        exit 1
    }
done

ISA_REPORT="$BUILD_DIR/busybox-isa-report.txt"
if ! AWEOS_ISA_REPORT_OUT="$ISA_REPORT" \
    bash "$SCRIPT_DIR/check-qemu64-baseline-isa.sh" "$BUILT"; then
    echo "ERROR: BusyBox ELF failed the qemu64 baseline ISA scan; attributing the offending code before failing." >&2
    ATTRIB="$BUILD_DIR/busybox-isa-attribution.txt"
    : > "$ATTRIB"

    # Soft scanner: counts offenders in any ELF or ar archive without failing.
    isa_soft_scan() {
        local path="$1"
        AWEOS_ISA_SOFT=1 bash "$SCRIPT_DIR/check-qemu64-baseline-isa.sh" "$path" \
            2>/dev/null || printf 'AWEOS_ISA_OFFENDERS=?\nAWEOS_ISA_SYMBOLS=unreadable\n'
    }
    isa_attribute() {
        local label="$1" path="$2" scan count symbols
        [ -f "$path" ] && [ -s "$path" ] || return 0
        scan="$(isa_soft_scan "$path")"
        count="$(printf '%s\n' "$scan" | sed -n 's/^AWEOS_ISA_OFFENDERS=//p' | tail -n1)"
        symbols="$(printf '%s\n' "$scan" | sed -n 's/^AWEOS_ISA_SYMBOLS=//p' | tail -n1)"
        {
            echo "input: $label"
            echo "  path: $path"
            echo "  offenders: ${count:-?}; top symbols: ${symbols:-none}"
        } >> "$ATTRIB"
        if [ -n "${count:-}" ] && [ "$count" != "0" ] && [ "$count" != "?" ]; then
            echo "DIRTY: $label contains $count non-baseline instructions (symbols: ${symbols:-unknown})." | tee -a "$ATTRIB"
        fi
    }

    {
        echo "AWEOS qemu64/x86-64 ISA scan attribution"
        echo "Final BusyBox ELF: $BUILT"
        if [ -s "$ISA_REPORT" ]; then
            echo
            echo "Per-symbol offender counts in the final ELF:"
            awk '/^[[:space:]]*[[:xdigit:]]+[[:space:]]+<[^>]+>:/ {
                     name = $2
                     gsub(/[<>:]/, "", name)
                     counts[name]++
                 }
                 END {
                     for (name in counts) {
                         print counts[name], name
                     }
                 }' "$ISA_REPORT" | sort -rn | head -n 10
        else
            echo "The persisted ISA report is missing or empty."
        fi
        echo
        echo "Scanned linked inputs:"
    } >> "$ATTRIB"

    # 1. BusyBox's own compiled code: kbuild archives everything linked into
    #    the final binary into per-directory built-in.a archives.
    found_builtins=0
    while IFS= read -r -d '' input; do
        found_builtins=1
        rel="${input#"$SOURCE_DIR"/}"
        isa_attribute "busybox built-in.a:$rel" "$input"
    done < <(find "$SOURCE_DIR" -type f -name 'built-in.a' -print0 | sort -z)
    if [ "$found_builtins" -eq 0 ]; then
        {
            echo "input: busybox per-object fallback"
            echo "  note: no built-in.a archives were found under the source tree; scanning all non-scripts objects instead."
        } >> "$ATTRIB"
        while IFS= read -r -d '' input; do
            rel="${input#"$SOURCE_DIR"/}"
            isa_attribute "busybox object:$rel" "$input"
        done < <(find "$SOURCE_DIR" -type f -name '*.o' -not -path "$SOURCE_DIR/scripts/*" -print0 | sort -z)
    fi

    # 2. Prebuilt toolchain inputs consumed by the static link.
    toolchain_libc=""
    candidate="$("$MUSL_CC" -print-file-name=libc.a 2>/dev/null || true)"
    case "$candidate" in
        /*) [ -f "$candidate" ] && toolchain_libc="$candidate" ;;
    esac
    if [ -z "$toolchain_libc" ]; then
        for dir in /usr/lib/x86_64-linux-musl /usr/lib/musl /usr/local/musl/lib; do
            if [ -f "$dir/libc.a" ]; then
                toolchain_libc="$dir/libc.a"
                break
            fi
        done
    fi
    [ -n "$toolchain_libc" ] || {
        echo "input: musl libc.a (prebuilt)" >> "$ATTRIB"
        echo "  note: could not locate the musl libc.a consumed by the static link." >> "$ATTRIB"
    }
    [ -n "$toolchain_libc" ] && \
        isa_attribute "musl libc.a (prebuilt toolchain)" "$toolchain_libc"

    toolchain_libgcc="$("$MUSL_CC" -print-libgcc-file-name 2>/dev/null || true)"
    case "$toolchain_libgcc" in
        /*) isa_attribute "libgcc.a (prebuilt toolchain)" "$toolchain_libgcc" ;;
        *)
            {
                echo "input: libgcc.a (prebuilt toolchain)"
                echo "  note: the compiler did not report an absolute libgcc path ($toolchain_libgcc)."
            } >> "$ATTRIB"
            ;;
    esac

    for crt in crt1.o crti.o crtn.o Scrt1.o rcrt1.o; do
        crt_path="$("$MUSL_CC" -print-file-name="$crt" 2>/dev/null || true)"
        case "$crt_path" in
            /*) isa_attribute "crt object $crt (prebuilt toolchain)" "$crt_path" ;;
        esac
    done

    {
        echo
        echo "DIAGNOSIS:"
        if grep -q '^DIRTY:' "$ATTRIB"; then
            echo "Linked inputs that contain non-baseline instructions:"
            grep '^DIRTY:' "$ATTRIB"
        else
            echo "No scanned linked input reproduced the violation; the offending code is in an input that was not located or scanned. Record every link input before changing flags."
        fi
    } >> "$ATTRIB"

    cat "$ATTRIB"
    echo "ERROR: BusyBox packaging remains fail-closed. Full attribution: $ATTRIB; symbol report: $ISA_REPORT." >&2
    exit 1
fi

OUTPUT_TMP="$(mktemp "$TOOLS_DIR/.busybox.XXXXXX")"
CHECKSUM_TMP="$(mktemp "$TOOLS_DIR/busybox.sha256.XXXXXX")""
install -m 0755 "$BUILT" "$OUTPUT_TMP"
sha256sum "$OUTPUT_TMP" > "$CHECKSUM_TMP"
mv -f -- "$OUTPUT_TMP" "$OUTPUT"
OUTPUT_TMP=""
mv -f -- "$CHECKSUM_TMP" "$OUTPUT.sha256"
CHECKSUM_TMP=""

echo "PASS: baseline static BusyBox $VERSION published at $OUTPUT"
