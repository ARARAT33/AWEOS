# AWEOS build output directory safety

AWEOS build scripts write generated root filesystems, initramfs archives, ISO
images, disk images, and compiled binaries. They must not treat an arbitrary
caller-supplied path as disposable.

## Ownership marker

The first build may create a marker in a new or empty build directory:

```text
.aweos-build-dir
AWEOS build directory v1
```

Build scripts refuse to use a non-empty directory without this marker. This
prevents an accidental `BUILD_DIR` override from deleting or replacing files
that were not created as AWEOS build output.

If an existing build directory contains only artifacts you have inspected and
you intentionally want AWEOS to manage it, adopt it explicitly once:

```bash
AWEOS_ADOPT_BUILD_DIR=1 make image
```

Adoption only writes the ownership marker; it does not delete existing files.
Do not adopt a directory containing personal files or unrelated projects.

## Protected locations

The shared build-path guard resolves symlinks and relative path components
before accepting a destination. It refuses:

- the filesystem root;
- the repository root or a directory containing the repository;
- the vendored `/linux` source tree and every descendant of it;
- a build directory supplied as a symlink;
- a non-empty, unmarked directory.

The guard is used by the Rust build, kernel build, rootfs builders, initramfs
builder, ISO builder, disk-image builder, and cleanup command.

## Cleanup

`make clean` delegates to `scripts/clean-build.sh`. It removes only a
directory with the exact AWEOS ownership marker and refuses unmarked paths.
If no build directory exists, cleanup is a no-op.

The disk-image builder also creates a temporary image in the marked build
directory and publishes it only after partitioning, rootfs copying, and Limine
installation all succeed. A failed build therefore leaves the previous image
intact.
