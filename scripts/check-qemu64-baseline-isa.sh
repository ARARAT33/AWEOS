#!/usr/bin/env bash
# Reject instructions that are not safe for the x86-64 baseline used by
# AWEOS's qemu64 compatibility boot tests. In particular, VEX/EVEX
# instructions (AVX/AVX2/AVX-512) must not leak into PID 1 or other userland.
#
# Optional modes (defaults preserve the original fail-closed behavior):
#   AWEOS_ISA_REPORT_OUT=<path>  persist the full symbol-labeled report file
#                               (exit status is unchanged).
#   AWEOS_ISA_SOFT=1            diagnostic mode that never fails: prints
#   AWEOS_ISA_OFFENDERS=<count> and
#                                AWEOS_ISA_SYMBOLS=<top distinct symbols>, then
#                                exits 0. ar archives are also accepted in
#                                this mode so linked static-library inputs can
#                                be scanned for attribution.
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

report_out="${AWEOS_ISA_REPORT_OUT:-}"
isa_soft="${AWEOS_ISA_SOFT:-0}"
if ! readelf -h "$image" 2>/dev/null | grep -Eqi 'Machine:.*(X86-64|x86-64)'; then
    if [ "$isa_soft" != "1" ]; then
        echo "ERROR: expected an x86-64 ELF for qemu64 ISA verification: $image" >&2
        exit 2
    fi
    # Soft mode may scan ar archives (linked static libraries).
    if ! head -c 8 "$image" | grep -q '^!<arch>'; then
        echo "ERROR: expected an x86-64 ELF or ar archive for qemu64 ISA verification: $image" >&2
        exit 2
    fi
fi

report="$(mktemp "${TMPDIR:-/tmp}/aweos-qemu64-isa.XXXXXX")"
cleanup() {
    if [ -n "$report_out" ]; then
        cp -f -- "$report" "$report_out" 2>/dev/null || true
    fi
    rm -f -- "$report"
}
trap cleanup EXIT

# x86-64-v1/qemu64-safe code must not contain AVX VEX/EVEX mnemonics or
# common post-baseline extensions. verr and verw are legacy instructions,
# not VEX instructions, and are therefore intentionally excluded.
#
# Exception 1 (encoding level): tzcnt is deliberately NOT rejected. Its
# encoding (F3 0F BC, "rep bsf") is the BSF opcode with a rep prefix. On
# CPUs without BMI1, including the qemu64 model used by the boot tests, the
# rep prefix is ignored and the instruction executes as BSF, so it cannot
# #UD there. LLVM emits this encoding for count_trailing_zeros even on the
# x86-64-v1 baseline (including Rust's precompiled std, e.g. backtrace/
# OnceCell code), pairing it with an explicit zero-input check whenever the
# zero result is defined. lzcnt stays rejected to keep the gate narrow.
#
# Exception 2 (runtime dispatch): Rust's precompiled std embeds the memchr
# crate's SIMD kernels (mangled crate path 6memchr4arch6x86_64, e.g.
# memchr::arch::x86_64::memchr::memrchr_raw::find_avx2). These functions are
# compiled with #[target_feature(enable = "avx2")] and are reachable ONLY
# through is_x86_feature_detected! runtime dispatch inside the precompiled
# std. On CPUs without AVX2/SSSE3, including qemu64, the dispatcher never
# enters these kernels, so their instructions cannot #UD there. This code
# lives inside the precompiled std, so no build flag (-C target-cpu,
# RUSTFLAGS, -Z build-std) can remove it; rejecting it would ban every Rust
# userland binary. The exception is narrow: only symbols whose mangled names
# contain BOTH the memchr arch path (6memchr4arch6x86_64) AND an
# avx2/ssse3/sse42 kernel marker. AVX-512 kernels, memchr symbols without a
# kernel marker, every other crate, and all from-source code still fail
# closed. The qemu64 boot test with its instruction trace remains the
# dynamic backstop for this exception.
#
# Exception 3 (runtime dispatch): the RustCrypto sha2 crate embeds
# SHA-256/SHA-512 backend kernels under its mangled crate path (4sha2, e.g.
# sha2::sha256::x86::digest_blocks). These functions are assembled with
# SSSE3/SHA-NI/AVX2 instructions and are reachable ONLY through CPU-feature
# runtime detection (cpufeatures / is_x86_feature_detected!); they live in a
# precompiled dependency, so no build flag can remove them. On CPUs without
# the corresponding feature, including the qemu64 model used by the boot
# tests, the dispatcher never enters these kernels, so their instructions
# cannot #UD there. The exception is narrow: only symbols whose mangled
# names contain the sha2 crate marker (4sha2), a sha256/sha512 digest
# kernel (sha256 or sha512 AND digest_blocks), AND a backend marker
# (3x86, 4shani, or avx2). sha2 symbols without a kernel/backend marker,
# other crates, and all from-source code still fail closed. The qemu64 boot
# test with its instruction trace remains the dynamic backstop.
objdump -d -Mintel "$image" | awk '
/^[[:space:]]*[[:xdigit:]]+[[:space:]]+<[^>]+>:/ {
    current_symbol = $0
    next
}
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
    if (current_symbol ~ /6memchr4arch6x86_64/ &&
        current_symbol ~ /(avx2|ssse3|sse42)/) {
        next
    }
    if (current_symbol ~ /4sha2/ && current_symbol ~ /(sha256|sha512)/ &&
        current_symbol ~ /digest_blocks/ &&
        current_symbol ~ /(3x86|4shani|avx2)/) {
        next
    }
    if ((mnemonic ~ /^v/ && mnemonic != "verr" && mnemonic != "verw") ||
        mnemonic ~ /^(andn|bextr|blsi|blsmsk|blsr|bzhi|mulx|pdep|pext|rorx|sarx|shlx|shrx|popcnt|lzcnt|movbe|crc32|adcx|adox|rdrand|rdseed|clflushopt|clwb|addsubpd|addsubps|haddpd|haddps|hsubpd|hsubps|lddqu|movddup|movshdup|movsldup|pabsb|pabsw|pabsd|palignr|phaddw|phaddd|phaddsw|phsubw|phsubd|phsubsw|pmaddubsw|pmulhrsw|pshufb|psignb|psignw|psignd|blendpd|blendps|blendvpd|blendvps|dpps|dppd|extractps|insertps|movntdqa|mpsadbw|packusdw|pblendvb|pblendw|pcmpeqq|pinsrb|pinsrd|pinsrq|pmovsxbw|pmovsxbd|pmovsxbq|pmovsxwd|pmovsxwq|pmovsxdq|pmovzxbw|pmovzxbd|pmovzxbq|pmovzxwd|pmovzxwq|pmovzxdq|pmulld|ptest|roundsd|roundss|roundpd|roundps|pcmpestri|pcmpestrm|pcmpistri|pcmpistrm|pcmpgtq)$/) {
        if (current_symbol != last_symbol && current_symbol != "") {
            print current_symbol
            last_symbol = current_symbol
        }
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
    # Name the top offending symbols on the same first error line so the
    # single-line CI annotation identifies the actual functions.
    symbols="$(awk '
        /^[[:space:]]*[[:xdigit:]]+[[:space:]]+<[^>]+>:/ {
            name = $2
            gsub(/[<>:]/, "", name)
            if (!(name in seen)) {
                seen[name] = 1
                printf "%s%s", sep, name
                sep = ", "
                if (++n >= 6) {
                    exit
                }
            }
        }' "$report")"
    if [ "$isa_soft" = "1" ]; then
        offenders="$(awk '/^[[:space:]]*[[:xdigit:]]+:/ { n++ } END { print n + 0 }' "$report")"
        echo "AWEOS_ISA_OFFENDERS=$offenders"
        echo "AWEOS_ISA_SYMBOLS=$symbols"
        exit 0
    fi
    echo "ERROR: $image contains instructions outside the AWEOS qemu64/x86-64 baseline (mnemonics: $summary; symbols: $symbols):" >&2
    sed -n '1,30p' "$report" >&2
    echo "Refusing to package this ELF; rebuild it with an explicit x86-64 baseline target." >&2
    exit 1
fi

if [ "$isa_soft" = "1" ]; then
    echo "AWEOS_ISA_OFFENDERS=0"
    echo "AWEOS_ISA_SYMBOLS="
    exit 0
fi

echo "PASS: $image contains no detected AVX/AVX2/AVX-512, BMI, or post-baseline SIMD instructions."
