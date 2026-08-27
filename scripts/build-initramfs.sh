#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build}"
INITRAMFS_DIR="${BUILD_DIR}/initramfs"
OUTPUT_CPIO="${BUILD_DIR}/aweos-initramfs.cpio.gz"

echo "Building AWEOS initramfs in ${INITRAMFS_DIR}..."

rm -rf "${INITRAMFS_DIR}"
mkdir -p "${INITRAMFS_DIR}"/{bin,sbin,usr/bin,usr/sbin,dev,proc,sys,run,tmp,etc,root,var}

BUSYBOX_BIN="$(which busybox 2>/dev/null || true)"
if [ -z "$BUSYBOX_BIN" ]; then
    echo "Error: busybox binary not found!" >&2
    exit 1
fi

cp "$BUSYBOX_BIN" "${INITRAMFS_DIR}/bin/busybox"
chmod +x "${INITRAMFS_DIR}/bin/busybox"

# Install busybox symlinks
(
    cd "${INITRAMFS_DIR}"
    for applet in $(./bin/busybox --list); do
        if [ ! -e "bin/$applet" ] && [ ! -e "sbin/$applet" ] && [ ! -e "usr/bin/$applet" ] && [ ! -e "usr/sbin/$applet" ]; then
            ln -s /bin/busybox "bin/$applet"
        fi
    done
)

# Create /init script
cat > "${INITRAMFS_DIR}/init" <<'INITEOF'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t tmpfs tmpfs /run 2>/dev/null || true
mount -t tmpfs tmpfs /tmp 2>/dev/null || true

# Fallback device nodes
if [ ! -e /dev/console ]; then
    mknod /dev/console c 5 1 2>/dev/null || true
fi
if [ ! -e /dev/null ]; then
    mknod /dev/null c 1 3 2>/dev/null || true
fi
if [ ! -e /dev/ttyS0 ]; then
    mknod /dev/ttyS0 c 4 64 2>/dev/null || true
fi
if [ ! -e /dev/tty ]; then
    mknod /dev/tty c 5 0 2>/dev/null || true
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
Bootloader: Limine

AWEOS BOOT SUCCESS
AWEOS TERMINAL READY

LOGO

if [ -x /bin/busybox ]; then
    exec /bin/busybox cttyhack /bin/sh
else
    exec /bin/sh
fi
INITEOF

chmod +x "${INITRAMFS_DIR}/init"

# Pack into cpio.gz
(
    cd "${INITRAMFS_DIR}"
    find . -print0 | cpio --null -o --format=newc | gzip -9
) > "${OUTPUT_CPIO}"

echo "Initramfs created successfully at ${OUTPUT_CPIO}"
