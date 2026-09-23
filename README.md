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
AWEOS is a complete, bootable x86_64 Linux operating system featuring **AYUI as the default desktop**, a native C graphical desktop environment, double-buffered framebuffer renderer, compositor, window manager, PTY-backed terminal emulator, AOSIN package system (`.asp`, `.asa`, `.aosin`), safe OS system updater (`aweos-update`), standalone graphical installer (`aweos-installer`), cross-platform USB-less migration installer (`wlin`), and headless fallback, powered by the upstream Linux kernel source and the Limine bootloader.

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

## AOSIN Package System (`src/aosin/`)
Native AWEOS package management system supporting three formal format specifications:
- **`.asp` (AWEOS Software Package)**: Software/payload binary archives.
- **`.asa` (AWEOS Standalone Application)**: Self-contained application bundles.
- **`.aosin` (AOSIN Installer Archive)**: Multi-package installation bundles with manifests and permission bounds.
- **`aosin` CLI Tool**: Query, install, remove, and verify packages registered under `/var/lib/awepkg/`.
- **AYUI Integration**: Dynamic package scanning in `/var/lib/awepkg/*.meta` automatically populates the AYUI desktop application launcher menu.

## AYUI Native Desktop Environment (`src/gui/`, `src/apps/`)
- Built independently without external Desktop Environments (GNOME, KDE, Xfce, LXQt, etc.).
- **Executable**: `/usr/bin/aweos-ayui` (symlinked as `aweos-wm`, `aweos-gui`, `start-ayui`, `aweos-terminal`).
- **Graphics Abstraction**: Double-buffered `/dev/fb0` Linux framebuffer driver with resolution adaptation.
- **Input System**: Linux `/dev/input/event*` evdev keyboard/mouse input normalization with cursor tracking.
- **Compositor & Window Manager**: Surface layout, title bar controls, focus handling, z-ordering, and application launcher.
- **Graphical Terminal**: Live `/bin/sh` Unix PTY (`/dev/ptmx` forkpty) execution with real-time rendering.
- **Base Native GUI Applications**: File Manager, Settings, System Information, Network Manager, Storage Info, Package Manager, Installer, Updater, Diagnostics, About AWEOS.

## Safe OS System Updater (`src/updater/`)
- **`aweos-update`**: Staged, atomic OS update tool validating candidate ISO images, staging rootfs updates, preserving `/home` user data, and managing boot target switching.

## Standalone Graphical Installer (`src/installer/`)
- **`aweos-installer`**: Interactive GUI and CLI installer supporting dual-boot installation, full-disk replacement (with explicit destructive confirmation), and BIOS/UEFI boot setup.

## WLIN Cross-OS Installation Tool (`src/wlin/`)
- **Cross-Platform Installer**: USB-less installation tool for Windows and Linux hosts.
- **Windows Backend (`wlin.exe`)**: Compiled natively via MinGW-w64 (`x86_64-w64-mingw32-gcc`) with Win32 GUI controls (`CreateWindowEx`).
- **Linux Backend (`wlin`)**: Native C Linux application.
- **USB-Less Boot Staging**: Validates AWEOS ISO, stages kernel/initramfs onto boot staging partition, configures EFI/Limine boot path, and prepares computer to reboot directly into AWEOS installer.

## Build System Usage

- `make` or `make build`: Verify `/linux` immutability, build kernel out-of-tree, core libraries, AYUI GUI, AOSIN, installer, updater, WLIN (Linux & Win32), rootfs, initramfs, ISO (`build/AWEOS-x86_64.iso`), and raw disk image (`build/AWEOS-x86_64-disk.img`).
- `make ayui`: Build `aweos-ayui` desktop session executable.
- `make aosin`: Build `aosin` package management binary.
- `make installer`: Build `aweos-installer` standalone installer binary.
- `make updater`: Build `aweos-update` OS system updater binary.
- `make wlin`: Build `wlin` Linux migration binary.
- `make wlin-win32`: Build `wlin.exe` Windows MinGW migration binary.
- `make verify-linux-readonly`: Execute read-only integrity check on `/linux`.
- `make test`: Run automated QEMU BIOS, UEFI, and AYUI GUI verification tests.
- `make test-gui` / `make test-ayui`: Run automated QEMU AYUI GUI boot marker test and QMP screenshot capture (`build/ayui-screenshot.png`).
- `make qemu-gui` / `make qemu-ayui`: Launch interactive QEMU graphical desktop boot mode.
- `make clean`: Clean build artifacts in `build/`.
