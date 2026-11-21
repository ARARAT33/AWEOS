#!/usr/bin/env bash
# Regression guard: the BusyBox baseline build must explicitly disable the
# tc (traffic-control) applet. Its source depends on the CBQ qdisc ABI that
# modern kernels removed, so networking/tc.o fails to compile against the
# freshly installed UAPI headers with musl (GitHub Actions run 44868882500,
# "make[2]: *** [scripts/Makefile.build:197: networking/tc.o] Error 1").
# Without this guard the defconfig default CONFIG_TC=y would re-enable the
# failing applet on every rebuild from a clean tree.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BUILDER="${SCRIPT_DIR}/build-busybox-baseline.sh"

[[ -f "${BUILDER}" ]] || { echo "ERROR: builder script missing: ${BUILDER}" >&2; exit 1; }

grep -Eq "^[[:space:]]*set_config CONFIG_TC n[[:space:]]*$" "${BUILDER}" || {
    echo "ERROR: build-busybox-baseline.sh does not explicitly disable CONFIG_TC." >&2
    exit 1
}

# The disable must be documented with its root cause so the reason survives
# future refactors and defconfig refreshes.
grep -q "CBQ qdisc ABI" "${BUILDER}" || {
    echo "ERROR: the tc applet disable is not documented with its root cause." >&2
    exit 1
}

echo "PASS: BusyBox baseline build disables the tc applet with its root cause documented."
