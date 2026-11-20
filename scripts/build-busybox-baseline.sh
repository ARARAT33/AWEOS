#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-build}"
BUSYBOX_VERSION="1.38.0"
BUSYBOX_SHA256="34f9ea6ff8636f2c9241153b9114eefa9e65674a45318ae1ef95bb5f31c53bb2"
BUSYBOX_URL="https://www.busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"
ARCHIVE="${BUILD_DIR}/busybox-${BUSYBOX_VERSION}.tar.bz2"
OUTPUT="${BUILD_DIR}/busybox"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

for tool in curl make musl-gcc sha256sum tar readelf; do
    command -v "${tool}" >/dev/null 2>&1 || {
        echo "ERROR: required BusyBox build tool is missing: ${tool}" >&2
        exit 2
    }
done
mkdir -p "${BUILD_DIR}"

# BusyBox tools such as kbd_mode include linux/kd.h, a kernel-headers file that
# neither musl nor the host libc guarantees on every build host. Generate the
# required headers out-of-tree from the read-only /linux source; /linux itself
# is never modified because the output goes into the build directory only.
KERNEL_SRC_SRC="${AWEOS_LINUX_SRC:-/linux}"
KERNEL_HEADERS="${BUILD_DIR}/linux-headers"
KERNEL_HEADERS_ABS="$(cd -- "${BUILD_DIR}" && pwd -P)/linux-headers"
if [ ! -f "${KERNEL_HEADERS}/usr/include/linux/kd.h" ]; then
    if [ ! -d "${KERNEL_SRC_SRC}" ]; then
        echo "ERROR: kernel source tree not found at ${KERNEL_SRC_SRC}; cannot generate linux-headers" >&2
        exit 2
    fi
    echo "Installing kernel headers out-of-tree into ${KERNEL_HEADERS}..."
    make -C "${KERNEL_SRC_SRC}" O="${KERNEL_HEADERS_ABS}" ARCH=x86_64 headers_install
fi
if [ ! -f "${KERNEL_HEADERS}/usr/include/linux/kd.h" ]; then
    echo "ERROR: expected header linux/kd.h was not generated in ${KERNEL_HEADERS}" >&2
    exit 2
fi

if [ ! -s "${ARCHIVE}" ] || ! printf '%s  %s\n' "${BUSYBOX_SHA256}" "${ARCHIVE}" | sha256sum --check --status; then
    rm -f "${ARCHIVE}" "${ARCHIVE}.tmp"
    echo "Downloading BusyBox ${BUSYBOX_VERSION} source..."
    curl --fail --location --retry 3 --output "${ARCHIVE}.tmp" "${BUSYBOX_URL}"
    printf '%s  %s\n' "${BUSYBOX_SHA256}" "${ARCHIVE}.tmp" | sha256sum --check
    mv "${ARCHIVE}.tmp" "${ARCHIVE}"
fi

WORK_DIR="$(mktemp -d "${BUILD_DIR}/.busybox-build.XXXXXX")"
trap 'rm -rf -- "${WORK_DIR}"' EXIT

tar -xjf "${ARCHIVE}" --directory "${WORK_DIR}" --strip-components=1
(
    cd "${WORK_DIR}"
    make defconfig

    set_config() {
        local key="$1"
        local value="$2"
        if grep -q "^${key}=" .config; then
            sed -i "s|^${key}=.*|${key}=${value}|" .config
        else
            printf '%s=%s\n' "${key}" "${value}" >> .config
        fi
    }

    # Build one static multicall binary for both the persistent rootfs and
    # initramfs. These flags deliberately target the original x86-64 baseline
    # and prepend the out-of-tree kernel headers to the include path.
    set_config CONFIG_STATIC y
    set_config CONFIG_FEATURE_PREFER_APPLETS y
    set_config CONFIG_FEATURE_SH_STANDALONE y
    set_config CONFIG_EXTRA_CFLAGS '"-I"${KERNEL_HEADERS_ABS}/usr/include" -march=x86-64 -mtune=generic -mno-avx -mno-avx2 -mno-avx512f -mno-bmi -mno-bmi2 -mno-fma -mno-f16c"'

    make oldconfig </dev/null
    make -j"${AWEOS_BUSYBOX_JOBS:-$(nproc)}" CC="${AWEOS_BUSYBOX_CC:-musl-gcc}" HOSTCC=cc
    test -s busybox
)

install -D -m 0755 "${WORK_DIR}/busybox" "${OUTPUT}"
bash "${SCRIPT_DIR}/check-x86-64-baseline-isa.sh" "${OUTPUT}"
if readelf -l "${OUTPUT}" | grep -q 'INTERP'; then
    echo "ERROR: BusyBox must be statically linked for the initramfs." >&2
    exit 1
fi
"${OUTPUT}" --list >/dev/null
echo "Built BusyBox ${BUSYBOX_VERSION} as a static musl binary for x86-64 baseline: ${OUTPUT}"
