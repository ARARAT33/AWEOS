#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AWEPKG="${REPO_ROOT}/scripts/awepkg.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/awepkg-test.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

ROOT_DIR="${TMP_DIR}/root"
DB_DIR="${ROOT_DIR}/var/lib/awepkg"
mkdir -p "${ROOT_DIR}" "${TMP_DIR}/package/root/usr/share/demo"

cat > "${TMP_DIR}/package/manifest.meta" <<'EOF'
PKG_NAME=demo-package
PKG_VER=1.0.0
PKG_DESC=Package manager integration test
EOF
printf 'installed by awepkg\n' > "${TMP_DIR}/package/root/usr/share/demo/message.txt"
(cd "${TMP_DIR}/package" && tar -czf "${TMP_DIR}/demo.awe" manifest.meta root)

AWEPKG_ROOT="${ROOT_DIR}" AWEPKG_DB_DIR="${DB_DIR}" "${AWEPKG}" install "${TMP_DIR}/demo.awe"
test -f "${ROOT_DIR}/usr/share/demo/message.txt"
test "$(cat "${ROOT_DIR}/usr/share/demo/message.txt")" = "installed by awepkg"
AWEPKG_ROOT="${ROOT_DIR}" AWEPKG_DB_DIR="${DB_DIR}" "${AWEPKG}" info demo-package | grep -qx 'PKG_NAME=demo-package'
AWEPKG_ROOT="${ROOT_DIR}" AWEPKG_DB_DIR="${DB_DIR}" "${AWEPKG}" remove demo-package
test ! -e "${ROOT_DIR}/usr/share/demo/message.txt"

mkdir -p "${TMP_DIR}/unsafe/root"
cp "${TMP_DIR}/package/manifest.meta" "${TMP_DIR}/unsafe/manifest.meta"
ln -s /etc/passwd "${TMP_DIR}/unsafe/root/escape"
(cd "${TMP_DIR}/unsafe" && tar -czf "${TMP_DIR}/unsafe.awe" manifest.meta root)
if AWEPKG_ROOT="${ROOT_DIR}" AWEPKG_DB_DIR="${DB_DIR}" "${AWEPKG}" install "${TMP_DIR}/unsafe.awe"; then
    echo "unsafe symlink package was accepted" >&2
    exit 1
fi

echo "awepkg integration tests passed"
