#!/bin/sh
# AWEOS initramfs root discovery. Disk probing is read-only by default.
set -u
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

ROOT_PREFIX="${AWEOS_INITRAMFS_ROOT:-}"
root_path() { printf '%s%s' "$ROOT_PREFIX" "$1"; }

DEV_DIR="$(root_path /dev)"
PROC_DIR="$(root_path /proc)"
SYS_DIR="$(root_path /sys)"
RUN_DIR="$(root_path /run)"
TMP_DIR="$(root_path /tmp)"
NEW_ROOT="$(root_path /mnt/rootfs)"
BOOT_MOUNT="$(root_path /mnt/boot)"
OVERLAY_ROOT="$(root_path /mnt/newroot)"
CMDLINE_FILE="$(root_path /proc/cmdline)"

mkdir -p "$DEV_DIR" "$PROC_DIR" "$SYS_DIR" "$RUN_DIR" "$TMP_DIR" "$NEW_ROOT" "$BOOT_MOUNT"
mount -t proc proc "$PROC_DIR" 2>/dev/null || true
mount -t sysfs sysfs "$SYS_DIR" 2>/dev/null || true
mount -t devtmpfs devtmpfs "$DEV_DIR" 2>/dev/null || true
mount -t tmpfs tmpfs "$RUN_DIR" 2>/dev/null || true
mount -t tmpfs tmpfs "$TMP_DIR" 2>/dev/null || true

[ -e "$DEV_DIR/console" ] || mknod "$DEV_DIR/console" c 5 1 2>/dev/null || true
[ -e "$DEV_DIR/null" ] || mknod "$DEV_DIR/null" c 1 3 2>/dev/null || true
[ -e "$DEV_DIR/ttyS0" ] || mknod "$DEV_DIR/ttyS0" c 4 64 2>/dev/null || true
[ -e "$DEV_DIR/tty" ] || mknod "$DEV_DIR/tty" c 5 0 2>/dev/null || true

echo "AWEOS Bootstrap Initramfs Initializing..."
CMDLINE=""
[ -r "$CMDLINE_FILE" ] && CMDLINE="$(cat "$CMDLINE_FILE")"

ROOT_DEVICE=""
ROOT_RW=0
MODE=ayui
for token in $CMDLINE; do
    case "$token" in
        aweos.root=*) ROOT_DEVICE="${token#aweos.root=}" ;;
        root=/dev/*) [ -n "$ROOT_DEVICE" ] || ROOT_DEVICE="${token#root=}" ;;
        aweos.root-rw=1) ROOT_RW=1 ;;
        aweos.mode=installer) MODE=installer ;;
        aweos.mode=headless) MODE=headless ;;
        aweos.mode=ayui|aweos.mode=aweui|aweos.mode=gui) MODE=ayui ;;
    esac
done

is_block_device() {
    device="$1"
    [ -b "$device" ] && return 0
    # Regular files are accepted only by the isolated regression harness.
    [ "${AWEOS_INITRAMFS_TEST_ALLOW_REGULAR_DEVICES:-0}" = "1" ] && [ -f "$device" ]
}

is_aweos_root() {
    candidate="$1"
    [ -x "$candidate/sbin/init" ] || return 1
    [ -s "$candidate/etc/aweos-release" ] || return 1
    [ -s "$candidate/etc/os-release" ] || return 1
    grep -Eq '^ID="?aweos"?$' "$candidate/etc/os-release"
}

ROOTFS_MOUNTED=0
ROOTFS_LIVE=0
ROOTFS_SOURCE=""
echo "Locating AWEOS root filesystem..."

if [ -n "$ROOT_DEVICE" ]; then
    case "$ROOT_DEVICE" in
        /dev/*) device_name="${ROOT_DEVICE#/dev/}" ;;
        *)
            echo "ERROR: explicit root device must be under /dev; refusing '$ROOT_DEVICE'." >&2
            device_name=""
            ;;
    esac
    case "$device_name" in
        ""|.|..|*/*)
            echo "ERROR: invalid explicit AWEOS root device name; refusing to scan other disks." >&2
            ;;
        *)
            candidate_device="$DEV_DIR/$device_name"
            if is_block_device "$candidate_device"; then
                echo "Checking explicitly selected root device $candidate_device read-only..."
                if mount -t ext4 -o ro,noload "$candidate_device" "$NEW_ROOT" 2>/dev/null; then
                    if is_aweos_root "$NEW_ROOT"; then
                        ROOTFS_MOUNTED=1
                        ROOTFS_SOURCE="$candidate_device"
                    else
                        echo "Ignoring $candidate_device: it is not a verified AWEOS root filesystem."
                        umount "$NEW_ROOT" 2>/dev/null || true
                    fi
                fi
            else
                echo "ERROR: explicit AWEOS root device is not a block device: $candidate_device" >&2
            fi
            ;;
    esac
else
    # Live-media discovery is read-only; installed disks are never selected implicitly.
    for device_name in sr0 sr1 cdrom vda sda sda1 sdb sdb1; do
        candidate_device="$DEV_DIR/$device_name"
        is_block_device "$candidate_device" || continue

        for filesystem in iso9660 vfat ext4; do
            media_options=ro
            [ "$filesystem" = "ext4" ] && media_options=ro,noload
            if mount -t "$filesystem" -o "$media_options" "$candidate_device" "$BOOT_MOUNT" 2>/dev/null; then
                image_path=""
                if [ -f "$BOOT_MOUNT/rootfs.img" ]; then
                    image_path="$BOOT_MOUNT/rootfs.img"
                elif [ -f "$BOOT_MOUNT/boot/rootfs.img" ]; then
                    image_path="$BOOT_MOUNT/boot/rootfs.img"
                fi

                if [ -n "$image_path" ] &&
                    mount -t ext4 -o loop,ro,noload "$image_path" "$NEW_ROOT" 2>/dev/null; then
                    if is_aweos_root "$NEW_ROOT"; then
                        ROOTFS_MOUNTED=1
                        ROOTFS_LIVE=1
                        ROOTFS_SOURCE="$image_path"
                        # The loop mount retains the backing-file reference.
                        umount -l "$BOOT_MOUNT" 2>/dev/null || true
                        break 2
                    fi
                    echo "Ignoring rootfs image on $candidate_device: AWEOS identity check failed."
                    umount "$NEW_ROOT" 2>/dev/null || true
                fi
                umount "$BOOT_MOUNT" 2>/dev/null || true
                break
            fi
        done
    done
fi

if [ "$ROOTFS_MOUNTED" -eq 1 ]; then
    if [ "$ROOTFS_LIVE" -eq 0 ] && [ "$ROOT_RW" -eq 1 ]; then
        echo "Explicit aweos.root-rw=1 requested; remounting verified AWEOS root read-write."
        if ! mount -o remount,rw "$NEW_ROOT"; then
            echo "ERROR: verified AWEOS root could not be remounted read-write." >&2
            ROOTFS_MOUNTED=0
        fi
    elif [ "$ROOTFS_LIVE" -eq 1 ] || [ "$ROOT_RW" -eq 0 ]; then
        # Writable session state lives in tmpfs; the discovered lower root stays unchanged.
        mkdir -p "$RUN_DIR/overlay/upper" "$RUN_DIR/overlay/work" "$OVERLAY_ROOT"
        if mount -t overlay overlay \
            -o "lowerdir=$NEW_ROOT,upperdir=$RUN_DIR/overlay/upper,workdir=$RUN_DIR/overlay/work" \
            "$OVERLAY_ROOT"; then
            NEW_ROOT="$OVERLAY_ROOT"
        else
            echo "ERROR: unable to create the temporary writable root overlay." >&2
            ROOTFS_MOUNTED=0
        fi
    fi
fi

if [ "$ROOTFS_MOUNTED" -eq 1 ]; then
    for mount_source in dev proc sys run tmp; do
        case "$mount_source" in
            dev) source_path="$DEV_DIR" ;;
            proc) source_path="$PROC_DIR" ;;
            sys) source_path="$SYS_DIR" ;;
            run) source_path="$RUN_DIR" ;;
            tmp) source_path="$TMP_DIR" ;;
        esac
        mkdir -p "$NEW_ROOT/$mount_source"
        if ! mount --move "$source_path" "$NEW_ROOT/$mount_source"; then
            echo "ERROR: unable to move $mount_source into the verified AWEOS root." >&2
            ROOTFS_MOUNTED=0
            break
        fi
    done
fi

if [ "$ROOTFS_MOUNTED" -eq 1 ] && [ -x "$NEW_ROOT/sbin/init" ]; then
    access_mode=overlay
    [ "$ROOTFS_LIVE" -eq 0 ] && [ "$ROOT_RW" -eq 1 ] && access_mode=rw
    echo "AWEOS ROOTFS READY: mode=$MODE source=$ROOTFS_SOURCE access=$access_mode"
    echo "Transitioning to verified AWEOS root filesystem via switch_root..."
    if switch_root "$NEW_ROOT" /sbin/init; then
        exit 0
    fi
    echo "ERROR: switch_root returned unexpectedly; entering initramfs recovery." >&2
fi

echo "AWEOS INITRAMFS RECOVERY READY"
exec cttyhack /bin/sh
