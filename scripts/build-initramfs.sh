#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build}"
INITRAMFS_DIR="${BUILD_DIR}/initramfs"
OUTPUT_CPIO="${BUILD_DIR}/aweos-initramfs.cpio.gz"

echo "Building AWEOS bootstrap initramfs in ${INITRAMFS_DIR}..."

rm -rf "${INITRAMFS_DIR}"
mkdir -p "${INITRAMFS_DIR}"/{bin,sbin,usr/bin,usr/sbin,dev,proc,sys,run,tmp,etc,mnt/rootfs,mnt/boot}

BUSYBOX_BIN="$(which busybox 2>/dev/null || true)"
if [ -z "$BUSYBOX_BIN" ]; then
    echo "Error: busybox binary not found!" >&2
    exit 1
fi

cp "$BUSYBOX_BIN" "${INITRAMFS_DIR}/bin/busybox"
chmod +x "${INITRAMFS_DIR}/bin/busybox"

# Copy dynamic interpreter and shared libraries if busybox is dynamically linked
mkdir -p "${INITRAMFS_DIR}"/lib64 "${INITRAMFS_DIR}"/lib/x86_64-linux-gnu
if [ -f /lib64/ld-linux-x86-64.so.2 ]; then
    cp /lib64/ld-linux-x86-64.so.2 "${INITRAMFS_DIR}/lib64/"
fi
for lib in /lib/x86_64-linux-gnu/libc.so.6 /lib/x86_64-linux-gnu/libresolv.so.2 /lib/x86_64-linux-gnu/libm.so.6 /lib/x86_64-linux-gnu/libutil.so.1; do
    if [ -f "$lib" ]; then
        cp "$lib" "${INITRAMFS_DIR}/lib/x86_64-linux-gnu/"
    fi
done

(
    cd "${INITRAMFS_DIR}"
    for applet in $(./bin/busybox --list); do
        if [ ! -e "bin/$applet" ] && [ ! -e "sbin/$applet" ] && [ ! -e "usr/bin/$applet" ] && [ ! -e "usr/sbin/$applet" ]; then
            ln -s /bin/busybox "bin/$applet"
        fi
    done
)

# Create initramfs /init bootstrap script
cat > "${INITRAMFS_DIR}/init" <<'INITEOF'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t tmpfs tmpfs /run 2>/dev/null || true
mount -t tmpfs tmpfs /tmp 2>/dev/null || true

# Fallback device nodes
[ -e /dev/console ] || mknod /dev/console c 5 1 2>/dev/null || true
[ -e /dev/null ] || mknod /dev/null c 1 3 2>/dev/null || true
[ -e /dev/ttyS0 ] || mknod /dev/ttyS0 c 4 64 2>/dev/null || true
[ -e /dev/tty ] || mknod /dev/tty c 5 0 2>/dev/null || true

cat << 'LOGO'
    █████╗ ██╗    ██╗███████╗ ██████╗ ███████╗
   ██╔══██╗██║    ██║██╔════╝██╔═══██╗██╔════╝
   ███████║██║ █╗ ██║█████╗  ██║   ██║███████╗
   ██╔══██║██║███╗██║██╔══╝  ██║   ██║╚════██║
   ██║  ██║╚███╔███╔╝███████╗╚██████╔╝███████║
   ╚═╝  ╚═╝ ╚══╝╚══╝ ╚══════╝ ╚═════╝ ╚══════╝

AWEOS Bootstrap Initramfs Initializing...
LOGO

ROOTFS_MOUNTED=0
NEW_ROOT="/mnt/rootfs"

echo "Locating AWEOS root filesystem..."
sleep 1

# 1. Check direct block devices for ext4 rootfs (e.g. disk/USB partitions or virtio disk)
for dev in /dev/vda /dev/vda1 /dev/vda2 /dev/sda /dev/sda1 /dev/sda2 /dev/nvme0n1p1 /dev/nvme0n1p2 /dev/sdb /dev/sdb1; do
    if [ -b "$dev" ]; then
        echo "Attempting to mount rootfs from $dev..."
        if mount -t ext4 -o rw "$dev" "$NEW_ROOT" 2>/dev/null; then
            if [ -x "$NEW_ROOT/sbin/init" ] || [ -x "$NEW_ROOT/bin/sh" ]; then
                echo "Found valid AWEOS rootfs on $dev!"
                ROOTFS_MOUNTED=1
                break
            else
                umount "$NEW_ROOT" 2>/dev/null || true
            fi
        fi
    fi
done

# 2. Check ISO / boot media loopback rootfs.img if not mounted yet
if [ "$ROOTFS_MOUNTED" -eq 0 ]; then
    echo "Searching boot media for rootfs.img..."
    mkdir -p /mnt/boot
    for dev in /dev/sr0 /dev/sr1 /dev/cdrom /dev/vda /dev/sda /dev/sda1 /dev/sdb /dev/sdb1; do
        if [ -b "$dev" ]; then
            if mount -t iso9660 -o ro "$dev" /mnt/boot 2>/dev/null || mount -t vfat -o ro "$dev" /mnt/boot 2>/dev/null || mount -t ext4 -o ro "$dev" /mnt/boot 2>/dev/null; then
                if [ -f "/mnt/boot/rootfs.img" ] || [ -f "/mnt/boot/boot/rootfs.img" ]; then
                    IMG="/mnt/boot/rootfs.img"
                    [ -f "$IMG" ] || IMG="/mnt/boot/boot/rootfs.img"
                    echo "Found rootfs image at $IMG! Mounting loopback..."
                    if mount -t ext4 -o loop "$IMG" "$NEW_ROOT" 2>/dev/null; then
                        echo "Successfully mounted loopback rootfs from ISO!"
                        ROOTFS_MOUNTED=1
                        break
                    fi
                fi
                umount /mnt/boot 2>/dev/null || true
            fi
        fi
    done
fi

if [ "$ROOTFS_MOUNTED" -eq 1 ] && [ -x "$NEW_ROOT/sbin/init" ]; then
    echo "Transitioning to AWEOS persistent root filesystem via switch_root..."
    mount --move /dev "$NEW_ROOT/dev" 2>/dev/null || true
    mount --move /proc "$NEW_ROOT/proc" 2>/dev/null || true
    mount --move /sys "$NEW_ROOT/sys" 2>/dev/null || true
    mount --move /run "$NEW_ROOT/run" 2>/dev/null || true

    exec switch_root "$NEW_ROOT" /sbin/init
fi

echo "WARNING: Could not mount persistent rootfs. Falling back to initramfs root."
cat << 'MARKERS'
AWEOS BOOT SUCCESS
AWEOS TERMINAL READY
MARKERS

exec cttyhack /bin/sh
INITEOF

chmod +x "${INITRAMFS_DIR}/init"

(
    cd "${INITRAMFS_DIR}"
    find . -print0 | cpio --null -o --format=newc | gzip -9
) > "${OUTPUT_CPIO}"

echo "Bootstrap initramfs created successfully at ${OUTPUT_CPIO}"
