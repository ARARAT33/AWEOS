#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
WRAPPER="$SCRIPT_DIR/cc-x86_64-baseline.sh"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aweos-baseline-cc-test.XXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

FAKE_CC="$TEMP_ROOT/fake-cc"
CAPTURE="$TEMP_ROOT/arguments.txt"
EXPECTED="$TEMP_ROOT/expected.txt"
ACTUAL="$TEMP_ROOT/actual.txt"

cat > "$FAKE_CC" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${AWEOS_TEST_CC_ARGS:?test argument capture path is required}"
printf '%s\n' "$@" > "$AWEOS_TEST_CC_ARGS"
exit "${AWEOS_TEST_CC_EXIT:-0}"
EOF
chmod 0755 "$FAKE_CC"

# Simulate hostile/later build flags. The AWEOS policy must be the final
# compiler options, not merely an earlier -march value inside CC.
AWEOS_MUSL_CC="$FAKE_CC" \
AWEOS_TEST_CC_ARGS="$CAPTURE" \
    bash "$WRAPPER" -O2 -march=native -mavx2 -mbmi2 -c fixture.c

grep -Fxq -- '-march=native' "$CAPTURE"
grep -Fxq -- '-mavx2' "$CAPTURE"
grep -Fxq -- '-mbmi2' "$CAPTURE"

cat > "$EXPECTED" <<'EOF'
-march=x86-64
-mtune=generic
-mno-avx
-mno-avx2
-mno-avx512f
-mno-bmi
-mno-bmi2
-mno-movbe
-mno-popcnt
-mno-lzcnt
-mno-sse3
-mno-ssse3
-mno-sse4.1
-mno-sse4.2
-mno-aes
-mno-pclmul
-mno-rdrnd
-mno-rdseed
-mno-adx
EOF
tail -n "$(wc -l < "$EXPECTED")" "$CAPTURE" > "$ACTUAL"
cmp -s "$EXPECTED" "$ACTUAL" || {
    echo "ERROR: x86-64 baseline flags are not the final compiler options." >&2
    diff -u "$EXPECTED" "$ACTUAL" >&2 || true
    exit 1
}

# The wrapper must preserve the real compiler's failure status.
if AWEOS_MUSL_CC="$FAKE_CC" \
   AWEOS_TEST_CC_ARGS="$CAPTURE" \
   AWEOS_TEST_CC_EXIT=23 \
       bash "$WRAPPER" -c fixture.c; then
    echo "ERROR: compiler failure was hidden by the baseline wrapper." >&2
    exit 1
else
    status=$?
    [[ "$status" -eq 23 ]] || {
        echo "ERROR: expected compiler exit 23, received $status." >&2
        exit 1
    }
fi

# Missing compilers must fail closed with a non-zero status.
if AWEOS_MUSL_CC="$TEMP_ROOT/missing-compiler" bash "$WRAPPER" -c fixture.c; then
    echo "ERROR: wrapper accepted a missing compiler." >&2
    exit 1
fi

# Exercise the policy with a real compiler when the musl toolchain is present.
# The hostile flags deliberately request host-native AVX/BMI code; the wrapper
# must still produce an object accepted by the qemu64 ISA scanner.
REAL_CC="${AWEOS_TEST_REAL_CC:-musl-gcc}"
if command -v "$REAL_CC" >/dev/null 2>&1; then
    PROBE_SOURCE="$TEMP_ROOT/baseline-probe.c"
    PROBE_OBJECT="$TEMP_ROOT/baseline-probe.o"
    TARGET_REPORT="$TEMP_ROOT/target-report.txt"

    cat > "$PROBE_SOURCE" <<'EOF'
#include <stddef.h>
#include <stdint.h>

__attribute__((noinline))
uint64_t aweos_baseline_probe(const uint64_t *src, uint64_t *dst, size_t n)
{
    uint64_t sum = 0;
    for (size_t i = 0; i < n; ++i) {
        uint64_t value = src[i];
        dst[i] = (value * UINT64_C(0x9e3779b185ebca87)) ^ (value >> 13);
        sum ^= dst[i];
        if (value != 0)
            sum ^= (uint64_t)__builtin_ctzll(value);
    }
    return sum;
}
EOF

    AWEOS_MUSL_CC="$REAL_CC" bash "$WRAPPER" \
        -O3 -march=native -mavx2 -mbmi2 \
        -c "$PROBE_SOURCE" -o "$PROBE_OBJECT"
    bash "$SCRIPT_DIR/check-qemu64-baseline-isa.sh" "$PROBE_OBJECT"

    AWEOS_MUSL_CC="$REAL_CC" bash "$WRAPPER" -Q --help=target > "$TARGET_REPORT"
    for option in -mavx -mavx2 -mavx512f -mbmi -mbmi2 -mmovbe \
                  -mpopcnt -mlzcnt -msse3 -mssse3 -msse4.1 -msse4.2 \
                  -maes -mpclmul -mrdrnd -mrdseed -madx; do
        if ! awk -v wanted="$option" \
            '$1 == wanted && $2 == "[disabled]" { found = 1 } END { exit !found }' \
            "$TARGET_REPORT"; then
            echo "ERROR: real compiler did not disable $option under the AWEOS baseline." >&2
            grep -E "^[[:space:]]*$option[[:space:]]" "$TARGET_REPORT" >&2 || true
            exit 1
        fi
    done
    awk '$1 == "-msse2" && $2 == "[enabled]" { found = 1 } END { exit !found }' \
        "$TARGET_REPORT" || {
        echo "ERROR: real compiler unexpectedly disabled the x86-64 baseline SSE2 feature." >&2
        exit 1
    }
    echo "PASS: real compiler output and effective target options satisfy the x86-64 baseline."
else
    echo "SKIP: real compiler baseline probe; $REAL_CC is not installed in this test environment."
fi

echo "PASS: x86-64 baseline compiler policy is last, deterministic, and fail-closed."
