# AWEOS Architecture & Boot System Documentation

## Overview
AWEOS is an x86_64 operating system base powered by the Linux kernel source and the Limine bootloader.

## Core Rules & Isolation Policy
- **`/linux` Read-Only Rule**: The upstream Linux kernel source tree in `/linux` is strictly read-only. No files inside `/linux` are added, modified, formatted, patched, or created.
- **Out-of-Tree Builds**: All Linux kernel configuration and build outputs are generated entirely in `build/linux-x86_64/`.

## Boot Sequence Architecture
```
    Firmware (BIOS / UEFI)
             ↓
Limine Bootloader (v12.6.1)
             ↓
Linux Kernel (x86_64 bzImage)
             ↓
Separate AWEOS Initramfs (cpio.gz)
             ↓
       AWEOS /init
             ↓
    AWEOS ASCII Boot Logo
             ↓
  AWEOS BOOT SUCCESS
 AWEOS TERMINAL READY
             ↓
BusyBox Interactive Terminal
```

## Limine Integration
Limine v12.6.1 bootloader artifacts located in `Bootloader/x86_64/` are used directly:
- `limine-bios.sys` & `limine-bios-cd.bin` for BIOS boot.
- `limine-uefi-cd.bin` & `BOOTX64.EFI` for UEFI boot.
- `limine.conf` uses Limine Linux protocol syntax:
  ```ini
  timeout: 1
  serial: yes

  /AWEOS Linux x86_64
      protocol: linux
      kernel_path: boot():/boot/bzImage
      module_path: boot():/boot/aweos-initramfs.cpio.gz
      cmdline: console=ttyS0,115200
  ```

## Initramfs & Userspace Environment
The initramfs is packed into `build/aweos-initramfs.cpio.gz` using standard `busybox-static` applets.
The `/init` script mounts `/proc`, `/sys`, `/dev` (devtmpfs), `/tmp`, and `/run`, outputs the AWEOS boot banner, displays the mandatory success markers:
- `AWEOS BOOT SUCCESS`
- `AWEOS TERMINAL READY`

And spawns an interactive shell via `cttyhack /bin/sh`. Standard Linux commands (`ls`, `cd`, `pwd`, `cat`, `echo`, `mkdir`, `cp`, `mv`, `rm`, `touch`, `chmod`, `ps`, `mount`, `uname`, `free`, `df`, `ip`, `dmesg`, `clear`, `env`, `reboot`, `poweroff`, `shutdown`) execute natively.

## Build System Usage

- `make` or `make build`: Build the out-of-tree Linux kernel, construct initramfs, and assemble `build/AWEOS-x86_64.iso`.
- `make test`: Execute QEMU automated BIOS and UEFI boot tests and verify `AWEOS BOOT SUCCESS` / `AWEOS TERMINAL READY`.
- `make qemu-bios`: Launch ISO interactive boot test in QEMU BIOS mode.
- `make qemu-uefi`: Launch ISO interactive boot test in QEMU UEFI mode.
- `make clean`: Clean build artifacts.
