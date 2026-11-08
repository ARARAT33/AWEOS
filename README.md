# AWEOS

AWEOS is an x86_64 Linux-based operating-system project with its own boot
integration, root filesystem, initramfs, Rust-based AYUI desktop work, system
utilities, package-management experiments, and C installer/updater components.

> **Development status — 2026-11-08: not production-ready.** The repository has
> working component tests and an image-build pipeline, but full BIOS/UEFI
> end-to-end boot and real-hardware validation are not yet established. The
> latest qemu64 trace identifies an AVX instruction in the host-provided BusyBox
> binary as a userspace invalid-opcode fault after the kernel starts. Draft PR
> #46 replaces that host binary with a pinned static x86-64 baseline build and
> adds ELF ISA checks. Its first full image build then exposed a missing Linux
> UAPI header (`linux/kd.h`) while compiling BusyBox's `kbd_mode` applet. The
> follow-up branch `fix/busybox-linux-uapi-headers-20261108` now installs
> `linux-libc-dev`. Its first rerun showed that `musl-gcc`'s `-nostdinc` mode
> still hides distro UAPI headers, so the branch now adds those headers after
> musl's own include directories and preflights the real compile path. The
> latest full image build passed the Linux UAPI header preflight but failed
> in BusyBox's optional `tc` applet because the current Linux UAPI no longer
> exports legacy CBQ types (`TCA_CBQ_*`). AWEOS's required bootstrap applet set
> does not include `tc`; PR #48 now disables that unsupported optional applet
> while retaining the other BusyBox networking utilities. A fresh image build
> and BIOS/UEFI/direct-kernel boot results are still pending. Do not
> use the installer/updater to modify a disk containing valuable data. Both
> the C transaction path and the Rust GUI installer now fail closed: the
> previous Rust flow automatically selected the first disk and repartitioned
> and formatted it without a tested data-preserving backup/rollback path.
> Unattended `--auto` installation is disabled even if the legacy environment
> override is set. No target disk is selected automatically. See
> [installer safety status](docs/INSTALLER-SAFETY.md).

## Current implementation

- **Kernel and boot:** the vendored `/linux` kernel source is strictly
  read-only. Kernel configuration and build output are kept out of tree under
  `build/linux-x86_64/`. Limine is used for BIOS/UEFI hybrid ISO assembly.
- **Initramfs and root filesystem:** the image pipeline builds an ext4 root
  image and a BusyBox initramfs. BusyBox is built from a SHA-256-pinned upstream
  source archive with static musl linking and explicit x86-64 baseline flags;
  the build does not copy an ISA-optimized BusyBox from the host runner. Rootfs
  validation disassembles packaged ELF binaries and rejects detected AVX/AVX2/
  AVX-512, BMI, and other post-baseline instructions. The initramfs validates
  AWEOS identity before
  switching root. It probes ext4 with `ro,noload`; live sessions use a tmpfs
  overlay. Persistent root writes require the explicit
  `aweos.root-rw=1` boot parameter after identity verification.
- **AYUI:** the Rust Smithay/Winit compositor remains the nested Wayland
  backend and is validated under Xvfb. Bare boots first try it, then fall back
  to a separate C fbdev session that opens the kernel framebuffer, validates
  the character device, visible virtual-screen offsets, pitch, mapped-memory
  bounds, and packed truecolor channel layout before rendering a first frame.
  It exposes only a PTY terminal and a read-only root-directory snapshot. The
  fallback supports 16/24/32-bpp layouts with standard bit ordering and rejects
  unsupported modes instead of guessing. It is a limited recovery desktop,
  not a native DRM/KMS compositor; GPU acceleration, multi-monitor, and full
  input-device support remain unverified.
- **Installer and updater:** both the C transaction engine and Rust GUI
  installer fail closed. The Rust whole-disk partition/format API is disabled,
  the first disk is not auto-selected, the default password is empty, and
  `--auto` cannot bypass the safety hold. The installer remains a preview only
  until a data-preserving target-volume staging, backup, verification,
  bootloader deployment, and rollback backend is implemented and tested.
  Disk formatting and partitioning are not performed by initramfs root
  discovery.
- **Package management:** `awepkg` validates archive paths and entry types,
  refuses overwrites and symlink traversal, records SHA-256 ownership hashes,
  rolls back interrupted installs, and preserves locally modified files on
  removal. Unsigned installation is disabled by default; the
  `AWEPKG_ALLOW_UNSIGNED=1` override is development-only, not signature
  verification. Legacy C AOSIN v1 APIs fail closed instead of generating
  dummy payloads. Dependency resolution, trusted signing/key management,
  sandboxing, and a full repository lifecycle remain unimplemented. See
  [package security status](docs/PACKAGE-SECURITY.md).
- **CI:** shell/C regression tests, Rust workspace tests, userland release
  builds, ISO assembly tests, QEMU runner tests, compressed-kernel and userland
  ISA checks, and the `/linux` integrity check run through GitHub Actions.

## Boot and root-mount policy

See [Boot and root-filesystem mounting](docs/BOOT-AND-ROOT-MOUNT.md) for the
supported command-line parameters and the read-only defaults.

- Live media discovery looks for an embedded `rootfs.img` without mounting
  arbitrary disks read-write.
- An installed root must be selected explicitly with
  `aweos.root=/dev/<partition>` (or `root=/dev/<partition>`).
- A verified installed root is read-only by default and receives a temporary
  overlay. Persistent writes require `aweos.root-rw=1`.
- UUID-based root selection is not implemented yet.
- A failed identity check or mount handoff enters recovery rather than
  selecting another disk or claiming a successful boot.

## Build profiles

- Default AYUI profile: `make image`
- Optional GNOME rootfs profile: `AWEOS_DESKTOP=gnome make image`
- Override GNOME rootfs size with `AWEOS_ROOTFS_SIZE_MB`.
- Build output defaults to `build/`; use a dedicated build directory.
- Build directories are ownership-marked; non-empty unmarked paths are refused. See [build output directory safety](docs/BUILD-OUTPUT-SAFETY.md) before adopting an existing directory.

The main Make targets currently defined in the repository are:

| Command | Purpose |
| --- | --- |
| `make test-shell` | Shell syntax checks and C/shell safety regressions |
| `make test-rust` | Rust workspace tests |
| `make test` | Read-only boundary, shell/C, and Rust tests |
| `make image` | Build the hybrid ISO and BIOS disk image |
| `make test-qemu` | Exercise BIOS, UEFI, and direct-kernel QEMU boot paths |
| `make verify-linux-readonly` | Verify that the vendored `/linux` tree is unchanged |

The full image and QEMU targets require the host dependencies installed by
[the x86_64 GitHub Actions workflow](.github/workflows/build-aweos-x86_64.yml),
including a Limine host utility, QEMU, OVMF, xorriso, the musl toolchain
(`musl-tools`/`musl-gcc`), Linux UAPI development headers
(`linux-libc-dev`), cpio, and ext4 tools. The build downloads and verifies
its pinned BusyBox source archive; a host BusyBox executable is not required.

## Architecture

```text
Limine (BIOS / UEFI)
        |
        v
Linux kernel (out-of-tree build; /linux source read-only)
        |
        v
BusyBox initramfs
  - explicit root selection
  - read-only identity verification
  - tmpfs overlay for live/default sessions
        |
        v
Verified AWEOS root filesystem
        |
        v
AWEOS init / session supervisor
        |
        +---- Smithay/Winit nested compositor
        |       (used when an existing X11/Wayland display is available)
        |
        +---- AYUI fbdev fallback
        |       (real framebuffer output; terminal + read-only root listing)
        |
        +---- recovery console
```

## Safety invariants

1. **`/linux` is read-only.** No patches, generated files, formatting, or
   build outputs may be written inside it. CI verifies this boundary.
2. **No implicit disk selection.** An installed root requires an explicit
   device parameter and AWEOS identity metadata.
3. **Read-only discovery.** ext4 probes use `ro,noload`; live media and the
   embedded root image are mounted read-only.
4. **Explicit persistent writes.** `aweos.root-rw=1` is required before a
   verified installed root is remounted read-write.
5. **Fail-closed installation.** The incomplete installer/updater transaction
   backend must not format, repartition, overwrite, or claim success.
6. **No false boot success.** Root readiness is reported only after identity
   and mount setup succeed. AYUI readiness is reported only after a backend
   submits its first frame; recovery is reported separately.

## Development notes

Changes should be made on an isolated branch and reviewed through a pull
request. Do not merge a stacked PR until its base PR is merged or the stack is
otherwise reconciled, and require fresh checks on the final head. A successful
unit or Xvfb test is not evidence of full BIOS/UEFI or physical-hardware
compatibility.
