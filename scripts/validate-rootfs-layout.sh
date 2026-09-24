#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build}"
ROOTFS_DIR="${BUILD_DIR}/rootfs"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ -d "${ROOTFS_DIR}" ] || fail "rootfs directory is missing: ${ROOTFS_DIR}"

for required_dir in bin dev etc home proc root run sbin sys tmp usr/bin usr/lib usr/share/applications var/log; do
    [ -d "${ROOTFS_DIR}/${required_dir}" ] || fail "required rootfs directory is missing: /${required_dir}"
done

for required_file in \
    etc/passwd \
    etc/group \
    etc/shadow \
    etc/os-release \
    etc/aweos/config \
    etc/aweui/config.toml \
    sbin/init \
    usr/share/wayland-sessions/ayui.desktop \
    usr/bin/aweui; do
    [ -s "${ROOTFS_DIR}/${required_file}" ] || fail "required rootfs file is missing or empty: /${required_file}"
done

[ -x "${ROOTFS_DIR}/sbin/init" ] || fail "/sbin/init is not executable"
[ -x "${ROOTFS_DIR}/bin/busybox" ] || fail "/bin/busybox is not executable"

awk -F: 'BEGIN { ok=0 } $1 == "aweos" && $3 == "1000" { ok=1 } END { exit ok ? 0 : 1 }' "${ROOTFS_DIR}/etc/passwd" \
    || fail "the aweos user with UID 1000 is missing from /etc/passwd"

awk -F: 'BEGIN { ok=0 } $1 == "aweos" && $3 == "1000" { ok=1 } END { exit ok ? 0 : 1 }' "${ROOTFS_DIR}/etc/group" \
    || fail "the aweos group with GID 1000 is missing from /etc/group"

if grep -q 'Exec=/usr/bin/aweui$' "${ROOTFS_DIR}/usr/share/wayland-sessions/ayui.desktop"; then
    :
else
    fail "AYUI Wayland session does not launch /usr/bin/aweui"
fi

echo "AWEOS rootfs layout validation passed: ${ROOTFS_DIR}"
