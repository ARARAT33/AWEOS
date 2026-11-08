#!/usr/bin/env bash
# Reject instructions that are not safe for the x86-64 baseline used by
# AWEOS's qemu64 compatibility boot tests. In particular, VEX/EVEX
# instructions (AVX/AVX2/AVX-512) must not leak into PID 1 or other userland.
set -euo pipefail

image="${1:-}"
if [ -z "$image" ]; then
    echo "usage: $0 <x86_64-elf>" >&2
    exit 2
fi
if [ ! -s "$image" ]; then
    echo "ERROR: ELF is missing or empty: $image" >&2
    exit 2
fi
for tool in readelf objdump awk; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: $tool is required for qemu64 ISA verification." >&2
        exit 2
    }
done

if ! readelf -h "$image" 2>/dev/null | grep -Eqi 'Machine:.*(X86-64|x86-64)'; then
    echo "ERROR: expected an x86-64 ELF for qemu64 ISA verification: $image" >&2
    exit 2
fi

report="$(mktemp "${TMPDIR:-/tmp}/aweos-qemu64-isa.XXXXXX")"
trap 'rm -f -- "$report"' EXIT

# x86-64-v1/qemu64-safe code must not contain AVX VEX/EVEX mnemonics or
# common post-baseline extensions. verr and verw are legacy instructions,
# not VEX instructions, and are therefore intentionally excluded.
objdump -d -Mintel "$image" | awk '
/^[[:space:]]*[[:xdigit:]]+:/ {
    line = $0
    sub(/^[[:space:]]*[[:xdigit:]]+:[[:space:]]*/, "", line)
    count = split(line, fields, /[[:space:]]+/)
    i = 1
    while (i <= count && length(fields[i]) == 2 &&
           fields[i] ~ /^[[:xdigit:]][[:xdigit:]]$/) {
        i++
    }
    mnemonic = tolower(fields[i])
    if ((mnemonic ~ /^v/ && mnemonic != "verr" && mnemonic != "verw") ||
        mnemonic ~ /^(andn|bextr|blsi|blsmsk|blsr|bzhi|mulx|pdep|pext|rorx|sarx|shlx|shrx|tzcnt|popcnt|lzcnt|movbe|crc32|adcx|adox|rdrand|rdseed|clflushopt|clwb|addsubpd|addsubps|haddpd|haddps|hsubpd|hsubps|lddqu|movddup|movshdup|movsldup|pabsb|pabsw|pabsd|palignr|phaddw|phaddd|phaddsw|phsubw|phsubd|phsubsw|pmaddubsw|pmulhrsw|pshufb|psignb|psignw|psignd|blendpd|blendps|blendvpd|blendvps|dpps|dppd|extractps|insertps|movntdqa|mpsadbw|packusdw|pblendvb|pblendw|pcmpeqq|pinsrb|pinsrd|pinsrq|pmovsxbw|pmovsxbd|pmovsxbq|pmovsxwd|pmovsxwq|pmovsxdq|pmovzxbw|pmovzxbd|pmovzxbq|pmovzxwd|pmovzxwq|pmovzxdq|pmulld|ptest|roundsd|roundss|roundpd|roundps|pcmpestri|pcmpestrm|pcmpistri|pcmpistrm|pcmpgtq)$/) {
        print $0
    }
}' > "$report"

if [ -s "$report" ]; then
    # Compact mnemonic histogram on the first error line so the failure is
    # diagnosable from a single-line CI annotation without downloading logs.
    summary="$(awk '
        /^[[:space:]]*[[:xdigit:]]+:/ {
            line = $0
            sub(/^[[:space:]]*[[:xdigit:]]+:[[:space:]]*/, "", line)
            count = split(line, fields, /[[:space:]]+/)
            i = 1
            while (i <= count && length(fields[i]) == 2 &&
                   fields[i] ~ /^[[:xdigit:]][[:xdigit:]]$/) {
                i++
            }
            counts[tolower(fields[i])]++
        }
        END {
            shown = 0
            sep = ""
            for (m in counts) {
                printf "%s%s(%d)", sep, m, counts[m]
                sep = ", "
                if (++shown >= 20) {
                    break
                }
            }
        }' "$report")"
    echo "ERROR: $image contains instructions outside the AWEOS qemu64/x86-64 baseline (mnemonics: $summary):" >&2
    sed -n '1,30p' "$report" >&2
    echo "Refusing to package this ELF; rebuild it with an explicit x86-64 baseline target." >&2
    exit 1
fi

echo "PASS: $image contains no detected AVX/AVX2/AVX-512, BMI, or post-baseline SIMD instructions."
