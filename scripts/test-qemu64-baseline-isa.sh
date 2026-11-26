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

cat >"$workdir/stdmemchr.S" <<'ASM'
.text
.globl _ZN6memchr4arch6x86_646memchr11memrchr_raw9find_avx2E
_ZN6memchr4arch6x86_646memchr11memrchr_raw9find_avx2E:
    # VEX-encoded VMOVDQA inside a Rust std memchr runtime-dispatched AVX2
    # kernel. The kernel is entered only behind is_x86_feature_detected!
    # ("avx2"), so it cannot execute on qemu64 and must be accepted.
    .byte 0xc5, 0xf9, 0x6f, 0x05, 0x00, 0x00, 0x00, 0x00
    ret
ASM

cat >"$workdir/stdmemchr-nokernel.S" <<'ASM'
.text
.globl _ZN6memchr4arch6x86_646memchr6detectE
_ZN6memchr4arch6x86_646memchr6detectE:
    # Same VEX bytes in a memchr arch symbol WITHOUT an avx2/ssse3/sse42
    # kernel marker: the narrow exception must not apply, fail closed.
    .byte 0xc5, 0xf9, 0x6f, 0x05, 0x00, 0x00, 0x00, 0x00
    ret
ASM

cat >"$workdir/stdmemchr-avx512.S" <<'ASM'
.text
.globl _ZN6memchr4arch6x86_646memchr9find_avx512E
_ZN6memchr4arch6x86_646memchr9find_avx512E:
    # VEX/EVEX bytes under an avx512 kernel name: AVX-512 stays rejected
    # even inside the memchr arch path, fail closed.
    .byte 0xc5, 0xf9, 0x6f, 0x05, 0x00, 0x00, 0x00, 0x00
    ret
ASM

cat >"$workdir/othercrate-avx.S" <<'ASM'
.text
.globl _ZN9othercrate4arch6x86_6410find_avx2E
_ZN9othercrate4arch6x86_6410find_avx2E:
    # Same VEX bytes outside the memchr arch path: fail closed.
    .byte 0xc5, 0xf9, 0x6f, 0x05, 0x00, 0x00, 0x00, 0x00
    ret
ASM

cat >"$workdir/sha2x86.S" <<'ASM'
.text
.globl _ZN4sha26sha2563x8613digest_blocksE
_ZN4sha26sha2563x8613digest_blocksE:
    # SSSE3 pshufb inside the RustCrypto sha2 runtime-dispatched
    # sha256::x86 backend kernel. The kernel is entered only behind CPU
    # feature detection, so it cannot execute on qemu64 and must be
    # accepted.
    .byte 0x66, 0x0f, 0x38, 0x00, 0xc1
    ret
ASM

cat >"$workdir/sha2-nokernel.S" <<'ASM'
.text
.globl _ZN4sha26sha2566detectE
_ZN4sha26sha2566detectE:
    # Same SSSE3 bytes in a sha2 symbol WITHOUT digest_blocks: the narrow
    # exception must not apply, fail closed.
    .byte 0x66, 0x0f, 0x38, 0x00, 0xc1
    ret
ASM

cat >"$workdir/sha2-nobackend.S" <<'ASM'
.text
.globl _ZN4sha29sha512_x8613digest_blocksE
_ZN4sha29sha512_x8613digest_blocksE:
    # sha2 digest_blocks without a 3x86/4shani/avx2 backend marker: fail
    # closed.
    .byte 0x66, 0x0f, 0x38, 0x00, 0xc1
    ret
ASM

cat >"$workdir/othercrate-shani.S" <<'ASM'
.text
.globl _ZN9digester6sha2564shani13digest_blocksE
_ZN9digester6sha2564shani13digest_blocksE:
    # Same SSSE3 bytes outside the sha2 crate: fail closed.
    .byte 0x66, 0x0f, 0x38, 0x00, 0xc1
    ret
ASM

cc -c "$workdir/safe.S" -o "$workdir/safe.o"
cc -c "$workdir/avx.S" -o "$workdir/avx.o"
cc -c "$workdir/bmi1.S" -o "$workdir/bmi1.o"
cc -c "$workdir/lzcnt.S" -o "$workdir/lzcnt.o"
cc -c "$workdir/bmi2.S" -o "$workdir/bmi2.o"
cc -c "$workdir/stdmemchr.S" -o "$workdir/stdmemchr.o"
cc -c "$workdir/stdmemchr-nokernel.S" -o "$workdir/stdmemchr-nokernel.o"
cc -c "$workdir/stdmemchr-avx512.S" -o "$workdir/stdmemchr-avx512.o"
cc -c "$workdir/othercrate-avx.S" -o "$workdir/othercrate-avx.o"
cc -c "$workdir/sha2x86.S" -o "$workdir/sha2x86.o"
cc -c "$workdir/sha2-nokernel.S" -o "$workdir/sha2-nokernel.o"
cc -c "$workdir/sha2-nobackend.S" -o "$workdir/sha2-nobackend.o"
cc -c "$workdir/othercrate-shani.S" -o "$workdir/othercrate-shani.o"

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

# The Rust std memchr runtime-dispatched AVX2 kernel must be accepted: it
# is entered only behind is_x86_feature_detected!("avx2") and therefore
# cannot execute on qemu64.
bash "$checker" "$workdir/stdmemchr.o" >"$workdir/stdmemchr.out" 2>&1
grep -q 'PASS' "$workdir/stdmemchr.out"

# The exception must stay narrow: memchr arch symbols without a kernel
# marker, avx512 kernel names, and any other crate still fail closed.
if bash "$checker" "$workdir/stdmemchr-nokernel.o" >"$workdir/stdmemchr-nokernel.out" 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted a memchr symbol without a kernel marker." >&2
    exit 1
fi
grep -Eqi 'vmovdqa|avx' "$workdir/stdmemchr-nokernel.out"

if bash "$checker" "$workdir/stdmemchr-avx512.o" >"$workdir/stdmemchr-avx512.out" 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted an avx512 kernel name." >&2
    exit 1
fi
grep -Eqi 'vmovdqa|avx' "$workdir/stdmemchr-avx512.out"

if bash "$checker" "$workdir/othercrate-avx.o" >"$workdir/othercrate-avx.out" 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted AVX outside the memchr arch path." >&2
    exit 1
fi
grep -Eqi 'vmovdqa|avx' "$workdir/othercrate-avx.out"

# The RustCrypto sha2 runtime-dispatched sha256::x86 kernel must be
# accepted: it is entered only behind CPU feature detection and therefore
# cannot execute on qemu64.
bash "$checker" "$workdir/sha2x86.o" >"$workdir/sha2x86.out" 2>&1
grep -q 'PASS' "$workdir/sha2x86.out"

# The exception must stay narrow: sha2 symbols without digest_blocks,
# without a backend marker, and any other crate still fail closed.
if bash "$checker" "$workdir/sha2-nokernel.o" >"$workdir/sha2-nokernel.out" 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted a sha2 symbol without digest_blocks." >&2
    exit 1
fi
grep -Eqi 'pshufb' "$workdir/sha2-nokernel.out"

if bash "$checker" "$workdir/sha2-nobackend.o" >"$workdir/sha2-nobackend.out" 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted sha2 digest_blocks without a backend marker." >&2
    exit 1
fi
grep -Eqi 'pshufb' "$workdir/sha2-nobackend.out"

if bash "$checker" "$workdir/othercrate-shani.o" >"$workdir/othercrate-shani.out" 2>&1; then
    echo "ERROR: qemu64 ISA checker accepted SSSE3 outside the sha2 crate." >&2
    exit 1
fi
grep -Eqi 'pshufb' "$workdir/othercrate-shani.out"

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

echo "PASS: qemu64 ISA checker accepts baseline code, std memchr and sha2 runtime-gated kernels, rejects AVX, BMI, lzcnt, avx512, and non-kernel symbols, persists reports, and supports soft archive attribution."
