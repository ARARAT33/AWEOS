#!/usr/bin/env bash
# Enforce AWEOS's x86-64-v1 compiler policy after all build-system flags.
# BusyBox may append CFLAGS after CC; putting policy flags here makes them win.
set -euo pipefail

compiler="${AWEOS_MUSL_CC:-musl-gcc}"
if ! command -v "$compiler" >/dev/null 2>&1; then
    echo "ERROR: baseline C compiler is unavailable: $compiler" >&2
    exit 2
fi

baseline_flags=(
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
)

exec "$compiler" "$@" "${baseline_flags[@]}"
