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

# Validate the actual ELF runtime closure of every packaged userland binary.
# A file can exist and be executable while still failing execve when PT_INTERP
# is absent or non-executable inside the target root filesystem.
validate_elf_runtime() {
    local binary="$1"
    local interpreter loader ldd_output lib

    readelf -h "$binary" >/dev/null 2>&1 || return 0
    interpreter="$(readelf -l "$binary" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' | head -n 1)"
    [ -n "$interpreter" ] || return 0

    loader="${ROOTFS_DIR}${interpreter}"
    [ -f "$loader" ] && [ -x "$loader" ] || fail "ELF interpreter is missing or not executable for ${binary}: ${interpreter}"

    ldd_output="$(ldd "$binary" 2>&1)" || fail "cannot inspect ELF runtime dependencies for ${binary}: ${ldd_output}"
    if grep -Fq "not found" <<< "$ldd_output"; then
        fail "unresolved ELF runtime dependency for ${binary}: ${ldd_output}"
    fi

    while IFS= read -r lib; do
        [ -n "$lib" ] || continue
        [ -e "${ROOTFS_DIR}${lib}" ] || fail "ELF dependency is missing from rootfs for ${binary}: ${lib}"
    done < <(printf '%s\n' "$ldd_output" | awk '$2 == "=>" && $3 ~ /^\// {print $3} $1 ~ /^\/lib/ {print $1}')
}

command -v readelf >/dev/null 2>&1 || fail "readelf is required for ELF runtime validation"
command -v ldd >/dev/null 2>&1 || fail "ldd is required for ELF runtime validation"
while IFS= read -r -d '' binary; do
    validate_elf_runtime "$binary"
done < <(find "${ROOTFS_DIR}/usr/bin" -type f -print0)

echo "AWEOS rootfs layout validation passed: ${ROOTFS_DIR}"
