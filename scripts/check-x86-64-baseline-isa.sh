#!/usr/bin/env bash
# Targeted guard for the AVX/BMI extensions that previously faulted under qemu64.
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <x86_64-elf>" >&2
    exit 2
fi
binary="$1"
[ -f "$binary" ] || { echo "ERROR: ELF is missing: $binary" >&2; exit 2; }
for tool in readelf objdump awk grep; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is required" >&2; exit 2; }
done

machine="$(readelf -h "$binary" | awk -F: '/Machine:/ {sub(/^[[:space:]]+/, "", $2); print $2}')"
[ "$machine" = "Advanced Micro Devices X86-64" ] || {
    echo "ERROR: expected an x86_64 ELF, got: ${machine:-unknown}" >&2
    exit 1
}

disassembly="$(mktemp "${TMPDIR:-/tmp}/aweos-isa-check.XXXXXX")"
trap 'rm -f -- "$disassembly"' EXIT
if ! objdump -d --no-show-raw-insn "$binary" >"$disassembly"; then
    echo "ERROR: objdump could not disassemble $binary." >&2
    exit 1
fi
if ! grep -Eq '^[[:space:]]*[[:xdigit:]]+:' "$disassembly"; then
    echo "ERROR: objdump produced no instruction lines for $binary." >&2
    exit 1
fi

if awk '
    /^[[:space:]]*[[:xdigit:]]+:/ {
        instruction = $0
        sub(/^[[:space:]]*[[:xdigit:]]+:[[:space:]]*/, "", instruction)
        split(instruction, fields, /[[:space:]]+/)
        mnemonic = fields[1]
        if ((mnemonic ~ /^v[a-z][[:alnum:]]*$/ && mnemonic != "verr" && mnemonic != "verw") ||
            mnemonic ~ /^(andn|bextr|blsi|blsmsk|blsr|lzcnt|mulx|pdep|pext|rorx|sarx|shlx|shrx|tzcnt|popcnt|movbe|crc32|rdrand|rdseed|adcx|adox|aesenc|aesenclast|aesdec|aesdeclast|aesimc|aeskeygenassist|pclmulqdq)$/) {
            # Tagged with ERROR so CI diagnostics steps surface the exact
            # offending instruction as a run-page annotation.
            print "ERROR: Unsupported non-baseline x86-64 instruction: " $0 > "/dev/stderr"
            print "Unsupported non-baseline x86-64 instruction: " $0 > "/dev/stderr"
            found = 1
        }
    }
    END { exit found ? 1 : 0 }
' "$disassembly"; then
    echo "PASS: $binary contains no detected AVX/BMI or listed post-baseline instructions."
else
    echo "ERROR: $binary is not compatible with the guarded x86-64 baseline." >&2
    exit 1
fi
