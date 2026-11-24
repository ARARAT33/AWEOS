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
cc_setting=""
for argument in "$@"; do
    case "${argument}" in CC=*) cc_setting="${argument#CC=}" ;; esac
done
if [[ -n "${cc_setting}" ]]; then
    printf "%s\\n" "${cc_setting}" > "${AWEOS_TEST_TRACE}/compiler-command"
fi
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
        # Match the upstream BusyBox defconfig representation of a disabled
        # setting; the builder must rewrite this row in place, not append a
        # duplicate assignment whose resolution is left to kconfig.
        printf '# CONFIG_STATIC is not set\nCONFIG_EXTRA_CFLAGS=""\nCONFIG_SHA256_HWACCEL=y\n' > .config
        ;;
    oldconfig)
        rows="$(grep -Ec '^CONFIG_STATIC=y$' .config || true)"
        total="$(grep -Ec '^CONFIG_STATIC' .config || true)"
        printf '%s %s\n' "${rows}" "${total}" > "${AWEOS_TEST_TRACE}/static-config-rows"
        [[ "${rows}" == "1" ]] || {
            echo "ERROR: exactly one CONFIG_STATIC=y row expected after the rewrite, got rows=${rows} total=${total}" >&2
            grep -n "CONFIG_STATIC" .config >&2
            exit 23
        }
        hw_enable_rows="$(grep -Ec '^CONFIG_SHA256_HWACCEL=y$' .config || true)"
        hw_disable_rows="$(grep -Ec '^CONFIG_SHA256_HWACCEL=n$' .config || true)"
        [[ "${hw_enable_rows}" == "0" && "${hw_disable_rows}" == "1" ]] || {
            echo "ERROR: SHA-256 hardware acceleration must be disabled for the x86-64 baseline: enable_rows=${hw_enable_rows} disable_rows=${hw_disable_rows}" >&2
            grep -n "CONFIG_SHA256_HWACCEL" .config >&2 || true
            exit 24
        }
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
        link_flags="-nostdlib -no-pie -Wl,-e,_start"
        if [[ -f "${AWEOS_TEST_TRACE}/fake-dynamic" ]]; then
            link_flags="-nostdlib -no-pie -Wl,-e,_start -Wl,--dynamic-linker=/lib/ld-musl-x86_64.so.1"
        fi
        cc ${link_flags} baseline.S -o busybox
        ;;
esac
MAKE

cat > "${FAKE_BIN}/readelf" <<'RE'
#!/usr/bin/env bash
set -euo pipefail
# check-x86-64-baseline-isa.sh calls readelf -h; answer with a baseline
# x86-64 machine line and only fake the -l program-header listing.
case " $* " in
    *" -h "*)
        printf 'Machine:  Advanced Micro Devices X86-64\n'
        exit 0
        ;;
esac
if [[ " $* " != *" -l "* ]] && [[ " $* " != *" -l"* ]]; then
    echo "unexpected readelf invocation: $*" >&2
    exit 40
fi
if [[ -f "${AWEOS_TEST_TRACE}/fake-dynamic" ]]; then
    printf 'Program Headers:\n  INTERP     0x0000000000000318 Rx8  /lib/ld-musl-x86_64.so.1\n'
else
    printf 'Program Headers:\n  LOAD       0x0000000000000000 RWE 0x8\n'
fi
RE

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

chmod 0755 "${FAKE_BIN}/make" "${FAKE_BIN}/curl" "${FAKE_BIN}/sha256sum" "${FAKE_BIN}/tar" "${FAKE_BIN}/musl-gcc" "${FAKE_BIN}/readelf"

# The harness tests BusyBox configuration and fail-closed ELF checks, not a real musl build.
# Use the supported compiler override so the fake toolchain stays network-free;
# test-musl-baseline-build.sh separately verifies the pinned musl builder wiring.
export AWEOS_TEST_TRACE="${TRACE_DIR}"
export AWEOS_TEST_EXPECTED_HEADERS="${BUILD_DIR}/linux-headers"
(
    cd "${TEMP_ROOT}"
    env -u AWEOS_LINUX_SRC \
        AWEOS_BUSYBOX_CC="${FAKE_BIN}/musl-gcc" \
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
grep -Fq -- "-march=x86-64" "${TRACE_DIR}/compiler-command"
grep -Fq -- "-mno-avx" "${TRACE_DIR}/compiler-command"
grep -Fq -- "-mno-bmi2" "${TRACE_DIR}/compiler-command"
! grep -Fq -- "-march=native" "${TRACE_DIR}/compiler-command"
[[ "$(cat "${TRACE_DIR}/static-config-rows")" == "1 1" ]] || {
    echo "ERROR: expected exactly one CONFIG_STATIC=y row in the rewritten .config, got: $(cat "${TRACE_DIR}/static-config-rows")" >&2
    exit 1
}
[[ -x "${BUILD_DIR}/busybox" ]]

# Negative case: reproduce the CI failure mode where the binary links with an
# interpreter. The builder must fail closed with diagnostics instead of
# shipping a dynamic BusyBox for the initramfs.
NEGATIVE_DIR="${TEMP_ROOT}/out-dynamic"
mkdir -p "${NEGATIVE_DIR}"
touch "${TRACE_DIR}/fake-dynamic"
set +e
(
    cd "${TEMP_ROOT}"
    env -u AWEOS_LINUX_SRC \
        AWEOS_BUSYBOX_CC="${FAKE_BIN}/musl-gcc" \
        PATH="${FAKE_BIN}:${PATH}" \
        AWEOS_TEST_TRACE="${TRACE_DIR}" \
        AWEOS_TEST_EXPECTED_HEADERS="${NEGATIVE_DIR}/linux-headers" \
        bash "${FAKE_REPO}/scripts/build-busybox-baseline.sh" "${NEGATIVE_DIR}"
) > "${TRACE_DIR}/negative-stdout" 2> "${TRACE_DIR}/negative-stderr"
negative_status=$?
set -e
rm -f "${TRACE_DIR}/fake-dynamic"
[[ "${negative_status}" -ne 0 ]] || {
    echo "ERROR: dynamic BusyBox output was accepted by the static-link check." >&2
    exit 1
}
grep -q "must be statically linked" "${TRACE_DIR}/negative-stderr" || {
    echo "ERROR: static-link failure diagnostics were not emitted." >&2
    exit 1
}
grep -q "readelf program headers" "${TRACE_DIR}/negative-stderr" || {
    echo "ERROR: readelf diagnostic output missing on static-link failure." >&2
    exit 1
}

echo "PASS: BusyBox build resolves the repository kernel tree, keeps headers out-of-tree, expands compiler flags, keeps exactly one CONFIG_STATIC=y row, validates a static x86-64 baseline ELF, and fails closed on dynamic output."

