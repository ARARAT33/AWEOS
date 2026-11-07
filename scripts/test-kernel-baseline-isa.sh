#!/usr/bin/env bash
# Test the compressed-kernel ISA checker with one safe and one BMI2 fixture.
set -euo pipefail

here="$(cd -- "$(dirname -- "$0")" && pwd -P)"
checker="$here/check-kernel-baseline-isa.sh"
command -v cc >/dev/null 2>&1 || { echo "ERROR: cc is required for ISA checker tests." >&2; exit 2; }
command -v objdump >/dev/null 2>&1 || { echo "ERROR: objdump is required for ISA checker tests." >&2; exit 2; }
workdir="$(mktemp -d "${TMPDIR:-/tmp}/aweos-kernel-isa-test.XXXXXX")"
trap 'rm -rf -- "$workdir"' EXIT

cat >"$workdir/safe.S" <<'ASM'
.text
.globl aweos_safe_fixture
aweos_safe_fixture:
    nop
    ret
ASM

cat >"$workdir/unsafe.S" <<'ASM'
.text
.globl aweos_unsafe_fixture
aweos_unsafe_fixture:
    # SHRX r64, r/m64, r64 (BMI2), encoded explicitly so the test does not
    # depend on the host compiler's default target ISA.
    .byte 0xc4, 0xe2, 0xfb, 0xf7, 0xca
    ret
ASM

cc -c "$workdir/safe.S" -o "$workdir/safe.o"
cc -c "$workdir/unsafe.S" -o "$workdir/unsafe.o"

bash "$checker" "$workdir/safe.o"
if bash "$checker" "$workdir/unsafe.o" >"$workdir/unsafe.out" 2>&1; then
    echo "ERROR: ISA checker accepted an object containing SHRX/BMI2." >&2
    exit 1
fi
grep -q 'shrx' "$workdir/unsafe.out"
echo "PASS: compressed-kernel ISA checker accepts baseline code and rejects BMI2 code."
