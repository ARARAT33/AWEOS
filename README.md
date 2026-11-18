# AWEOS — Architecture and product status

> **Verified status (2026-11-18):** AWEOS is an x86_64 Linux-based OS project using the upstream Linux kernel and Limine. The repository can build kernel/rootfs/ISO artifacts, but the inspected CI has not yet demonstrated a successful BIOS/UEFI boot into a ready AYUI desktop. AYUI is an in-progress Rust/Smithay desktop; the alternate GNOME profile is based on Ubuntu Noble. AWEOS is not yet a fully independent kernel, production desktop, package ecosystem or distributed network platform.

See docs/IMPLEMENTATION-STATUS.md for the verified/partial/not-implemented breakdown and current blockers.

## Current desktop and boot profiles

- Default AWEOS_DESKTOP=ayui: BusyBox-based minimal rootfs that launches the Rust AYUI executable. The compositor currently uses Smithay's Winit backend and the minimal image launches it as UID 0; a tested bare-metal DRM/KMS session and unprivileged desktop split remain outstanding.
- Alternate AWEOS_DESKTOP=gnome: Ubuntu Noble GNOME userspace built from Ubuntu packages. This is a compatibility distribution profile, not an independently implemented AWEOS desktop.
- The kernel source under /linux is upstream Linux and is built out-of-tree. AWEOS does not yet have an independent kernel implementation.
- The current product target is x86_64. ARM64 and broad hardware support are not claimed as tested.

The live-image, rootfs, boot and desktop readiness requirements are enforced by the build scripts and QEMU checks. A kernel image or ISO build alone is not considered a successful OS boot.

## Overview

AWEOS is an active x86_64 Linux-based OS project. It combines the upstream Linux kernel, Limine boot assets, a BusyBox-based minimal rootfs, an in-progress Rust/Smithay AYUI desktop and bundled Rust applications. Kernel/rootfs/ISO artifact creation is implemented, but the inspected CI has not yet demonstrated a successful BIOS/UEFI boot into a ready AYUI desktop. See docs/IMPLEMENTATION-STATUS.md before treating any subsystem as production-ready.

## Core rules and isolation

- The upstream Linux source under /linux is kept unchanged during ordinary builds and tests.
- Kernel configuration and build output are generated out-of-tree.
- The read-only guard runs before and after the build/test pipeline.

## C prototype infrastructure (src/core/)

Selected C modules have standalone regression tests, but the C tree is not the active Rust/Cargo userland build. The storage prototype currently enumerates block-device names and sizes from /proc/partitions; it does not implement complete GPT/MBR, filesystem UUID or free-space discovery. The transaction state machine deliberately stops before target-volume staging/deployment and must not report a successful installation. See docs/IMPLEMENTATION-STATUS.md.

## Package management status

The current scripts/awepkg.sh utility supports read-only list and info queries against package metadata. Install and remove are intentionally disabled until a trusted package format, cryptographic signature verification, archive path validation, atomic staging, ownership tracking and rollback are implemented.

The C code under src/aosin/ is a legacy format prototype; it is not part of the active Cargo workspace or the default image build and must not be treated as a production package manager. The .asp, .asa and .aosin names are design/prototype labels, not verified production package formats.

## AYUI desktop

The active image uses the Rust AYUI application under AWEUI/ and the Rust system applications under APPS/SYSTEM/. AYUI currently uses Smithay's Winit backend and is not yet validated as a bare-metal DRM/KMS desktop. The older C code under src/gui/ is a prototype and is not part of the current Cargo workspace/image build.

## Legacy C tool prototypes

The C sources under src/updater/, src/installer/ and src/wlin/ contain historical prototypes and are not built by the active root Makefile or included in the current Cargo workspace image. The transaction engine intentionally refuses target-volume deployment. Do not treat the updater, graphical installer or USB-less migration flow as operational until their complete backends and destructive-operation tests are implemented.

## Current build system

The active root Makefile exposes these targets:

- make build: Verify /linux immutability, build the Rust workspace, build the x86_64 Linux kernel out-of-tree, assemble the rootfs/initramfs, create the hybrid ISO and disk image, and validate artifacts.
- make test-shell: Run shell/C safety regressions, including the fail-closed transaction, storage and package-manager checks.
- make test-rust: Run the active Cargo workspace tests.
- make test: Run the Linux read-only check, shell regressions and Rust tests.
- make test-qemu: Boot-test BIOS and UEFI paths and require the rootfs hand-off plus AYUI compositor first-frame readiness.
- make verify-linux-readonly: Confirm ordinary builds/tests did not change the vendored kernel source.
- make clean: Remove generated files under build/.

There are no active root Makefile targets for the legacy C aosin, updater or WLIN prototypes. Do not infer that those binaries are included in the current image.
