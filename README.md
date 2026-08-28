# AWEOS Architecture & Complete OS Stack Documentation

## Overview
AWEOS is a complete, bootable x86_64 Linux operating system featuring a native C graphical stack, double-buffered framebuffer renderer, compositor, window manager, PTY-backed terminal emulator, AOSIN package system (`.asp`, `.asa`, `.aosin`), safe OS system updater (`aweos-update`), standalone graphical installer (`aweos-installer`), cross-platform USB-less migration installer (`wlin`), and headless fallback, powered by the upstream Linux kernel source and the Limine bootloader.

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
       AWEOS compositor                 │
              │                         │
        AWEOS GUI shell                 │
              │                         │
     ┌────────┼─────────────┐            │
     │        │             │            │
 Terminal  Settings      Installer   System Apps
     │                      │            │
     └──────────────┬───────┘            │
                    │                    │
               AWEOS userspace           │
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

## Native GUI & Compositor Architecture (`src/gui/`, `src/apps/`)
- Built independently without external Desktop Environments (GNOME, KDE, Xfce, LXQt, etc.).
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
- **Windows Backend (`wlin.exe`)**: Compiled natively via MinGW-w64 (`x86_64-w64-mingw32-gcc`).
- **Linux Backend (`wlin`)**: Native C Linux application.
- **USB-Less Boot Staging**: Validates AWEOS ISO, stages kernel/initramfs onto boot staging partition, configures EFI/Limine boot path, and prepares computer to reboot directly into AWEOS installer.

## Build System Usage

- `make` or `make build`: Verify `/linux` immutability, build kernel out-of-tree, core libraries, GUI, AOSIN, installer, updater, WLIN (Linux & Win32), rootfs, initramfs, ISO (`build/AWEOS-x86_64.iso`), and raw disk image (`build/AWEOS-x86_64-disk.img`).
- `make aosin`: Build `aosin` package management binary.
- `make installer`: Build `aweos-installer` standalone installer binary.
- `make updater`: Build `aweos-update` OS system updater binary.
- `make wlin`: Build `wlin` Linux migration binary.
- `make wlin-win32`: Build `wlin.exe` Windows MinGW migration binary.
- `make verify-linux-readonly`: Execute read-only integrity check on `/linux`.
- `make test`: Run automated QEMU BIOS, UEFI, and GUI verification tests.
- `make test-gui`: Run automated QEMU GUI boot marker test and QMP screenshot capture (`build/aweos-gui-screenshot.png`).
- `make qemu-gui`: Launch interactive QEMU graphical desktop boot mode.
- `make clean`: Clean build artifacts in `build/`.
