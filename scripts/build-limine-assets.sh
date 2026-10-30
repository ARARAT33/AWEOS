#!/usr/bin/env bash
# Build the pinned Limine release from its official source tarball.
# The source archive is verified before extraction; only generated assets are
# written to DEST, and no existing directory is recursively removed.
set -euo pipefail

DEST="${1:-build/limine-12.9.6}"
VERSION="${2:-12.9.6}"

case "${VERSION}" in
    12.9.6)
        SOURCE_SHA256="5022d02c0709ccf3cd6702e89206e2e8c953d253d80fc05b276a526c23719332"
        ;;
    *)
        echo "ERROR: Limine version ${VERSION} is not pinned in this script." >&2
        exit 2
        ;;
esac

case "${DEST}" in
    /*) ;;
    *) DEST="${PWD}/${DEST}" ;;
esac

required_files=(
    limine
    limine-bios.sys
    limine-bios-cd.bin
    limine-uefi-cd.bin
    BOOTX64.EFI
)

if [ -f "${DEST}/VERSION" ] && [ "$(cat "${DEST}/VERSION")" = "${VERSION}" ] && [ -s "${DEST}/SHA256SUMS" ]; then
    if (cd "${DEST}" && sha256sum --check --status SHA256SUMS); then
        echo "Verified Limine ${VERSION} assets already exist in ${DEST}."
        exit 0
    fi
    echo "Existing Limine asset cache failed its checksum manifest; rebuilding it."
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aweos-limine.XXXXXX")"
trap 'rm -rf -- "$TMP_ROOT"' EXIT
ARCHIVE="${TMP_ROOT}/limine-${VERSION}.tar.gz"
SOURCE_ROOT="${TMP_ROOT}/source"
STAGE="${TMP_ROOT}/stage"

URL="https://github.com/Limine-Bootloader/Limine/releases/download/v${VERSION}/limine-${VERSION}.tar.gz"
echo "Downloading pinned Limine ${VERSION} source..."
curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
    --connect-timeout 20 --max-time 180 "${URL}" -o "${ARCHIVE}"

printf '%s  %s\n' "${SOURCE_SHA256}" "${ARCHIVE}" | sha256sum --check -
mkdir -p "${SOURCE_ROOT}" "${STAGE}"
tar -xzf "${ARCHIVE}" -C "${SOURCE_ROOT}"

CONFIGURE_PATH="$(find "${SOURCE_ROOT}" -maxdepth 3 -type f -name configure -print -quit)"
if [ -z "${CONFIGURE_PATH}" ]; then
    echo "ERROR: verified Limine source archive does not contain configure." >&2
    exit 1
fi
SOURCE_DIR="$(dirname "${CONFIGURE_PATH}")"

(
    cd "${SOURCE_DIR}"
    ./configure --enable-bios --enable-bios-cd --enable-uefi-x86-64 --enable-uefi-cd
    make -j"${JOBS:-$(nproc)}"
)

BIN_DIR="${SOURCE_DIR}/bin"
test -x "${BIN_DIR}/limine" || {
    echo "ERROR: Limine host utility was not built." >&2
    exit 1
}

install -m 0755 "${BIN_DIR}/limine" "${STAGE}/limine"
for asset in limine-bios.sys limine-bios-cd.bin limine-uefi-cd.bin BOOTX64.EFI; do
    source_asset="${BIN_DIR}/${asset}"
    if [ ! -s "${source_asset}" ]; then
        source_asset="$(find "${SOURCE_DIR}" -type f -name "${asset}" -print -quit)"
    fi
    if [ -z "${source_asset}" ] || [ ! -s "${source_asset}" ]; then
        echo "ERROR: Limine ${VERSION} did not produce required asset ${asset}." >&2
        exit 1
    fi
    install -m 0644 "${source_asset}" "${STAGE}/${asset}"
done

printf '%s\n' "${VERSION}" > "${STAGE}/VERSION"
(
    cd "${STAGE}"
    sha256sum "${required_files[@]}" > SHA256SUMS
)

# Install only the named, verified build outputs. Never remove DEST or its
# unrelated contents; each file replacement is atomic on the same filesystem.
mkdir -p -- "${DEST}"
install -m 0755 "${STAGE}/limine" "${DEST}/limine"
for asset in limine-bios.sys limine-bios-cd.bin limine-uefi-cd.bin BOOTX64.EFI; do
    install -m 0644 "${STAGE}/${asset}" "${DEST}/${asset}"
done
install -m 0644 "${STAGE}/VERSION" "${DEST}/VERSION"
install -m 0644 "${STAGE}/SHA256SUMS" "${DEST}/SHA256SUMS"

(
    cd "${DEST}"
    sha256sum --check SHA256SUMS
)
echo "Limine ${VERSION} BIOS/UEFI assets built and verified in ${DEST}."
