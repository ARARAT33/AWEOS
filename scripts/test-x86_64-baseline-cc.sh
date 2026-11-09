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

echo "PASS: x86-64 baseline compiler policy is last, deterministic, and fail-closed."
