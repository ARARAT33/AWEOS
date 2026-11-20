# AWEOS Architecture & Complete OS Stack Documentation

> **Current default desktop:** AYUI native desktop; Ubuntu Noble GNOME is the secondary graphical environment. AWEOS supplies its own Linux kernel build, Limine boot path, native utilities and OS integration; GNOME is the actual desktop session.

## Current Desktop Architecture

AWEOS builds its native AYUI desktop by default and keeps a real Ubuntu 24.04 Noble GNOME userspace as a secondary graphical environment. The secondary GNOME graphical stack comes from Ubuntu packages rather than a mock desktop: GNOME Shell, Mutter, GDM, GNOME Control Center, Ubuntu session components, NetworkManager, PipeWire/WirePlumber and the normal freedesktop application model. Ubuntu's official `ubuntu-desktop-minimal` package includes GNOME Shell, GDM and GNOME Control Center. citeturn0search0turn0search2

The ISO is a live environment. Its Ubuntu root filesystem is mounted as the lower OverlayFS layer and a writable RAM upper layer is created before systemd starts. Disk-image boots use the ext4 root filesystem directly. The AWEOS kernel configuration enables cgroups, namespaces and OverlayFS outside the read-only `/linux` tree.

AYUI/AWEUI is the primary AWEOS desktop session. GNOME is retained as the secondary compatibility/full-feature desktop.

### Build profiles

- Default: `AWEOS_DESKTOP=ayui make image`
- Secondary GNOME: `AWEOS_DESKTOP=gnome make image`
- Root filesystem: 4 GiB by default; override with `AWEOS_ROOTFS_SIZE_MB`
- QEMU desktop boot tests: 2 GiB RAM
- CI verifies that `/linux` is unchanged before and after the build/test pipeline.

## Overview
AWEOS is a bootable x86_64 Linux-based operating-system project. The current image build uses the upstream Linux kernel and Limine BIOS/UEFI boot path, a Rust userland, a Smithay-based AYUI Wayland compositor (nested Winit/GLES backend in the current tested path), system applications, and the AOSIN v2 package CLI. This repository does not contain an independent kernel, and the current CI does not validate ARM64, RISC-V, LoongArch, or physical-hardware support. Several C installer/updater/WLIN modules remain source-level components and are not part of the current default image build.

## Core Rules & Isolation Policy
- **`/linux` Read-Only Rule**: The upstream Linux kernel source tree in `/linux` is strictly read-only. No files inside `/linux` are added, modified, formatted, patched, or created.
- **Out-of-Tree Builds**: All Linux kernel configuration (`scripts/config-kernel.sh`) and build outputs are generated out-of-tree in `build/linux-x86_64/`.
- **Read-Only Protection Guard**: Enforced via `./scripts/verify-linux-readonly.sh` before and after builds and tests.

## Target Architecture & System Stack
```
                         AWEOS
                           │
              ┌────────────┴────────────┐
              │                         │
           Booting                  Installed OS
              │                         │
       BIOS / UEFI / QEMU               │
              │                         │
         Linux Kernel                   │
              │                         │
          AWEOS Init                    │
              │                         │
     device/system services             │
              │                         │
      graphics + input stack            │
              │                         │
         AYUI compositor                │
              │                         │
         AYUI desktop shell             │
              │                         │
     ┌────────┼─────────────┐            │
     │        │             │            │
 Terminal  Settings      Installer   System Apps
     │                      │            │
     └──────────────┬───────┘            │
                    │                    │
               AYUI userspace            │
                    │                    │
          package/update framework       │
                    │                    │
          AOSIN + AWEOS package API      │
```

## Shared Core C Infrastructure (`src/core/`)
- **`types.h` / `logging.h`**: Standardized logging, error codes, and transaction state management.
- **`storage.c/h`**: Multi-disk, partition layout (GPT/MBR), filesystem UUID, and free space discovery.
- **`boot.c/h`**: BIOS and UEFI Limine bootloader configuration (`limine.conf`).
- **`iso_verify.c/h`**: ISO manifest checking, header validation, and SHA-256 checksum verification.
- **`archive.c/h`**: Non-destructive user data preservation engine archiving directory structures into `/archiveddata/`.
- **`transaction.c/h`**: Atomic transaction engine (`PLAN -> VALIDATE -> PREPARE -> PRESERVE -> EXECUTE -> BOOTCFG -> VERIFY -> COMMIT / ROLLBACK`).

These C modules are present in the source tree; not all are linked into the current default image. The actual shipped components are determined by the Makefile and rootfs scripts, not by directory presence alone.

## AOSIN Package System (`src/aosin/`)

Current implementation: AOSIN binary package format v2 with bounded payload file tables, streamed SHA-256 integrity verification, and a native CLI shipped as /usr/bin/aosin in both rootfs profiles.

- **Container layout**: fixed-width header, file-entry table, and concatenated payload bytes. The SHA-256 digest covers the payload bytes and is rechecked by verify, inspect, and install.
- **Type tags**: `.asp`, `.asa`, and `.aosin` currently map to enum values in the same v2 container layout. They are not yet three independent formats or a multi-package installer bundle.
- **CLI**: create, verify, inspect package metadata, install into an explicit root, and remove a package using its installed manifest. The awepkg compatibility wrapper delegates install/remove to this CLI; its unsafe legacy tar extraction path is disabled.
- **Install/remove safety**: payload paths and sizes are bounded; symlink payload entries are skipped; uninstall is scoped to the selected package directory and preserves unowned files.
- **Not implemented yet**: publisher signatures, trusted signing keys, authenticated repositories, dependency resolution, permissions/capabilities, sandboxing, multi-package transactions, and rollback.
- **Security boundary**: SHA-256 detects payload corruption but does not authenticate the publisher. Do not install untrusted packages as root.

## AYUI Native Desktop Environment (AWEUI/)

- **Executable**: `/usr/bin/aweui`, built from the Rust workspace.
- **Compositor**: Smithay Wayland server with compositor, XDG-shell, shared-memory, seat, and data-device protocol handlers.
- **Current render backend**: Smithay's nested Winit backend with GLES rendering. The tested CI path runs AYUI in a QEMU window; this is not yet a direct DRM/KMS console compositor.
- **Window handling**: Wayland toplevel surfaces are tracked and rendered; the current implementation is an early compositor/session, not a complete desktop shell.
- **Incomplete areas**: direct DRM/KMS backend, complete pointer/touch handling, popup support, decorations, panel/launcher rendering inside the compositor, multi-monitor validation, accessibility, and hardware power integration.
- **Status rule**: the BIOS/UEFI boot test requires a submitted AYUI frame. That proves the nested compositor rendered a frame; it does not prove every desktop feature or physical GPU/monitor support.

## Additional C system modules (source-level status)

- `src/updater/`, `src/installer/`, and `src/wlin/` contain C implementation work and tests, but they are not currently built or installed by the default Makefile/rootfs pipeline.
- Do not treat these modules as production installers, disk migrators, or atomic update services until explicit build targets, integration tests, destructive-operation safeguards, and end-to-end BIOS/UEFI tests are wired into CI.
- The default image currently ships the Rust AYUI application suite, BusyBox utilities, and the native AOSIN CLI.

## Build System Usage

Current implemented Makefile targets:

- `make build`: verify the read-only Linux source tree, build Rust userland and the native AOSIN CLI, build the x86_64 kernel out-of-tree, create rootfs/initramfs, then produce the hybrid ISO and raw disk image.
- `make kernel`: build the x86_64 Linux kernel into `build/linux-x86_64/`.
- `make userland`: build Rust applications and `build/aosin`.
- `make aosin`: compile the native AOSIN v2 CLI.
- `make rootfs`: assemble the selected rootfs profile and validate required files.
- `make image`: create ISO and disk-image artifacts.
- `make test`: run read-only boundary, shell/C regressions, and Rust tests.
- `make test-shell`: run shell syntax, C module, package, rootfs, and QEMU-runner regression tests.
- `make test-rust`: run Rust workspace tests.
- `make test-qemu`: boot-test BIOS and UEFI images and require the AYUI first-frame marker.
- `make check`: run shell tests, formatting checks, and Cargo workspace checks.
- `make validate-rootfs`: validate the current rootfs layout.
- `make verify-linux-readonly`: verify that the vendored `/linux` tree is unchanged.
- `make clean`: remove build artifacts under `build/`.

The current kernel/image build target is x86_64 only. ARM64/RISC-V/LoongArch bootloader EFI files are not, by themselves, kernel ports or tested platform support.
