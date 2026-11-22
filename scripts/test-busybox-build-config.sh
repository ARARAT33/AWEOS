#!/usr/bin/env bash
# Exercise BusyBox build preflight and compiler configuration without network access.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aweos-busybox-config-test.XXXXXX")"
trap 'rm -rf -- "${TEMP_ROOT}"' EXIT

FAKE_REPO="${TEMP_ROOT}/repo"
FAKE_BIN="${TEMP_ROOT}/fake-bin"
TRACE_DIR="${TEMP_ROOT}/trace"
BUILD_DIR="${TEMP_ROOT}/out"
mkdir -p "${FAKE_REPO}/scripts" "${FAKE_REPO}/linux" "${FAKE_BIN}" "${TRACE_DIR}" "${BUILD_DIR}"
cp "${SCRIPT_DIR}/build-busybox-baseline.sh" "${FAKE_REPO}/scripts/"
cp "${SCRIPT_DIR}/check-x86-64-baseline-isa.sh" "${FAKE_REPO}/scripts/"
: > "${FAKE_REPO}/linux/Makefile"

cat > "${FAKE_BIN}/make" <<'MAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *" headers_install "* ]]; then
    source_dir=""
    output_dir=""
    previous=""
    for argument in "$@"; do
        if [[ "${previous}" == "-C" ]]; then source_dir="${argument}"; fi
        case "${argument}" in O=*) output_dir="${argument#O=}";; esac
        previous="${argument}"
    done
    [[ -f "${source_dir}/Makefile" ]] || { echo "missing kernel Makefile: ${source_dir}" >&2; exit 20; }
    mkdir -p "${output_dir}/usr/include/linux"
    printf '/* test kernel header */\n' > "${output_dir}/usr/include/linux/kd.h"
    printf '%s\n' "${source_dir}" > "${AWEOS_TEST_TRACE}/kernel-source"
    printf '%s\n' "${output_dir}" > "${AWEOS_TEST_TRACE}/headers-output"
    exit 0
fi

case "${1:-}" in
    defconfig)
        printf 'CONFIG_STATIC=n\nCONFIG_EXTRA_CFLAGS=""\n' > .config
        ;;
    oldconfig)
        :
        ;;
    *)
        flags="$(sed -n 's/^CONFIG_EXTRA_CFLAGS=//p' .config)"
        [[ "${flags}" == *"-I${AWEOS_TEST_EXPECTED_HEADERS}/usr/include"* ]] || {
            echo "ERROR: kernel include path was not expanded in CONFIG_EXTRA_CFLAGS: ${flags}" >&2
            exit 21
        }
        [[ "${flags}" != *'${KERNEL_HEADERS_ABS}'* ]] || {
            echo "ERROR: CONFIG_EXTRA_CFLAGS contains an unexpanded shell variable." >&2
            exit 22
        }
        printf '%s\n' "${flags}" > "${AWEOS_TEST_TRACE}/config-flags"
        cat > baseline.S <<'ASM'
.text
.global _start
_start:
    xor %edi,%edi
    mov $60,%eax
    syscall
ASM
        cc -nostdlib -no-pie -Wl,-e,_start baseline.S -o busybox
        ;;
esac
MAKE

cat > "${FAKE_BIN}/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
output=""
previous=""
for argument in "$@"; do
    if [[ "${previous}" == "--output" ]]; then output="${argument}"; fi
    previous="${argument}"
done
[[ -n "${output}" ]] || { echo "curl fixture did not receive --output" >&2; exit 30; }
: > "${output}"
CURL

cat > "${FAKE_BIN}/sha256sum" <<'SHA'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *" --check "* ]]; then
    cat >/dev/null
    exit 0
fi
echo "unexpected sha256sum invocation in fixture" >&2
exit 31
SHA

cat > "${FAKE_BIN}/tar" <<'TAR'
#!/usr/bin/env bash
set -euo pipefail
# The fake make command creates a minimal baseline ELF in the extraction directory.
TAR

cat > "${FAKE_BIN}/musl-gcc" <<'MUSL'
#!/usr/bin/env bash
exec cc "$@"
MUSL

chmod 0755 "${FAKE_BIN}/make" "${FAKE_BIN}/curl" "${FAKE_BIN}/sha256sum" "${FAKE_BIN}/tar" "${FAKE_BIN}/musl-gcc"

export AWEOS_TEST_TRACE="${TRACE_DIR}"
export AWEOS_TEST_EXPECTED_HEADERS="${BUILD_DIR}/linux-headers"
(
    cd "${TEMP_ROOT}"
    env -u AWEOS_LINUX_SRC \
        PATH="${FAKE_BIN}:${PATH}" \
        AWEOS_TEST_TRACE="${TRACE_DIR}" \
        AWEOS_TEST_EXPECTED_HEADERS="${BUILD_DIR}/linux-headers" \
        bash "${FAKE_REPO}/scripts/build-busybox-baseline.sh" "${BUILD_DIR}"
)

[[ "$(cat "${TRACE_DIR}/kernel-source")" == "${FAKE_REPO}/linux" ]] || {
    echo "ERROR: default kernel source was not resolved relative to the script's repository." >&2
    exit 1
}
[[ "$(cat "${TRACE_DIR}/headers-output")" == "${BUILD_DIR}/linux-headers" ]] || {
    echo "ERROR: kernel headers were not generated in the build directory." >&2
    exit 1
}
grep -Fq -- "-I${BUILD_DIR}/linux-headers/usr/include" "${TRACE_DIR}/config-flags"
! grep -Fq -- '${KERNEL_HEADERS_ABS}' "${TRACE_DIR}/config-flags"
[[ -x "${BUILD_DIR}/busybox" ]]

echo "PASS: BusyBox build resolves the repository kernel tree, keeps headers out-of-tree, expands compiler flags, and validates a static x86-64 baseline ELF."
