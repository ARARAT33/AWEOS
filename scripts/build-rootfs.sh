#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build}"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
ROOTFS_IMG="${BUILD_DIR}/rootfs.img"
IMG_SIZE_MB="${2:-64}"

echo "Building AWEOS Root Filesystem in ${ROOTFS_DIR}..."

rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"/{bin,sbin,usr/bin,usr/sbin,usr/lib,usr/share,etc,dev,proc,sys,run,tmp,var/log,var/cache,var/lib/awepkg,var/tmp,home/aweos,root,opt,mnt,media,srv,boot,etc/aweos,etc/aweui,etc/init.d}

BUSYBOX_BIN="$(which busybox 2>/dev/null || true)"
if [ -z "$BUSYBOX_BIN" ]; then
    echo "Error: busybox binary not found!" >&2
    exit 1
fi

cp "$BUSYBOX_BIN" "${ROOTFS_DIR}/bin/busybox"
chmod +x "${ROOTFS_DIR}/bin/busybox"

# Copy dynamic interpreter and shared libraries for rootfs
mkdir -p "${ROOTFS_DIR}"/lib64 "${ROOTFS_DIR}"/lib/x86_64-linux-gnu
if [ -f /lib64/ld-linux-x86-64.so.2 ]; then
    cp /lib64/ld-linux-x86-64.so.2 "${ROOTFS_DIR}/lib64/"
fi
for lib in /lib/x86_64-linux-gnu/libc.so.6 /lib/x86_64-linux-gnu/libresolv.so.2 /lib/x86_64-linux-gnu/libm.so.6 /lib/x86_64-linux-gnu/libutil.so.1; do
    if [ -f "$lib" ]; then
        cp "$lib" "${ROOTFS_DIR}/lib/x86_64-linux-gnu/"
    fi
done

# Install busybox symlinks
(
    cd "${ROOTFS_DIR}"
    for applet in $(./bin/busybox --list); do
        if [ ! -e "bin/$applet" ] && [ ! -e "sbin/$applet" ] && [ ! -e "usr/bin/$applet" ] && [ ! -e "usr/sbin/$applet" ]; then
            ln -s /bin/busybox "bin/$applet"
        fi
    done
)

# Set permissions on runtime directories
chmod 1777 "${ROOTFS_DIR}/tmp"
chmod 1777 "${ROOTFS_DIR}/var/tmp"

# Create Unix system identity & auth files
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
root:::0:99999:7:::
aweos:::0:99999:7:::
EOF

cat > "${ROOTFS_DIR}/etc/shells" <<'EOF'
/bin/sh
/bin/ash
EOF

cat > "${ROOTFS_DIR}/etc/hostname" <<'EOF'
aweos
EOF

cat > "${ROOTFS_DIR}/etc/hosts" <<'EOF'
127.0.0.1   localhost aweos
::1         localhost aweos
EOF

cat > "${ROOTFS_DIR}/etc/resolv.conf" <<'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

cat > "${ROOTFS_DIR}/etc/os-release" <<'EOF'
NAME="AWEOS"
ID=aweos
PRETTY_NAME="AWEOS Terminal Linux"
VERSION="1.0.0"
VERSION_ID="1.0.0"
BUILD_ID="x86_64-release"
HOME_URL="https://github.com/ARARAT33/AWEOS"
ARCH=x86_64
EOF

cat > "${ROOTFS_DIR}/etc/aweos/release" <<'EOF'
AWEOS Terminal Linux v1.0.0 (x86_64)
EOF

cat > "${ROOTFS_DIR}/etc/aweos/config" <<'EOF'
# AWEOS System Configuration
AUTOLOGIN=true
DEFAULT_USER=root
HOSTNAME=aweos
NETWORK_AUTO=true
EOF

# System profiles & prompts
cat > "${ROOTFS_DIR}/etc/profile" <<'EOF'
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export TERM=xterm
export USER=$(whoami 2>/dev/null || echo "root")
export HOME=${HOME:-/root}

if [ "$USER" = "root" ]; then
    export PS1='root@aweos:\w# '
else
    export PS1='aweos@aweos:\w$ '
fi

if [ -f /etc/aweos/motd ]; then
    cat /etc/aweos/motd
fi
EOF

cat > "${ROOTFS_DIR}/etc/aweos/motd" <<'EOF'
========================================
       A W E O S  x86_64
    Terminal Linux Distribution
========================================
Type 'aweos info' or 'aweos diagnostics' for system details.
Type 'awepkg' for package management commands.
EOF

cp "${ROOTFS_DIR}/etc/profile" "${ROOTFS_DIR}/root/.profile"
cp "${ROOTFS_DIR}/etc/profile" "${ROOTFS_DIR}/home/aweos/.profile"

# Build & install AWEOS GUI stack binary (AYUI)
echo "Compiling AWEOS native GUI stack (AYUI)..."
gcc -static -Wall -Wextra -O2 "${1}/../src/gui"/*.c "${1}/../src/apps"/*.c "${1}/../src/core"/*.c -I"${1}/../src/gui" -I"${1}/../src/apps" -I"${1}/../src/core" -lutil -o "${ROOTFS_DIR}/usr/bin/aweos-ayui"
chmod +x "${ROOTFS_DIR}/usr/bin/aweos-ayui"
ln -sf /usr/bin/aweos-ayui "${ROOTFS_DIR}/usr/bin/aweos-wm"
ln -sf /usr/bin/aweos-ayui "${ROOTFS_DIR}/usr/bin/aweos-gui"
ln -sf /usr/bin/aweos-ayui "${ROOTFS_DIR}/usr/bin/start-ayui"
ln -sf /usr/bin/aweos-ayui "${ROOTFS_DIR}/usr/bin/aweos-terminal"

# Install AWEUI Wayland Desktop Environment binaries if compiled in BUILD_DIR
if [ -f "${BUILD_DIR}/aweui" ]; then
    echo "Installing AWEUI Wayland Desktop Environment binaries into rootfs..."
    cp "${BUILD_DIR}/aweui" "${ROOTFS_DIR}/usr/bin/aweui"
    chmod +x "${ROOTFS_DIR}/usr/bin/aweui"
    ln -sf /usr/bin/aweui "${ROOTFS_DIR}/usr/bin/start-aweui"

    for app_bin in aweui-settings aweui-control-center aweui-file-manager aweui-terminal aweui-system-monitor aweui-diagnostics aweui-text-editor aweui-calculator; do
        if [ -f "${BUILD_DIR}/${app_bin}" ]; then
            cp "${BUILD_DIR}/${app_bin}" "${ROOTFS_DIR}/usr/bin/${app_bin}"
            chmod +x "${ROOTFS_DIR}/usr/bin/${app_bin}"
        fi
    done
fi

# Copy AWEOS utilities into rootfs
cp "${1}/../scripts/aweos-info.sh" "${ROOTFS_DIR}/usr/bin/aweos"
cp "${1}/../scripts/aweos-diagnostics.sh" "${ROOTFS_DIR}/usr/bin/aweos-diagnostics"
cp "${1}/../scripts/awepkg.sh" "${ROOTFS_DIR}/usr/bin/awepkg"
chmod +x "${ROOTFS_DIR}/usr/bin/aweos"
chmod +x "${ROOTFS_DIR}/usr/bin/aweos-diagnostics"
chmod +x "${ROOTFS_DIR}/usr/bin/awepkg"
ln -sf /usr/bin/aweos "${ROOTFS_DIR}/usr/bin/aweos-info"
ln -sf /usr/bin/aweos "${ROOTFS_DIR}/usr/bin/aweos-status"

# Install sample .awe package into /var/lib/awepkg for initial state
cat > "${ROOTFS_DIR}/var/lib/awepkg/base-system.meta" <<'EOF'
PKG_NAME=base-system
PKG_VER=1.0.0
PKG_DESC=AWEOS Base Userspace System
ARCH=x86_64
EOF

# Create network initialization script /sbin/aweos-network
cat > "${ROOTFS_DIR}/sbin/aweos-network" <<'EOF'
#!/bin/sh
echo "Initializing AWEOS Network..."
ip link set lo up 2>/dev/null || true

for iface in $(ip link show | grep -E '^[0-9]+:' | awk -F': ' '{print $2}' | grep -v '^lo'); do
    echo "Bringing up network interface $iface..."
    ip link set "$iface" up 2>/dev/null || true
    if command -v udhcpc >/dev/null 2>&1; then
        udhcpc -i "$iface" -n -q -t 2 2>/dev/null || true
    fi
done
EOF
chmod +x "${ROOTFS_DIR}/sbin/aweos-network"

# Create AWEOS Init script /sbin/init
cat > "${ROOTFS_DIR}/sbin/init" <<'EOF'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# Mount essential virtual filesystems
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t tmpfs tmpfs /run 2>/dev/null || true
mount -t tmpfs tmpfs /tmp 2>/dev/null || true

mkdir -p /dev/pts
mount -t devpts devpts /dev/pts 2>/dev/null || true

# Set Hostname
if [ -f /etc/hostname ]; then
    hostname -F /etc/hostname 2>/dev/null || hostname aweos 2>/dev/null || true
fi

# Run network initialization
if [ -x /sbin/aweos-network ]; then
    /sbin/aweos-network &
fi

cat << 'LOGO'
    █████╗ ██╗    ██╗███████╗ ██████╗ ███████╗
   ██╔══██╗██║    ██║██╔════╝██╔═══██╗██╔════╝
   ███████║██║ █╗ ██║█████╗  ██║   ██║███████╗
   ██╔══██║██║███╗██║██╔══╝  ██║   ██║╚════██║
   ██║  ██║╚███╔███╔╝███████╗╚██████╔╝███████║
   ╚═╝  ╚═╝ ╚══╝╚══╝ ╚══════╝ ╚═════╝ ╚══════╝

AWEOS x86_64 Operating System
Kernel: Linux (x86_64)
Init System: AWEOS Init v1.0.0

AWEOS BOOT SUCCESS
AWEOS TERMINAL READY

LOGO

# Check kernel cmdline for boot mode override (aweos.mode=gui vs aweos.mode=headless vs aweos.mode=aweui)
MODE="gui"
if grep -q "aweos.mode=aweui" /proc/cmdline 2>/dev/null; then
    MODE="aweui"
elif grep -q "aweos.mode=headless" /proc/cmdline 2>/dev/null; then
    MODE="headless"
fi

if [ "$MODE" = "aweui" ] && [ -x /usr/bin/aweui ]; then
    echo "Starting AWEUI Wayland Desktop Session..."
    /usr/bin/aweui || {
        echo "WARNING: AWEUI Wayland initialization failed! Falling back to terminal..."
        exec /bin/busybox cttyhack /bin/sh
    }
elif [ "$MODE" = "gui" ] && [ -x /usr/bin/aweos-ayui ] && [ -e /dev/fb0 ]; then
    echo "Starting AYUI Desktop Session..."
    /usr/bin/aweos-ayui || {
        echo "WARNING: AYUI GUI initialization failed! Falling back to terminal..."
        exec /bin/busybox cttyhack /bin/sh
    }
else
    if [ "$MODE" = "gui" ]; then
        echo "WARNING: Framebuffer /dev/fb0 not detected or aweos-ayui missing. Falling back to terminal..."
    fi
    AUTOLOGIN="true"
    if [ -f /etc/aweos/config ]; then
        . /etc/aweos/config
    fi
    if [ "$AUTOLOGIN" = "true" ]; then
        exec /bin/busybox cttyhack /bin/sh
    else
        exec /bin/busybox cttyhack /bin/login
    fi
fi
EOF
chmod +x "${ROOTFS_DIR}/sbin/init"

chown -R 0:0 "${ROOTFS_DIR}" 2>/dev/null || true
chown -R 1000:1000 "${ROOTFS_DIR}/home/aweos" 2>/dev/null || true

# Create persistent ext4 disk image rootfs.img
echo "Creating persistent ext4 disk image ${ROOTFS_IMG} (${IMG_SIZE_MB}MB)..."
rm -f "${ROOTFS_IMG}"
dd if=/dev/zero of="${ROOTFS_IMG}" bs=1M count="${IMG_SIZE_MB}" status=none
mke2fs -t ext4 -F -d "${ROOTFS_DIR}" "${ROOTFS_IMG}"

echo "Rootfs directory and ext4 rootfs.img built successfully."
