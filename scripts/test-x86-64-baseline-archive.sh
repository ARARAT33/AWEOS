#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ARCHIVE_CHECKER="${SCRIPT_DIR}/check-x86-64-baseline-archive.sh"
ISA_CHECKER="${SCRIPT_DIR}/check-x86-64-baseline-isa.sh"
for tool in cc ar; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: $tool is required." >&2
        exit 2
    }
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aweos-archive-isa-test.XXXXXX")"
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

# Deliberately use .lo rather than .o to cover archive member suffixes used
# by some static-library build systems.
cc -c "$WORK_DIR/baseline.S" -o "$WORK_DIR/baseline.lo"
cc -mavx -c "$WORK_DIR/avx.S" -o "$WORK_DIR/avx.lo"
ar rcs "$WORK_DIR/baseline.a" "$WORK_DIR/baseline.lo"
ar rcs "$WORK_DIR/avx.a" "$WORK_DIR/avx.lo"

bash "$ARCHIVE_CHECKER" "$WORK_DIR/baseline.a" "$ISA_CHECKER"

if bash "$ARCHIVE_CHECKER" "$WORK_DIR/avx.a" "$ISA_CHECKER" >"$WORK_DIR/avx.log" 2>&1; then
    echo "ERROR: archive checker accepted an AVX archive member." >&2
    exit 1
fi
grep -q "avx.lo" "$WORK_DIR/avx.log"
grep -q "vmovdqa" "$WORK_DIR/avx.log"

# Duplicate basenames are valid in static archives. Verify all occurrences:
# the first is baseline-safe and the second deliberately contains AVX.
mkdir -p "$WORK_DIR/duplicate-safe/a" "$WORK_DIR/duplicate-safe/b"
mkdir -p "$WORK_DIR/duplicate-mixed/a" "$WORK_DIR/duplicate-mixed/b"
cc -c "$WORK_DIR/baseline.S" -o "$WORK_DIR/duplicate-safe/a/clone.lo"
cc -c "$WORK_DIR/baseline.S" -o "$WORK_DIR/duplicate-safe/b/clone.lo"
cc -c "$WORK_DIR/baseline.S" -o "$WORK_DIR/duplicate-mixed/a/clone.lo"
cc -mavx -c "$WORK_DIR/avx.S" -o "$WORK_DIR/duplicate-mixed/b/clone.lo"
ar rcs "$WORK_DIR/duplicate-safe.a" "$WORK_DIR/duplicate-safe/a/clone.lo" "$WORK_DIR/duplicate-safe/b/clone.lo"
ar rcs "$WORK_DIR/duplicate-mixed.a" "$WORK_DIR/duplicate-mixed/a/clone.lo" "$WORK_DIR/duplicate-mixed/b/clone.lo"

bash "$ARCHIVE_CHECKER" "$WORK_DIR/duplicate-safe.a" "$ISA_CHECKER"
if bash "$ARCHIVE_CHECKER" "$WORK_DIR/duplicate-mixed.a" "$ISA_CHECKER" >"$WORK_DIR/duplicate-mixed.log" 2>&1; then
    echo "ERROR: archive checker skipped an unsafe duplicate member." >&2
    exit 1
fi
grep -q "clone.lo.*occurrence #2" "$WORK_DIR/duplicate-mixed.log"
grep -q "vmovdqa" "$WORK_DIR/duplicate-mixed.log"

printf 'not an ELF object\n' >"$WORK_DIR/invalid.member"
ar rcs "$WORK_DIR/invalid.a" "$WORK_DIR/invalid.member"
if bash "$ARCHIVE_CHECKER" "$WORK_DIR/invalid.a" "$ISA_CHECKER" >"$WORK_DIR/invalid.log" 2>&1; then
    echo "ERROR: archive checker accepted a non-ELF member." >&2
    exit 1
fi
grep -q "invalid.member" "$WORK_DIR/invalid.log"

ar rcs "$WORK_DIR/empty.a"
if bash "$ARCHIVE_CHECKER" "$WORK_DIR/empty.a" "$ISA_CHECKER" >"$WORK_DIR/empty.log" 2>&1; then
    echo "ERROR: archive checker accepted an empty archive." >&2
    exit 1
fi
grep -q "no members" "$WORK_DIR/empty.log"

echo "PASS: archive ISA scan handles .lo and duplicate members, rejects AVX/invalid members, and fails on empty archives."
