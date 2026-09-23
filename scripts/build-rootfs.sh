#!/bin/bash
set -euo pipefail

if [ "${AWEOS_DESKTOP:-gnome}" = "gnome" ]; then
    exec "$(dirname "$0")/build-rootfs-gnome.sh" "$@"
fi

set -euo pipefail

BUILD_DIR="${1:-build}"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
ROOTFS_IMG="${BUILD_DIR}/rootfs.img"
IMG_SIZE_MB="${2:-128}"

echo "Building AWEOS root filesystem in ${ROOTFS_DIR}..."

rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"/{bin,sbin,usr/bin,usr/sbin,usr/lib,usr/share/applications,usr/share/backgrounds,etc,dev,proc,sys,run,tmp,var/log,var/cache,var/lib/awepkg,var/tmp,home/aweos,root,opt,mnt,media,srv,boot,etc/aweos,etc/aweui}
mkdir -p "${ROOTFS_DIR}/run/user/0"
chmod 0700 "${ROOTFS_DIR}/run/user/0"

BUSYBOX_BIN="$(command -v busybox || true)"
test -n "${BUSYBOX_BIN}" || { echo "ERROR: busybox binary not found" >&2; exit 1; }
cp -L "${BUSYBOX_BIN}" "${ROOTFS_DIR}/bin/busybox"
chmod 0755 "${ROOTFS_DIR}/bin/busybox"

RUST_BINS="
aweui
aweui-installer
aweui-settings
aweui-control-center
aweui-file-manager
aweui-terminal
aweui-system-monitor
aweui-diagnostics
aweui-text-editor
aweui-calculator
aweui-firstboot-setup
aweui-user-app-template
"

copy_runtime_deps() {
    local binary="$1"
    command -v ldd >/dev/null 2>&1 || return 0
    ldd "${binary}" 2>/dev/null |
        awk '/=> \/|^\/lib/ {print ($3 ~ /^\// ? $3 : $1)}' |
        while IFS= read -r lib; do
            [ -f "${lib}" ] || continue
            install -D -m 0644 "${lib}" "${ROOTFS_DIR}${lib}"
        done
}

for binary in ${RUST_BINS}; do
    source="${BUILD_DIR}/${binary}"
    test -x "${source}" || { echo "ERROR: required userland binary missing: ${source}" >&2; exit 1; }
    install -D -m 0755 "${source}" "${ROOTFS_DIR}/usr/bin/${binary}"
    copy_runtime_deps "${source}"
done

(
    cd "${ROOTFS_DIR}"
    for applet in $(./bin/busybox --list); do
        target="bin/${applet}"
        [ -e "${target}" ] || ln -s /bin/busybox "${target}"
    done
)

chmod 1777 "${ROOTFS_DIR}/tmp" "${ROOTFS_DIR}/var/tmp"

cat > "${ROOTFS_DIR}/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
aweos:x:1000:1000:AWEOS User:/home/aweos:/bin/sh
EOF
cat > "${ROOTFS_DIR}/etc/group" <<'EOF'
root:x:0:
aweos:x:1000:
tty:x:5:
wheel:x:10:
EOF
cat > "${ROOTFS_DIR}/etc/shadow" <<'EOF'
root:*:19700:0:99999:7:::
aweos:*:19700:0:99999:7:::
EOF
chmod 0600 "${ROOTFS_DIR}/etc/shadow"

cat > "${ROOTFS_DIR}/etc/shells" <<'EOF'
/bin/sh
/bin/ash
EOF
cat > "${ROOTFS_DIR}/etc/hostname" <<'EOF'
aweos
EOF
cat > "${ROOTFS_DIR}/etc/hosts" <<'EOF'
127.0.0.1 localhost aweos
::1 localhost aweos
EOF
cat > "${ROOTFS_DIR}/etc/os-release" <<'EOF'
NAME="AWEOS"
ID=aweos
PRETTY_NAME="AWEOS"
VERSION="0.1.0"
VERSION_ID="0.1.0"
BUILD_ID="x86_64"
HOME_URL="https://github.com/ARARAT33/AWEOS"
ARCH=x86_64
EOF
cat > "${ROOTFS_DIR}/etc/aweos-release" <<'EOF'
AWEOS 0.1.0 (x86_64)
EOF
cat > "${ROOTFS_DIR}/etc/aweos/config" <<'EOF'
AUTOLOGIN=true
DEFAULT_USER=root
HOSTNAME=aweos
NETWORK_AUTO=true
EOF

cat > "${ROOTFS_DIR}/etc/aweui/config.toml" <<'EOF'
[desktop]
wallpaper = "/usr/share/backgrounds/aweos-default.png"
theme = "AWEUI-Dark"
icon_theme = "AWEUI-Icons"
font = "Sans"
font_size = 10
accent_color = "#3b82f6"

[input]
repeat_rate = 25
repeat_delay = 200
tap_to_click = true
pointer_speed = 1.0

[wm]
default_mode = "floating"
gap_size = 6
border_width = 2
active_border_color = "#3b82f6"
inactive_border_color = "#334155"
workspace_count = 4

[panel]
position = "top"
height = 32
auto_hide = false
widgets = ["launcher", "workspaces", "window_title", "cpu_ram", "clock", "control_center_toggle"]
EOF

cat > "${ROOTFS_DIR}/etc/profile" <<'EOF'
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export TERM=xterm
export HOME="${HOME:-/root}"
export USER="${USER:-root}"
if [ "${USER}" = "root" ]; then
    export PS1='root@aweos:\w# '
else
    export PS1='aweos@aweos:\w$ '
fi
EOF
cp "${ROOTFS_DIR}/etc/profile" "${ROOTFS_DIR}/root/.profile"
cp "${ROOTFS_DIR}/etc/profile" "${ROOTFS_DIR}/home/aweos/.profile"

make_desktop() {
    local file="$1" name="$2" exec="$3" comment="$4" categories="$5"
    cat > "${ROOTFS_DIR}/usr/share/applications/${file}" <<EOF
[Desktop Entry]
Type=Application
Name=${name}
Exec=${exec}
Comment=${comment}
Categories=${categories}
Terminal=false
EOF
}
make_desktop aweui-terminal.desktop "AWE Terminal" aweui-terminal "System terminal" "System;TerminalEmulator;"
make_desktop aweui-files.desktop "AWE File Manager" aweui-file-manager "Browse files" "System;FileManager;"
make_desktop aweui-settings.desktop "AWE Settings" aweui-settings "System settings" "Settings;System;"
make_desktop aweui-control-center.desktop "AWE Control Center" aweui-control-center "System controls" "Settings;System;"
make_desktop aweui-calculator.desktop "AWE Calculator" "aweui-calculator -i" "Scientific calculator" "Utility;Calculator;"
make_desktop aweui-monitor.desktop "AWE System Monitor" aweui-system-monitor "System resource monitor" "System;Monitor;"
make_desktop aweui-editor.desktop "AWE Text Viewer" aweui-text-editor "View a text file" "Utility;TextEditor;"

for helper in aweos-info.sh aweos-diagnostics.sh awepkg.sh; do
    source="scripts/${helper}"
    test -f "${source}" || { echo "ERROR: missing helper ${source}" >&2; exit 1; }
    install -D -m 0755 "${source}" "${ROOTFS_DIR}/usr/bin/${helper%.sh}"
done
ln -sf /usr/bin/aweos-info "${ROOTFS_DIR}/usr/bin/aweos"
ln -sf /usr/bin/aweos-info "${ROOTFS_DIR}/usr/bin/aweos-status"

cat > "${ROOTFS_DIR}/var/lib/awepkg/base-system.meta" <<'EOF'
PKG_NAME=base-system
PKG_VER=0.1.0
PKG_DESC=AWEOS Base Userspace
ARCH=x86_64
EOF

cat > "${ROOTFS_DIR}/sbin/init" <<'EOF'
#!/bin/sh
set -eu
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mkdir -p /dev/pts /run /run/user/0 /tmp
mount -t devpts devpts /dev/pts 2>/dev/null || true
mount -t tmpfs tmpfs /run 2>/dev/null || true
mkdir -p /run/user/0
chmod 0700 /run/user/0
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    export XDG_RUNTIME_DIR=/run/user/0
fi

[ -f /etc/hostname ] && hostname -F /etc/hostname 2>/dev/null || true

MODE=gui
if grep -qw aweos.mode=installer /proc/cmdline 2>/dev/null; then
    MODE=installer
elif grep -qw aweos.mode=aweui /proc/cmdline 2>/dev/null; then
    MODE=aweui
elif grep -qw aweos.mode=headless /proc/cmdline 2>/dev/null; then
    MODE=headless
fi

echo "AWEOS BOOT SUCCESS: mode=${MODE}"

case "${MODE}" in
    installer)
        exec /usr/bin/aweui-installer
        ;;
    aweui|gui)
        if [ -x /usr/bin/aweui-firstboot-setup ] && grep -q '^fresh_install=true' /etc/aweos/first_boot 2>/dev/null; then
            /usr/bin/aweui-firstboot-setup || true
        fi
        exec /usr/bin/aweui
        ;;
    headless)
        exec /bin/busybox cttyhack /bin/sh
        ;;
esac
EOF
chmod 0755 "${ROOTFS_DIR}/sbin/init"

cat > "${ROOTFS_DIR}/etc/aweos/first_boot" <<'EOF'
fresh_install=false
EOF

chown -R 0:0 "${ROOTFS_DIR}" 2>/dev/null || true
chown -R 1000:1000 "${ROOTFS_DIR}/home/aweos" 2>/dev/null || true

echo "Creating persistent ext4 rootfs image ${ROOTFS_IMG} (${IMG_SIZE_MB} MiB)..."
rm -f "${ROOTFS_IMG}"
dd if=/dev/zero of="${ROOTFS_IMG}" bs=1M count="${IMG_SIZE_MB}" status=none
mke2fs -t ext4 -F -d "${ROOTFS_DIR}" "${ROOTFS_IMG}" >/dev/null
test -s "${ROOTFS_IMG}"
echo "AWEOS rootfs built successfully."
