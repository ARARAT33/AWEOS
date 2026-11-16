#!/usr/bin/env bash
# Regression test for the x86-64 baseline ELF checker.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
checker="$here/check-qemu64-baseline-isa.sh"
command -v cc >/dev/null 2>&1 || { echo "ERROR: cc is required." >&2; exit 2; }
command -v objdump >/dev/null 2>&1 || { echo "ERROR: objdump is required." >&2; exit 2; }
command -v readelf >/dev/null 2>&1 || { echo "ERROR: readelf is required." >&2; exit 2; }
command -v ar >/dev/null 2>&1 || { echo "ERROR: ar is required." >&2; exit 2; }

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

cat >"$workdir/memchr-dispatch.S" <<'ASM'
.text
# This exact Rust-v0 symbol path models memchr's private x86_64 runtime
# dispatcher thunk. The production crate checks AVX2 availability before
# storing/calling this target-feature function pointer.
.globl _RNvNvNtNtNtCsdUDvdapExkK_6memchr4arch6x86_646memchr11memrchr_raw9find_avx2
_RNvNvNtNtNtCsdUDvdapExkK_6memchr4arch6x86_646memchr11memrchr_raw9find_avx2:
    # VEX2 VMOVDQA xmm0, xmm0.
    .byte 0xc5, 0xf9, 0x6f, 0xc0
    ret
ASM

cat >"$workdir/memchr-lookalike.S" <<'ASM'
.text
# A similar-looking AVX2 implementation path is not the dispatcher module
# and must not inherit the runtime-dispatch exception.
.globl _RNvNvNtNtNtCsdUDvdapExkK_6memchr4arch6x86_644avx24memchr11memrchr_raw9find_avx2
_RNvNvNtNtNtCsdUDvdapExkK_6memchr4arch6x86_644avx24memchr11memrchr_raw9find_avx2:
    .byte 0xc5, 0xf9, 0x6f, 0xc0
    ret
ASM

cat >"$workdir/memchr-evex.S" <<'ASM'
.text
.globl _RNvNvNtNtNtCsdUDvdapExkK_6memchr4arch6x86_646memchr11memrchr_raw9find_avx2
_RNvNvNtNtNtCsdUDvdapExkK_6memchr4arch6x86_646memchr11memrchr_raw9find_avx2:
    # EVEX VPXORD zmm0, zmm0, zmm0 must not be allowlisted.
    .byte 0x62, 0xf1, 0x7d, 0x48, 0xef, 0xc0
    ret
ASM

cat >"$workdir/memchr-bmi2.S" <<'ASM'
.text
.globl _RNvNvNtNtNtCsdUDvdapExkK_6memchr4arch6x86_646memchr11memrchr_raw9find_avx2
_RNvNvNtNtNtCsdUDvdapExkK_6memchr4arch6x86_646memchr11memrchr_raw9find_avx2:
    # SHRX r64, r/m64, r64 remains rejected even in an allowlisted symbol.
    .byte 0xc4, 0xe2, 0xfb, 0xf7, 0xca
    ret
ASM

cat >"$workdir/bmi1.S" <<'ASM'
.text
.globl aweos_tzcnt_fixture
aweos_tzcnt_fixture:
    # TZCNT rax, rbx (F3 0F BC: rep-prefixed BSF encoding; executes as BSF
    # on CPUs without BMI1, so it must be accepted by the checker).
    .byte 0xf3, 0x48, 0x0f, 0xbc, 0xc3
    ret
ASM

cat >"$workdir/lzcnt.S" <<'ASM'
.text
.globl aweos_lzcnt_fixture
aweos_lzcnt_fixture:
    # LZCNT rax, rbx (F3 0F BD) stays rejected: the gate allows only the
    # narrow tzcnt encoding exception.
    .byte 0xf3, 0x48, 0x0f, 0xbd, 0xc3
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
cc -c "$workdir/memchr-dispatch.S" -o "$workdir/memchr-dispatch.o"
cc -c "$workdir/memchr-lookalike.S" -o "$workdir/memchr-lookalike.o"
cc -c "$workdir/memchr-evex.S" -o "$workdir/memchr-evex.o"
cc -c "$workdir/memchr-bmi2.S" -o "$workdir/memchr-bmi2.o"
cc -c "$workdir/bmi1.S" -o "$workdir/bmi1.o"
cc -c "$workdir/lzcnt.S" -o "$workdir/lzcnt.o"
cc -c "$workdir/bmi2.S" -o "$workdir/bmi2.o"

# With no report path configured, the checker must not create a stray
# file named "-" in its caller's working directory.
(
    cd "$workdir"
    bash "$checker" "$workdir/safe.o" >"$workdir/default.out"
    [ ! -e "$workdir/-" ]
)

if bash "$checker" "$workdir/avx.o" >"$workdir/avx.out" 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted a VEX/AVX instruction." >&2
    exit 1
fi
grep -Eqi 'vmovdqa|avx' "$workdir/avx.out"
# The first error line must name the offending symbol for CI annotations.
grep -Eq 'aweos_avx_fixture' "$workdir/avx.out"

# Only VEX2/VEX3 instructions in memchr's exact runtime-dispatch thunk are
# permitted. The source-backed dispatcher performs CPU/OS-state detection;
# qemu64 therefore takes the SSE2 path and never calls this AVX2 thunk.
bash "$checker" "$workdir/memchr-dispatch.o" >"$workdir/memchr-dispatch.out" 2>&1
grep -q 'PASS' "$workdir/memchr-dispatch.out"
soft_memchr="$(AWEOS_ISA_SOFT=1 bash "$checker" "$workdir/memchr-dispatch.o")"
grep -q 'AWEOS_ISA_OFFENDERS=0' <<<"$soft_memchr"

# The allowlist must not match a lookalike path outside memchr's dispatcher.
if bash "$checker" "$workdir/memchr-lookalike.o" >"$workdir/memchr-lookalike.out" 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted an AVX2 lookalike outside the dispatcher." >&2
    exit 1
fi
grep -q 'find_avx2' "$workdir/memchr-lookalike.out"

# EVEX/AVX-512 and BMI2 remain rejected even inside the allowlisted symbol.
if bash "$checker" "$workdir/memchr-evex.o" >"$workdir/memchr-evex.out" 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted EVEX inside the memchr dispatcher." >&2
    exit 1
fi
grep -qi 'vpxord' "$workdir/memchr-evex.out"
if bash "$checker" "$workdir/memchr-bmi2.o" >"$workdir/memchr-bmi2.out" 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted BMI2 inside the memchr dispatcher." >&2
    exit 1
fi
grep -qi 'shrx' "$workdir/memchr-bmi2.out"

# tzcnt (rep bsf) must be accepted: it decodes as BSF without BMI1.
bash "$checker" "$workdir/bmi1.o" >"$workdir/bmi1.out" 2>&1
grep -q 'PASS' "$workdir/bmi1.out"

# lzcnt must still be rejected fail-closed.
if bash "$checker" "$workdir/lzcnt.o" >"$workdir/lzcnt.out" 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted LZCNT." >&2
    exit 1
fi
grep -Eqi 'lzcnt|bmi' "$workdir/lzcnt.out"

if bash "$checker" "$workdir/bmi2.o" >"$workdir/bmi2.out" 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted SHRX/BMI2." >&2
    exit 1
fi
grep -Eqi 'shrx|bmi' "$workdir/bmi2.out"

# The full symbol-labeled report must be persisted when requested, without
# changing the fail-closed verdict.
if AWEOS_ISA_REPORT_OUT="$workdir/persisted-report.txt" \
    bash "$checker" "$workdir/avx.o" >"$workdir/persisted.out" 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted a VEX/AVX instruction." >&2
    exit 1
fi
grep -q 'aweos_avx_fixture' "$workdir/persisted-report.txt"
if AWEOS_ISA_REPORT_OUT="$workdir/persisted-safe.txt" \
    bash "$checker" "$workdir/safe.o" >/dev/null 2>&1; then
    [ -f "$workdir/persisted-safe.txt" ] || {
        echo "ERROR: qemu64 ISA report was not persisted for a passing ELF." >&2
        exit 1
    }
    if [ -s "$workdir/persisted-safe.txt" ]; then
        echo "ERROR: qemu64 ISA report for a passing ELF should be empty." >&2
        exit 1
    fi
fi

# Soft diagnostic mode must never fail and must report machine-readable
# offender counts and top symbols, including for ar archives.
soft_avx="$(AWEOS_ISA_SOFT=1 bash "$checker" "$workdir/avx.o")"
grep -Eq 'AWEOS_ISA_OFFENDERS=[1-9][0-9]*' <<<"$soft_avx"
grep -q 'AWEOS_ISA_SYMBOLS=aweos_avx_fixture' <<<"$soft_avx"
soft_safe="$(AWEOS_ISA_SOFT=1 bash "$checker" "$workdir/safe.o")"
grep -q 'AWEOS_ISA_OFFENDERS=0' <<<"$soft_safe"

# ar archives must be attributable in soft mode but still rejected in the
# default fail-closed mode.
ar rcs "$workdir/fixture.a" "$workdir/avx.o"
soft_archive="$(AWEOS_ISA_SOFT=1 bash "$checker" "$workdir/fixture.a")"
grep -Eq 'AWEOS_ISA_OFFENDERS=[1-9][0-9]*' <<<"$soft_archive"
grep -q 'AWEOS_ISA_SYMBOLS=aweos_avx_fixture' <<<"$soft_archive"
if bash "$checker" "$workdir/fixture.a" >/dev/null 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted an ar archive outside soft mode." >&2
    exit 1
fi
if AWEOS_ISA_SOFT=1 bash "$checker" "$workdir/safe.o" >/dev/null; then
    :
else
    echo "ERROR: soft mode must always exit successfully." >&2
    exit 1
fi

echo "PASS: qemu64 ISA checker accepts baseline and guarded memchr dispatch code, rejects unguarded AVX, EVEX, BMI1 and BMI2, persists reports, and supports soft archive attribution."
