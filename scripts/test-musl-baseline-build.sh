#!/usr/bin/env bash
set -euo pipefail

# Network-free regression for the baseline musl source builder:
# a rejected archive must fail closed and install nothing.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BUILDER="${SCRIPT_DIR}/build-musl-baseline.sh"

test -f "${BUILDER}" || { echo "ERROR: build-musl-baseline.sh is missing." >&2; exit 1; }
grep -q 'build-musl-baseline.sh' "${SCRIPT_DIR}/build-busybox-baseline.sh" || {
    echo "ERROR: the BusyBox builder does not invoke the baseline musl builder." >&2
    exit 1
}
grep -E -q '^MUSL_SHA256="[0-9a-f]{64}"$' "${BUILDER}" || {
    echo "ERROR: musl archive SHA-256 pin is missing from the builder." >&2
    exit 1
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aweos-musl-baseline-test.XXXXXX")"
trap 'rm -rf -- "${WORK_DIR}"' EXIT

printf 'not a musl tarball\n' >"${WORK_DIR}/malformed.tar.gz"
if AWEOS_MUSL_ARCHIVE="${WORK_DIR}/malformed.tar.gz" bash "${BUILDER}" "${WORK_DIR}/build" >"${WORK_DIR}/out.log" 2>&1; then
    echo "ERROR: archive rejection did not fail closed." >&2
    exit 1
fi
test ! -e "${WORK_DIR}/build/musl/lib/libc.a" || {
    echo "ERROR: an installation was produced from a rejected archive." >&2
    exit 1
}
grep -q 'SHA-256' "${WORK_DIR}/out.log" || {
    echo "ERROR: archive rejection does not reference checksum verification." >&2
    exit 1
}

stamp_count="$(grep -F -c 'archive-member-scan-v4' "${BUILDER}" || true)"
[ "${stamp_count}" -eq 2 ] || {
    echo "ERROR: musl cache validation and stamp writer must both use archive-member-scan-v4 (found ${stamp_count} occurrences)." >&2
    exit 1
}
if grep -Fq 'archive-member-scan-v3' "${BUILDER}"; then
    echo "ERROR: stale archive-member-scan-v3 cache stamp remains in the musl builder." >&2
    exit 1
fi

echo "PASS: baseline musl builder verifies archive checksums and fails closed."
