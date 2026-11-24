#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CHECKER="${SCRIPT_DIR}/check-x86-64-baseline-isa.sh"
command -v cc >/dev/null 2>&1 || { echo "ERROR: cc is required." >&2; exit 2; }
command -v objdump >/dev/null 2>&1 || { echo "ERROR: objdump is required." >&2; exit 2; }
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aweos-user-isa-test.XXXXXX")"
trap 'rm -rf -- "${WORK_DIR}"' EXIT

cat >"${WORK_DIR}/baseline.S" <<'ASM'
.text
.globl _start
_start:
    nop
    ret
ASM
cat >"${WORK_DIR}/avx.S" <<'ASM'
.text
.globl _start
_start:
    vmovdqa %xmm0, %xmm1
    ret
ASM
cat >"${WORK_DIR}/bmi.S" <<'ASM'
.text
.globl _start
_start:
    andn %eax, %ebx, %ecx
    ret
ASM

cc -nostdlib -no-pie -Wl,-e,_start "${WORK_DIR}/baseline.S" -o "${WORK_DIR}/baseline.elf"
cc -nostdlib -no-pie -mavx -Wl,-e,_start "${WORK_DIR}/avx.S" -o "${WORK_DIR}/avx.elf"
cc -nostdlib -no-pie -mbmi -Wl,-e,_start "${WORK_DIR}/bmi.S" -o "${WORK_DIR}/bmi.elf"
printf 'not an ELF file\n' >"${WORK_DIR}/invalid.elf"

bash "${CHECKER}" "${WORK_DIR}/baseline.elf"
for unsafe in avx bmi invalid; do
    if bash "${CHECKER}" "${WORK_DIR}/${unsafe}.elf" >"${WORK_DIR}/${unsafe}.out" 2>&1; then
        echo "ERROR: ISA checker accepted ${unsafe} fixture." >&2
        exit 1
    fi
done
grep -q 'vmovdqa' "${WORK_DIR}/avx.out"
grep -q 'near symbol' "${WORK_DIR}/avx.out"
grep -q 'andn' "${WORK_DIR}/bmi.out"

echo "PASS: userland ISA checker accepts baseline code and rejects AVX, BMI and invalid ELF fixtures."
