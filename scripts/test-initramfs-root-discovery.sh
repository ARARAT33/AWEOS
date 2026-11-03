#!/usr/bin/env bash
# Exercise the actual initramfs init script with isolated device/mount stubs.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
init_script="$repo_root/scripts/aweos-initramfs-init.sh"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-initramfs-test.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT

mock_bin="$tmp_root/bin"
mkdir -p "$mock_bin"

cat > "$mock_bin/mount" <<'MOCK_MOUNT'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$AWEOS_TEST_MOUNT_LOG"

if [ "${1:-}" = "-t" ] && [ "${2:-}" = "iso9660" ]; then
    cp -a "$AWEOS_TEST_MEDIA_FIXTURE/." "${6:-}/"
    exit 0
fi

if [ "${1:-}" = "-t" ] && [ "${2:-}" = "ext4" ] && [ "${3:-}" = "-o" ]; then
    options="${4:-}"
    source="${5:-}"
    target="${6:-}"
    case "$options" in
        ro,noload)
            if [ "$source" = "$AWEOS_TEST_ROOT_PREFIX/dev/sda1" ]; then
                cp -a "$AWEOS_TEST_DIRECT_FIXTURE/." "$target/"
            fi
            ;;
        loop,ro,noload)
            cp -a "$AWEOS_TEST_ISO_ROOT_FIXTURE/." "$target/"
            ;;
    esac
    exit 0
fi

if [ "${1:-}" = "-t" ] && [ "${2:-}" = "overlay" ]; then
    cp -a "$AWEOS_TEST_OVERLAY_FIXTURE/." "${6:-}/"
    exit 0
fi

exit 0
MOCK_MOUNT

cat > "$mock_bin/umount" <<'MOCK_UMOUNT'
#!/bin/sh
set -eu
target="${1:-}"
if [ "${1:-}" = "-l" ]; then
    target="${2:-}"
fi
if [ -n "$target" ] && [ -d "$target" ]; then
    find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
fi
exit 0
MOCK_UMOUNT

cat > "$mock_bin/switch_root" <<'MOCK_SWITCH_ROOT'
#!/bin/sh
set -eu
printf '%s\n' "$*" > "$AWEOS_TEST_SWITCH_ROOT_LOG"
printf '%s\n' "$" > "$AWEOS_TEST_SWITCH_ROOT_PID"
exit 0
MOCK_SWITCH_ROOT

for command_name in cttyhack mknod sleep; do
    cat > "$mock_bin/$command_name" <<'MOCK_NOOP'
#!/bin/sh
exit 0
MOCK_NOOP
done
chmod 0755 "$mock_bin"/*

make_root_fixture() {
    local root="$1"
    local identity="$2"
    mkdir -p "$root/etc" "$root/sbin"
    printf '#!/bin/sh\nexit 0\n' > "$root/sbin/init"
    chmod 0755 "$root/sbin/init"
    printf 'AWEOS test release\n' > "$root/etc/aweos-release"
    if [ "$identity" = "aweos" ]; then
        printf 'NAME="AWEOS"\nID=aweos\n' > "$root/etc/os-release"
    else
        printf 'NAME="Other OS"\nID=other\n' > "$root/etc/os-release"
    fi
}

assert_switch_root_exec() {
    local root="$1"
    if [[ ! -s "$root/switch-root.pid" || ! -s "$root/init.pid" ]]; then
        echo "ERROR: switch_root was not executed for the original init process in $root." >&2
        cat "$root/output.log" >&2
        exit 1
    fi
    if [[ "$(cat "$root/switch-root.pid")" != "$(cat "$root/init.pid")" ]]; then
        echo "ERROR: switch_root was forked instead of inheriting PID 1 in $root." >&2
        echo "init PID: $(cat "$root/init.pid"); switch_root PID: $(cat "$root/switch-root.pid")" >&2
        exit 1
    fi
    if ! grep -q -- '^-c /dev/console ' "$root/switch-root.log"; then
        echo "ERROR: switch_root did not reopen the new root console in $root." >&2
        cat "$root/switch-root.log" >&2
        exit 1
    fi
    if grep -q 'switch_root returned unexpectedly' "$root/output.log"; then
        echo "ERROR: initramfs fell back after a successful switch_root mock in $root." >&2
        cat "$root/output.log" >&2
        exit 1
    fi
}

run_case() {
    local name="$1"
    local cmdline="$2"
    local direct_identity="$3"
    local use_iso="$4"
    local root="$tmp_root/$name"
    local fixture="$root/direct-fixture"
    local iso_fixture="$root/iso-fixture"
    local iso_root_fixture="$root/iso-root-fixture"
    mkdir -p "$root/dev" "$root/proc" "$root/sys" "$root/run" "$root/tmp" \
        "$root/mnt/rootfs" "$root/mnt/boot" "$root/mnt/newroot" \
        "$fixture" "$iso_fixture/boot" "$iso_root_fixture"
    printf '%s\n' "$cmdline" > "$root/proc/cmdline"
    : > "$root/dev/sda1"
    : > "$root/dev/sr0"
    make_root_fixture "$fixture" "$direct_identity"
    make_root_fixture "$iso_root_fixture" "aweos"
    printf 'mock ext4 image\n' > "$iso_fixture/boot/rootfs.img"

    local direct_fixture media_fixture overlay_fixture
    if [ "$use_iso" = "1" ]; then
        direct_fixture="$root/empty-direct"
        mkdir -p "$direct_fixture"
        media_fixture="$iso_fixture"
        overlay_fixture="$iso_root_fixture"
    else
        direct_fixture="$fixture"
        media_fixture="$root/empty-media"
        mkdir -p "$media_fixture"
        overlay_fixture="$fixture"
    fi

    rm -f "$root/mount.log" "$root/switch-root.log" "$root/switch-root.pid" "$root/init.pid"
    env \
        PATH="$mock_bin:$PATH" \
        AWEOS_INITRAMFS_ROOT="$root" \
        AWEOS_INITRAMFS_TEST_ALLOW_REGULAR_DEVICES=1 \
        AWEOS_TEST_ROOT_PREFIX="$root" \
        AWEOS_TEST_DIRECT_FIXTURE="$direct_fixture" \
        AWEOS_TEST_ISO_ROOT_FIXTURE="$iso_root_fixture" \
        AWEOS_TEST_OVERLAY_FIXTURE="$overlay_fixture" \
        AWEOS_TEST_MEDIA_FIXTURE="$media_fixture" \
        AWEOS_TEST_MOUNT_LOG="$root/mount.log" \
        AWEOS_TEST_SWITCH_ROOT_LOG="$root/switch-root.log" \
        AWEOS_TEST_SWITCH_ROOT_PID="$root/switch-root.pid" \
        /bin/sh "$init_script" > "$root/output.log" 2>&1 &
    local init_pid=$!
    wait "$init_pid" || true
    printf '%s\n' "$init_pid" > "$root/init.pid"

    printf '%s\n' "$root"
}

# A foreign filesystem with /sbin/init must never be selected as AWEOS.
untrusted_root="$(run_case untrusted 'aweos.root=/dev/sda1' other 0)"
grep -q 'AWEOS INITRAMFS RECOVERY READY' "$untrusted_root/output.log"
test ! -e "$untrusted_root/switch-root.log"
test -s "$untrusted_root/mount.log"
grep -q -- '-o ro,noload .*/dev/sda1' "$untrusted_root/mount.log"
if grep -q -- 'remount,rw' "$untrusted_root/mount.log"; then
    echo "ERROR: untrusted root was remounted read-write." >&2
    exit 1
fi
echo "PASS: foreign filesystem rejected without read-write mount."

# A verified disk root stays read-only by default and receives a tmpfs overlay.
readonly_root="$(run_case readonly 'aweos.root=/dev/sda1' aweos 0)"
grep -q 'AWEOS ROOTFS READY: mode=ayui source=.*/dev/sda1 access=overlay' "$readonly_root/output.log"
grep -q -- '-t overlay overlay' "$readonly_root/mount.log"
assert_switch_root_exec "$readonly_root"
if grep -q -- 'remount,rw' "$readonly_root/mount.log"; then
    echo "ERROR: default root discovery unexpectedly remounted the disk read-write." >&2
    exit 1
fi
echo "PASS: verified disk root defaults to a read-only lower layer and tmpfs overlay."

# Persistent writes require the explicit kernel command-line opt-in.
writable_root="$(run_case writable 'aweos.root=/dev/sda1 aweos.root-rw=1' aweos 0)"
grep -q 'access=rw' "$writable_root/output.log"
grep -q -- '-o remount,rw' "$writable_root/mount.log"
if grep -q -- '-t overlay overlay' "$writable_root/mount.log"; then
    echo "ERROR: explicit persistent root unexpectedly received a live overlay." >&2
    exit 1
fi
echo "PASS: persistent root writes require explicit kernel opt-in."

# Live ISO rootfs images are loop-mounted read-only and always use a tmpfs overlay.
iso_root="$(run_case iso 'aweos.mode=ayui' other 1)"
grep -q 'AWEOS ROOTFS READY: mode=ayui source=.*/rootfs.img access=overlay' "$iso_root/output.log"
grep -q -- '-t iso9660 -o ro' "$iso_root/mount.log"
grep -q -- '-o loop,ro,noload' "$iso_root/mount.log"
grep -q -- '-t overlay overlay' "$iso_root/mount.log"
assert_switch_root_exec "$iso_root"
if grep -q -- 'remount,rw' "$iso_root/mount.log"; then
    echo "ERROR: live ISO rootfs was remounted read-write." >&2
    exit 1
fi

echo "PASS: initramfs accepts only verified AWEOS roots, probes disks read-only, and requires explicit opt-in for persistent writes."
