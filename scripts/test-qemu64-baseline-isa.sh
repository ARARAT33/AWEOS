#!/usr/bin/env bash
# Regression test for the x86-64 baseline ELF checker.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
checker="$here/check-qemu64-baseline-isa.sh"
command -v cc >/dev/null 2>&1 || { echo "ERROR: cc is required." >&2; exit 2; }
command -v objdump >/dev/null 2>&1 || { echo "ERROR: objdump is required." >&2; exit 2; }
command -v readelf >/dev/null 2>&1 || { echo "ERROR: readelf is required." >&2; exit 2; }

workdir="$(mktemp -d "${TMPDIR:-/tmp}/aweos-qemu64-isa-test.XXXXXX")"
trap 'rm -rf -- "$workdir"' EXIT

cat >"$workdir/safe.S" <<'ASM'
.text
.globl aweos_safe_fixture
aweos_safe_fixture:
    nop
    ret
ASM

cat >"$workdir/avx.S" <<'ASM'
.text
.globl aweos_avx_fixture
aweos_avx_fixture:
    # VEX-encoded VMOVDQA xmm0, [rip+0].
    .byte 0xc5, 0xf9, 0x6f, 0x05, 0x00, 0x00, 0x00, 0x00
    ret
ASM

cat >"$workdir/bmi2.S" <<'ASM'
.text
.globl aweos_bmi2_fixture
aweos_bmi2_fixture:
    # SHRX r64, r/m64, r64 (BMI2).
    .byte 0xc4, 0xe2, 0xfb, 0xf7, 0xca
    ret
ASM

cc -c "$workdir/safe.S" -o "$workdir/safe.o"
cc -c "$workdir/avx.S" -o "$workdir/avx.o"
cc -c "$workdir/bmi2.S" -o "$workdir/bmi2.o"

bash "$checker" "$workdir/safe.o"

if bash "$checker" "$workdir/avx.o" >"$workdir/avx.out" 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted a VEX/AVX instruction." >&2
    exit 1
fi
grep -Eqi 'vmovdqa|avx' "$workdir/avx.out"

if bash "$checker" "$workdir/bmi2.o" >"$workdir/bmi2.out" 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted SHRX/BMI2." >&2
    exit 1
fi
grep -Eqi 'shrx|bmi' "$workdir/bmi2.out"

echo "PASS: qemu64 ISA checker accepts baseline code and rejects AVX and BMI2."
