#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CHECKER="${SCRIPT_DIR}/check-musl-baseline-archives.sh"
ISA_CHECKER="${SCRIPT_DIR}/check-x86-64-baseline-isa.sh"
ARCHIVE_CHECKER="${SCRIPT_DIR}/check-x86-64-baseline-archive.sh"

for tool in cc ar; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: $tool is required." >&2
        exit 2
    }
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aweos-musl-archive-test.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT

cat >"$WORK_DIR/baseline.S" <<'ASM'
.text
.globl archive_baseline
archive_baseline:
    nop
    ret
ASM
cat >"$WORK_DIR/avx.S" <<'ASM'
.text
.globl archive_avx
archive_avx:
    vmovdqa %xmm0, %xmm1
    ret
ASM

cc -c "$WORK_DIR/baseline.S" -o "$WORK_DIR/baseline.o"
cc -mavx -c "$WORK_DIR/avx.S" -o "$WORK_DIR/avx.o"

make_lib_dir() {
    mkdir -p "$1"
    ar rcs "$1/libc.a" "$WORK_DIR/baseline.o"
    ar rc "$1/libcrypt.a"
    ar rc "$1/libm.a"
}

# The exact musl compatibility allowlist is accepted when empty, while libc.a
# is required to be present and non-empty.
VALID_DIR="$WORK_DIR/valid"
make_lib_dir "$VALID_DIR"
bash "$CHECKER" "$VALID_DIR" "$ISA_CHECKER" "$ARCHIVE_CHECKER" >"$WORK_DIR/valid.log"
grep -q 'libcrypt.a is an intentionally empty musl compatibility archive' "$WORK_DIR/valid.log"
grep -q 'libm.a is an intentionally empty musl compatibility archive' "$WORK_DIR/valid.log"
grep -q 'verified 1 non-empty musl archives and accepted 2 allowlisted empty compatibility archives' "$WORK_DIR/valid.log"

# Unknown empty archives must not be silently exempted.
UNKNOWN_DIR="$WORK_DIR/unknown"
make_lib_dir "$UNKNOWN_DIR"
ar rc "$UNKNOWN_DIR/libunknown.a"
if bash "$CHECKER" "$UNKNOWN_DIR" "$ISA_CHECKER" "$ARCHIVE_CHECKER" >"$WORK_DIR/unknown.log" 2>&1; then
    echo "ERROR: unknown empty archive was accepted." >&2
    exit 1
fi
grep -q 'not on the compatibility allowlist' "$WORK_DIR/unknown.log"

# An allowlisted archive is scanned normally if it contains objects; its
# filename never exempts non-empty contents from the ISA guard.
UNSAFE_DIR="$WORK_DIR/unsafe"
make_lib_dir "$UNSAFE_DIR"
ar rcs "$UNSAFE_DIR/libcrypt.a" "$WORK_DIR/avx.o"
if bash "$CHECKER" "$UNSAFE_DIR" "$ISA_CHECKER" "$ARCHIVE_CHECKER" >"$WORK_DIR/unsafe.log" 2>&1; then
    echo "ERROR: AVX code in a non-empty compatibility archive was accepted." >&2
    exit 1
fi
grep -q 'libcrypt.a' "$WORK_DIR/unsafe.log"
grep -q 'vmovdqa' "$WORK_DIR/unsafe.log"

# The primary libc archive is never allowed to be empty or absent.
EMPTY_LIBC_DIR="$WORK_DIR/empty-libc"
mkdir -p "$EMPTY_LIBC_DIR"
ar rc "$EMPTY_LIBC_DIR/libc.a"
ar rc "$EMPTY_LIBC_DIR/libcrypt.a"
if bash "$CHECKER" "$EMPTY_LIBC_DIR" "$ISA_CHECKER" "$ARCHIVE_CHECKER" >"$WORK_DIR/empty-libc.log" 2>&1; then
    echo "ERROR: empty primary libc archive was accepted." >&2
    exit 1
fi
grep -q 'unexpected empty musl archive' "$WORK_DIR/empty-libc.log"

MISSING_LIBC_DIR="$WORK_DIR/missing-libc"
mkdir -p "$MISSING_LIBC_DIR"
ar rc "$MISSING_LIBC_DIR/libcrypt.a"
if bash "$CHECKER" "$MISSING_LIBC_DIR" "$ISA_CHECKER" "$ARCHIVE_CHECKER" >"$WORK_DIR/missing-libc.log" 2>&1; then
    echo "ERROR: musl library set without libc.a was accepted." >&2
    exit 1
fi
grep -q 'libc.a is missing or contains no members' "$WORK_DIR/missing-libc.log"

echo "PASS: musl archive validation accepts only allowlisted empty compatibility archives, scans non-empty archives, and requires a non-empty libc.a."
