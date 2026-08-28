# AWEOS Architecture & Boot System Documentation

## Overview
AWEOS is a complete, bootable x86_64 Linux operating system featuring a native C graphical stack, double-buffered framebuffer renderer, compositor, window manager, PTY-backed terminal emulator, and headless fallback, powered by the upstream Linux kernel source and the Limine bootloader.

## Core Rules & Isolation Policy
- **`/linux` Read-Only Rule**: The upstream Linux kernel source tree in `/linux` is strictly read-only. No files inside `/linux` are added, modified, formatted, patched, or created.
- **Out-of-Tree Builds**: All Linux kernel configuration (`scripts/config-kernel.sh`) and build outputs are generated out-of-tree in `build/linux-x86_64/`.
- **Read-Only Protection Guard**: Enforced via `./scripts/verify-linux-readonly.sh`.

## Architecture & Boot Sequence
```
               Firmware (BIOS / UEFI)
                         ↓
            Limine Bootloader (v12.6.1)
                         ↓
            Linux Kernel (x86_64 bzImage)
                         ↓
          AWEOS Initramfs Bootstrap (cpio.gz)
                         ↓
      Locate & Mount Persistent ext4 rootfs.img
                         ↓
                    switch_root
                         ↓
             AWEOS Init (/sbin/init)
                         ↓
          AWEOS BOOT SUCCESS & Boot Markers
                         ↓
       ┌─────────────────┴─────────────────┐
       │                                   │
  AWEOS GUI Mode (Default)     AWEOS Headless Mode
  (aweos.mode=gui / /dev/fb0) (aweos.mode=headless / fallback)
       │                                   │
  Native C Window Manager             Serial / Getty Shell
  (/usr/bin/aweos-wm)                     (ash)
       │
  AWEOS Compositor & Shell
       │
  Graphical PTY Terminal Window
```

## Persistent Root Filesystem & Userspace Architecture
- **Persistent ext4 Rootfs (`build/rootfs.img`)**: Contains complete Unix directory structure (`/bin`, `/sbin`, `/usr`, `/etc`, `/dev`, `/proc`, `/sys`, `/run`, `/tmp`, `/var`, `/home`, `/root`, `/opt`, `/mnt`, `/srv`).
- **User Accounts & Auth**: Standard Unix account files (`/etc/passwd`, `/etc/group`, `/etc/shadow`, `/etc/shells`) defining `root` and `aweos` user.
- **Init System (`/sbin/init`)**: Mounts virtual filesystems (`proc`, `sysfs`, `devtmpfs`, `devpts`, `tmpfs`), configures hostname (`aweos`), launches networking daemon (`/sbin/aweos-network`), displays boot logos, and manages getty/login shell.

## AWEOS System Utilities & Package Manager
- **`aweos` / `aweos-info`**: System metrics display tool (version, kernel, architecture, uptime, memory, CPU, rootfs usage).
- **`aweos-diagnostics`**: Automated system health and virtual filesystem diagnostic tool.
- **`awepkg`**: Package manager supporting local `.awe` packages (manifest verification, installation, removal, info, and package tracking under `/var/lib/awepkg`).

## Hardware Support & Verification Status

### QEMU Verification
- **STATUS: QEMU VERIFIED**
- Fully verified in QEMU BIOS (`make qemu-bios` / `make test-bios`) and QEMU UEFI (`make qemu-uefi` / `make test-uefi`).
- VirtIO block & net devices operational.

### Physical PC Hardware Support
- **STATUS: HARDWARE COMPATIBLE (UNTESTED ON PHYSICAL RIGS)**
- Built with standard PC hardware kernel drivers enabled (SATA/AHCI, NVMe, USB XHCI/EHCI, USB HID, USB storage, PS/2, Framebuffer/EFI VGA console, Ethernet e1000/r8169).
- Produces `build/AWEOS-x86_64.iso` for optical/virtual media and `build/AWEOS-x86_64-disk.img` for raw USB/disk flashing.
- **WARNING**: Never write `AWEOS-x86_64-disk.img` directly to physical drives (`/dev/sdX` or `/dev/nvmeX`) without backing up data first.

## GUI Stack Architecture & Components
- **Native C Graphical Stack (`src/gui/`)**: Built independently of external Desktop Environments (GNOME, KDE, Xfce, LXQt, etc.).
- **Graphics Abstraction (`src/gui/graphics.c`)**: Double-buffered `/dev/fb0` Linux framebuffer driver supporting EFI/VESA and DRM/KMS fbdev emulation.
- **Input System (`src/gui/input.c`)**: Event device abstraction for Linux `/dev/input/event*` keyboard scancodes and mouse events with PS/2 fallback.
- **Compositor & Window Manager (`src/gui/wm.c`)**: Native AWEOS window manager handling surface layout, panel rendering, mouse cursor composition, title bars, and z-ordering.
- **Graphical Terminal Window**: Spawns live `/bin/sh` or standard AWEOS login shell via Unix PTY (`/dev/ptmx`), rendering command output graphically in real-time.
- **Boot Modes & Graceful Fallback**: Supports `aweos.mode=gui` (default) and `aweos.mode=headless`. Automatically falls back to terminal mode if framebuffer initialization fails.

## Build System Usage

- `make` or `make build`: Verify `/linux` immutability, build out-of-tree kernel, native GUI stack, rootfs image, initramfs, ISO (`build/AWEOS-x86_64.iso`), and raw disk image (`build/AWEOS-x86_64-disk.img`).
- `make iso`: Assemble ISO image.
- `make disk-image`: Assemble raw bootable disk image.
- `make verify-linux-readonly`: Execute read-only integrity check on `/linux`.
- `make test`: Run automated QEMU BIOS, UEFI, and GUI verification tests.
- `make test-gui`: Run automated QEMU GUI boot marker test and QMP screenshot capture (`build/aweos-gui-screenshot.png`).
- `make qemu-gui`: Launch interactive QEMU graphical desktop boot mode.
- `make qemu-bios`: Launch ISO interactive boot test in QEMU BIOS mode.
- `make qemu-uefi`: Launch ISO interactive boot test in QEMU UEFI mode.
- `make clean`: Clean build artifacts in `build/`.
