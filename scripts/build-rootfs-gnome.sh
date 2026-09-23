#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build}"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
ROOTFS_IMG="${BUILD_DIR}/rootfs.img"
IMG_SIZE_MB="${AWEOS_ROOTFS_SIZE_MB:-4096}"
UBUNTU_SUITE="${AWEOS_UBUNTU_SUITE:-noble}"
UBUNTU_MIRROR="${AWEOS_UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}"

command -v debootstrap >/dev/null
command -v chroot >/dev/null
rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"

debootstrap --arch=amd64 --components=main,restricted,universe,multiverse "${UBUNTU_SUITE}" "${ROOTFS_DIR}" "${UBUNTU_MIRROR}"

cat > "${ROOTFS_DIR}/etc/apt/sources.list" <<EOF
deb ${UBUNTU_MIRROR} ${UBUNTU_SUITE} main restricted universe multiverse
deb ${UBUNTU_MIRROR} ${UBUNTU_SUITE}-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${UBUNTU_SUITE}-security main restricted universe multiverse
EOF

cp -L /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf" 2>/dev/null || true
mount --bind /dev "${ROOTFS_DIR}/dev"
mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts" 2>/dev/null || true
mount -t proc proc "${ROOTFS_DIR}/proc"
mount -t sysfs sysfs "${ROOTFS_DIR}/sys"
mount -t tmpfs tmpfs "${ROOTFS_DIR}/run"

cleanup() {
    set +e
    umount -lf "${ROOTFS_DIR}/run" 2>/dev/null
    umount -lf "${ROOTFS_DIR}/sys" 2>/dev/null
    umount -lf "${ROOTFS_DIR}/proc" 2>/dev/null
    umount -lf "${ROOTFS_DIR}/dev/pts" 2>/dev/null
    umount -lf "${ROOTFS_DIR}/dev" 2>/dev/null
}
trap cleanup EXIT

cat > "${ROOTFS_DIR}/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
chmod 0755 "${ROOTFS_DIR}/usr/sbin/policy-rc.d"

chroot "${ROOTFS_DIR}" /bin/bash -euxo pipefail <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

apt-get update
apt-get -y full-upgrade
apt-get install -y --no-install-recommends \
    ubuntu-desktop-minimal linux-firmware network-manager \
    openssh-client curl wget ca-certificates sudo bash-completion \
    git nano vim-tiny pciutils usbutils mesa-utils xdg-utils \
    plymouth plymouth-theme-ubuntu-text

systemctl enable gdm3
systemctl set-default graphical.target

useradd -m -s /bin/bash -G adm,audio,cdrom,dialout,floppy,video,plugdev,netdev,sudo,render,input aweos || true
passwd -d aweos
passwd -d root

install -d -m 0755 /etc/gdm3
cat > /etc/gdm3/custom.conf <<'EOF'
[daemon]
WaylandEnable=true
AutomaticLoginEnable=true
AutomaticLogin=aweos
EOF

cat > /etc/os-release <<'EOF'
NAME="AWEOS"
ID=aweos
ID_LIKE="ubuntu debian"
PRETTY_NAME="AWEOS GNOME"
VERSION="1.0"
VERSION_ID="1.0"
BUILD_ID="x86_64"
HOME_URL="https://github.com/ARARAT33/AWEOS"
UBUNTU_CODENAME=noble
EOF

cat > /etc/aweos-release <<'EOF'
AWEOS 1.0 — Ubuntu GNOME userspace
EOF

install -d -m 0755 /etc/aweos /usr/share/backgrounds
cat > /etc/aweos/config <<'EOF'
DESKTOP=GNOME
DISPLAY_MANAGER=gdm3
SESSION=ubuntu
NETWORK_MANAGER=true
PACKAGE_MANAGER=apt
EOF

cat > /etc/systemd/system/aweos-boot-marker.service <<'EOF'
[Unit]
Description=AWEOS boot verification marker
After=multi-user.target
Before=gdm3.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo "AWEOS BOOT SUCCESS: mode=gnome" > /dev/ttyS0 || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable aweos-boot-marker.service

apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/*
rm -f /usr/sbin/policy-rc.d
CHROOT

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

for binary in ${RUST_BINS}; do
    source="${BUILD_DIR}/${binary}"
    test -x "${source}"
    install -D -m 0755 "${source}" "${ROOTFS_DIR}/usr/bin/${binary}"
done

for helper in aweos-info.sh aweos-diagnostics.sh awepkg.sh; do
    source="scripts/${helper}"
    test -f "${source}"
    install -D -m 0755 "${source}" "${ROOTFS_DIR}/usr/bin/${helper%.sh}"
done

ln -sf /usr/bin/aweos-info "${ROOTFS_DIR}/usr/bin/aweos"
ln -sf /usr/bin/aweos-info "${ROOTFS_DIR}/usr/bin/aweos-status"

cat > "${ROOTFS_DIR}/usr/share/applications/awe-terminal.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=AWE Terminal
Comment=AWEOS native terminal
Exec=/usr/bin/aweui-terminal
Icon=utilities-terminal
Categories=System;TerminalEmulator;
Terminal=false
EOF

cat > "${ROOTFS_DIR}/usr/share/applications/awe-settings.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=AWEOS Settings
Comment=AWEOS native settings
Exec=/usr/bin/aweui-settings
Icon=preferences-system
Categories=Settings;System;
Terminal=false
EOF

mkdir -p "${ROOTFS_DIR}/var/lib/awepkg"
cat > "${ROOTFS_DIR}/var/lib/awepkg/base-system.meta" <<'EOF'
PKG_NAME=base-system
PKG_VER=1.0
PKG_DESC=AWEOS GNOME Base System
ARCH=x86_64
EOF

chown -R 0:0 "${ROOTFS_DIR}"
chown -R 1000:1000 "${ROOTFS_DIR}/home/aweos" 2>/dev/null || true

rm -f "${ROOTFS_IMG}"
dd if=/dev/zero of="${ROOTFS_IMG}" bs=1M count="${IMG_SIZE_MB}" status=none
mke2fs -t ext4 -F -d "${ROOTFS_DIR}" "${ROOTFS_IMG}" >/dev/null
test -s "${ROOTFS_IMG}"
echo "AWEOS GNOME rootfs built successfully."
