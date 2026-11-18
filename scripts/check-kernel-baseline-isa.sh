#!/usr/bin/env bash
# Reject BMI1/BMI2 instructions in the x86_64 compressed kernel. This image
# executes before normal CPU feature alternatives are initialized and must
# remain compatible with the x86_64 baseline (including QEMU's qemu64 model).
set -euo pipefail

image="${1:-}"
if [ -z "$image" ]; then
    echo "usage: $0 <compressed-vmlinux>" >&2
    exit 2
fi
if [ ! -s "$image" ]; then
    echo "ERROR: compressed kernel ELF is missing or empty: $image" >&2
    exit 2
fi
if ! command -v objdump >/dev/null 2>&1; then
    echo "ERROR: objdump is required to verify the compressed-kernel ISA baseline." >&2
    exit 2
fi

# BMI1/BMI2 instructions are not part of the x86-64 baseline. In particular,
# SHRX/SHLX/BZHI/RORX caused the qemu64 Limine boot #UD observed in CI.
unsupported='andn|bextr|blsi|blsmsk|blsr|shlx|shrx|sarx|bzhi|mulx|rorx|pdep|pext'
report="$(mktemp "${TMPDIR:-/tmp}/aweos-kernel-isa.XXXXXX")"
trap 'rm -f -- "$report"' EXIT

if objdump -d -Mintel "$image" | grep -Ei "^[[:space:]]*[[:xdigit:]]+:[[:space:]]+([[:xdigit:]]{2}[[:space:]]+)+(${unsupported})[[:space:]]" >"$report"; then
    echo "ERROR: compressed kernel contains BMI1/BMI2 instructions unsupported by the x86-64 baseline:" >&2
    sed -n '1,20p' "$report" >&2
    echo "Refusing to publish this boot image; inspect compiler flags for the compressed-kernel objects." >&2
    exit 1
fi

echo "PASS: compressed kernel uses no BMI1/BMI2 instructions (x86-64 baseline)."
