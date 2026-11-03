# AWEOS boot and root-filesystem mounting

## Live media

The live boot entry does not select an installed disk partition. The initramfs
searches boot media for `rootfs.img`, mounts the media read-only, mounts the
embedded ext4 image with `loop,ro,noload`, and verifies that the image contains:

- an executable `/sbin/init`;
- `/etc/os-release` with `ID=aweos`;
- a non-empty `/etc/aweos-release`.

A verified live root is exposed through an overlay whose upper and work
directories are on the initramfs tmpfs `/run`. Writes made during a live
session are therefore temporary; they do not modify the ISO or another disk.

## Explicit installed-root selection

An installed-root device is never selected by scanning arbitrary internal
disks. The bootloader must pass one explicit device parameter:

```text
aweos.root=/dev/<partition>
```

The standard `root=/dev/<partition>` form is also accepted. The selected ext4
filesystem is initially mounted with `ro,noload` and must pass the AWEOS
identity checks above before `switch_root` is attempted. A missing, malformed,
or non-AWEOS device falls back to the initramfs recovery console.

UUID-based root selection is not implemented yet. Until a stable UUID resolver
is added and tested, use an explicit `/dev` device path in the boot entry.

## Persistent root writes

A verified installed root remains read-only by default and receives a
tmpfs-backed overlay. Persistent writes require the additional explicit kernel
command-line opt-in:

```text
aweos.root=/dev/<partition> aweos.root-rw=1
```

The initramfs still verifies AWEOS identity while the filesystem is mounted
read-only before attempting the read-write remount. If that remount fails, boot
does not continue into the selected root.

This option is not an installer. The C installer/updater transaction backend
remains fail-closed until real target-volume staging, bootloader deployment,
verification, and rollback are implemented. No partitioning or formatting is
performed by initramfs root discovery.

## Safety expectations

- No arbitrary disk is mounted read-write during root discovery.
- ext4 discovery uses `ro,noload` to avoid journal replay during probing.
- Live ISO media and its embedded root image are read-only.
- A root handoff requires explicit selection or a verified live-media image.
- A boot marker is emitted only after root identity and mount setup succeed.
- `/linux` remains a vendored read-only source tree; build and boot checks
  continue to verify that it is unchanged.
