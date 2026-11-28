#!/usr/bin/env bash
set -euo pipefail

# Build a pinned musl from source with the x86-64 baseline ISA floor.
# Rationale: the distribution's prebuilt musl libc.a is not compiled with AWEOS
# baseline flags, so statically linked BusyBox binaries can inherit VEX/AVX code
# even when every compiler invocation is limited to x86-64-v1. Compiler flags
# cannot restrict already-compiled archive objects; the archive must be rebuilt
# and verified object by object.
BUILD_DIR="${1:-build}"
MUSL_VERSION="1.2.5"
MUSL_SHA256="a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4"
MUSL_URL="https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz"
MUSL_BASELINE_CFLAGS="-march=x86-64 -mtune=generic -mno-avx -mno-avx2 -mno-avx512f -mno-bmi -mno-bmi2 -mno-fma -mno-f16c"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CHECKER="${SCRIPT_DIR}/check-x86-64-baseline-isa.sh"

[ -f "${CHECKER}" ] || { echo "ERROR: baseline ISA checker not found: ${CHECKER}" >&2; exit 2; }

for tool in curl make sha256sum tar ar cc objdump readelf awk grep; do
    command -v "${tool}" >/dev/null 2>&1 || {
        echo "ERROR: required musl source-build tool is missing: ${tool}" >&2
        exit 2
    }
done
mkdir -p "${BUILD_DIR}"
BUILD_DIR_ABS="$(cd -- "${BUILD_DIR}" && pwd -P)"
MUSL_PREFIX="${BUILD_DIR_ABS}/musl"

if [ -f "${MUSL_PREFIX}/lib/libc.a" ] &&
   [ -x "${MUSL_PREFIX}/bin/musl-gcc" ] &&
   grep -Fxq "archive-member-scan-v4" "${MUSL_PREFIX}/baseline-verified" 2>/dev/null; then
    echo "Using cached baseline-verified musl: ${MUSL_PREFIX}"
    exit 0
fi

ARCHIVE="${AWEOS_MUSL_ARCHIVE:-${BUILD_DIR_ABS}/musl-${MUSL_VERSION}.tar.gz}"
if [ -z "${AWEOS_MUSL_ARCHIVE:-}" ] && [ ! -s "${ARCHIVE}" ]; then
    echo "Downloading musl ${MUSL_VERSION} source..."
    curl --fail --location --retry 3 --output "${ARCHIVE}.tmp" "${MUSL_URL}"
    mv "${ARCHIVE}.tmp" "${ARCHIVE}"
fi
if ! printf '%s  %s\n' "${MUSL_SHA256}" "${ARCHIVE}" | sha256sum --check --status; then
    echo "ERROR: musl archive SHA-256 verification failed: ${ARCHIVE}" >&2
    exit 1
fi

WORK_DIR="$(mktemp -d "${BUILD_DIR_ABS}/.musl-build.XXXXXX")"
trap 'rm -rf -- "${WORK_DIR}"' EXIT

tar -xzf "${ARCHIVE}" --directory "${WORK_DIR}" --strip-components=1
(
    cd "${WORK_DIR}"
    ./configure CC=cc CFLAGS="-Os ${MUSL_BASELINE_CFLAGS}" --prefix="${MUSL_PREFIX}" --disable-shared
    make -j"${AWEOS_MUSL_JOBS:-$(nproc)}"
    make install
)

# Fail closed unless the wrapper can build a representative static program.
SMOKE="${WORK_DIR}/smoke.c"
cat >"${SMOKE}" <<'EOF'
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static int cmp_char(const void *a, const void *b) { return *(const char *)a - *(const char *)b; }
int main(void) {
    char buf[64];
    char copy[64];
    snprintf(buf, sizeof buf, "aweos %d", 42);
    memcpy(copy, buf, sizeof copy);
    qsort(copy, 5, 1, cmp_char);
    puts(copy);
    return copy[0] == 'a' ? 0 : 1;
}
EOF
"${MUSL_PREFIX}/bin/musl-gcc" -static -Os ${MUSL_BASELINE_CFLAGS} "${SMOKE}" -o "${WORK_DIR}/smoke.elf"
bash "${CHECKER}" "${WORK_DIR}/smoke.elf"

# Validate the complete installed archive set. musl intentionally ships
# several empty compatibility archives; only the exact upstream allowlist may
# be empty, while every non-empty archive is still scanned object by object.
ARCHIVE_CHECKER="${SCRIPT_DIR}/check-x86-64-baseline-archive.sh"
ARCHIVE_SET_CHECKER="${SCRIPT_DIR}/check-musl-baseline-archives.sh"
[ -f "${ARCHIVE_CHECKER}" ] || {
    echo "ERROR: baseline archive checker not found: ${ARCHIVE_CHECKER}" >&2
    exit 2
}
[ -f "${ARCHIVE_SET_CHECKER}" ] || {
    echo "ERROR: musl archive-set checker not found: ${ARCHIVE_SET_CHECKER}" >&2
    exit 2
}
bash "${ARCHIVE_SET_CHECKER}" "${MUSL_PREFIX}/lib" "${CHECKER}" "${ARCHIVE_CHECKER}"

# Version the stamp so a cache produced by the old suffix-dependent scanner
# cannot be mistaken for a fully verified cache.
printf '%s\n' "archive-member-scan-v4" > "${MUSL_PREFIX}/baseline-verified"
echo "Built and verified musl ${MUSL_VERSION} for the x86-64 baseline: ${MUSL_PREFIX}"
