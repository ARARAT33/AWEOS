# AWEOS implementation status

**Snapshot date:** 2026-11-18  
**Scope:** current master source and the GitHub Actions results inspected for this snapshot.

This document distinguishes code that exists from capabilities that have been demonstrated. A file, UI label, command name, or build target is not evidence that a feature works end-to-end.

## Verified foundation

- The repository vendors the upstream Linux source under /linux and builds it out-of-tree for x86_64.
- Limine BIOS/UEFI boot assets and scripts exist; the image pipeline can build a kernel, rootfs, initramfs, hybrid ISO and disk image.
- The default minimal rootfs uses BusyBox init and starts the Rust AYUI executable. It currently starts the desktop as UID 0.
- The alternate AWEOS_DESKTOP=gnome profile builds an Ubuntu Noble GNOME userspace. This is a Linux distribution profile, not an independent AWEOS desktop stack.
- The active Cargo workspace contains the Rust AYUI compositor/framework and bundled Rust applications.
- The build and test workflows include Rust workspace tests, shell regression tests, kernel build/image steps and QEMU boot/readiness checks.
- The C transaction engine explicitly refuses to proceed past the unimplemented target-volume staging backend. This is the correct fail-closed behavior, not a completed installer.

## Partial implementations

| Area | What exists | What is not yet proven or implemented |
|---|---|---|
| Kernel and boot | Upstream Linux, x86_64 config, Limine assets, out-of-tree build | No independent kernel; BIOS/UEFI boot-to-desktop is not yet green in the inspected CI runs; no validated ARM64 port |
| AYUI | Rust/Smithay compositor code, Wayland protocol handling, basic window/workspace state, bundled CLI apps | The compositor uses Smithay's Winit backend; bare-metal DRM/KMS session, full shell, multi-monitor, accessibility and successful first-frame boot are not demonstrated |
| IPC | Unix socket, private runtime directory, owner-only permissions and peer UID check on the active hardening branch | The minimal rootfs still runs the compositor as root; no privilege-separated broker/capability model or framed protocol |
| Storage | Linux block-device enumeration from /proc/partitions in C prototype code | No complete GPT/MBR, filesystem UUID, free-space or safe partition-management implementation |
| Installer/updater | Transaction state machine and validation scaffolding | Target-volume staging, deployment, bootloader writes, rollback and installed-system verification intentionally fail closed |
| Packages | Read-only metadata listing/info in awepkg | Trusted package format, signatures, dependency resolution, safe extraction, atomic install, uninstall ownership and rollback are not implemented |
| Network | Kernel networking and basic OS facilities are available through Linux | No AWEOS distributed network platform, device identity, discovery, secure peer mesh or distributed resource scheduler |
| Hardware | Linux upstream drivers are available according to kernel configuration | No product-level certification matrix; audio, GPU, Wi-Fi, Bluetooth, touch and multi-device support are not claimed as tested |

## Important safety constraints

- Do not describe the vendored upstream Linux kernel as an independently developed AWEOS kernel.
- Do not claim a successful boot or desktop session until QEMU/real-hardware logs contain the rootfs hand-off and AYUI first-frame readiness markers.
- Do not expose package installation/removal until package signatures, archive path validation, least-privilege staging, atomic commit and rollback are implemented and tested.
- Do not claim installer/updater success while the transaction backend returns a fail-closed error.
- Do not treat a desktop screenshot, menu entry or placeholder label as evidence of a working service.
- Keep /linux unchanged during normal builds and tests. The scheduled upstream-sync workflow is the only intended writer to that subtree.

## Current blocking CI evidence

- The inspected master full-image run #44077210131 completed kernel/rootfs/ISO assembly and /linux checks, then failed the BIOS QEMU boot test. Its serial log was empty and the emulator trace ended with a CPU reset/triple fault. This does not prove the kernel or rootfs started.
- The inspected master Linux-sync run #44079563272 failed after git rm because the linux directory remained on disk but was absent from the index. The guarded cleanup fix is under review in PR #59.
- AYUI IPC hardening and shared-client migration are under review in PR #58. The exact-head Userland Validation must pass before that change is considered verified.

## Recommended order

1. Restore a passing, exact-head userland test baseline for PRs #58 and #59.
2. Diagnose the BIOS reset with a bounded QEMU interrupt trace; preserve strict rootfs and compositor readiness checks.
3. Split the AYUI desktop into an unprivileged session user and a narrowly scoped privileged broker.
4. Replace the Winit-only bare-metal path with a tested DRM/KMS backend and add QEMU/real-hardware display/input tests.
5. Design and implement a signed package format and transactional package backend before enabling install/remove.
6. Implement the network platform as a separate, testable service stack with offline local-network operation.
7. Add hardware support only alongside device-specific tests and a published support matrix.
