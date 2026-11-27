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

header="$(readelf -h "$binary")" || {
    echo "ERROR: readelf could not inspect $binary." >&2
    exit 1
}
machine="$(printf '%s\n' "$header" | awk -F: '/Machine:/ {sub(/^[[:space:]]+/, "", $2); print $2}')"
[ "$machine" = "Advanced Micro Devices X86-64" ] || {
    echo "ERROR: expected an x86_64 ELF, got: ${machine:-unknown}" >&2
    exit 1
}
elf_type="$(printf '%s\n' "$header" | awk -F: '/Type:/ {sub(/^[[:space:]]+/, "", $2); split($2, fields, /[[:space:]]+/); print fields[1]; exit}')"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/aweos-isa-check.XXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT
disassembly="$work_dir/disassembly"
if ! objdump -d --no-show-raw-insn "$binary" >"$disassembly"; then
    echo "ERROR: objdump could not disassemble $binary." >&2
    exit 1
fi
if ! grep -Eq '^[[:space:]]*[[:xdigit:]]+:' "$disassembly"; then
    # Static archives legitimately contain data-only relocatable objects (for
    # example musl's __environ.lo). They are safe only when the ELF is ET_REL
    # and has no non-empty executable section. A malformed object or a final
    # executable with no disassembly must still fail closed.
    if [ "$elf_type" != "REL" ]; then
        echo "ERROR: objdump produced no instruction lines for non-relocatable ELF type ${elf_type:-unknown}: $binary." >&2
        exit 1
    fi

    sections="$work_dir/sections"
    if ! readelf -SW "$binary" >"$sections"; then
        echo "ERROR: readelf could not inspect section headers for $binary." >&2
        exit 1
    fi
    if awk '
        /^[[:space:]]*\[[[:space:]]*[0-9]+\]/ {
            line = $0
            sub(/^[[:space:]]*\[[[:space:]]*[0-9]+\][[:space:]]*/, "", line)
            split(line, fields, /[[:space:]]+/)
            size = fields[5]
            flags = fields[7]
            if (flags ~ /X/ && size !~ /^0+$/) found = 1
        }
        END { exit found ? 0 : 1 }
    ' "$sections"; then
        echo "ERROR: objdump produced no instruction lines for an ELF with non-empty executable sections: $binary." >&2
        exit 1
    fi

    echo "PASS: $binary is a data-only x86-64 relocatable ELF with no non-empty executable sections."
    exit 0
fi

if awk '
    /^[[:space:]]*[[:xdigit:]]+:/ {
        if ($0 ~ /^[[:space:]]*[[:xdigit:]]+ </) {
            sym = $0
            sub(/[^<]*</, "", sym)
            sub(/>[[:space:]]*:.*$/, "", sym)
        }
        instruction = $0
        sub(/^[[:space:]]*[[:xdigit:]]+:[[:space:]]*/, "", instruction)
        split(instruction, fields, /[[:space:]]+/)
        mnemonic = fields[1]
        if ((mnemonic ~ /^v[a-z][[:alnum:]]*$/ && mnemonic != "verr" && mnemonic != "verw") ||
            mnemonic ~ /^(andn|bextr|blsi|blsmsk|blsr|lzcnt|mulx|pdep|pext|rorx|sarx|shlx|shrx|tzcnt|popcnt|movbe|crc32|rdrand|rdseed|adcx|adox|aesenc|aesenclast|aesdec|aesdeclast|aesimc|aeskeygenassist|pclmulqdq)$/) {
            # Tagged with ERROR so CI diagnostics steps surface the exact
            # offending instruction as a run-page annotation.
            print "ERROR: Unsupported non-baseline x86-64 instruction near symbol <" (sym ? sym : "?") ">: " $0 > "/dev/stderr"
            print "Unsupported non-baseline x86-64 instruction near symbol: " $0 > "/dev/stderr"
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
