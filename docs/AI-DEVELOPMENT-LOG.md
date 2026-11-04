# AWEOS AI Development Log

## 2026-11-04 — AYUI bare-boot fallback and framebuffer safety

### Repository and CI inspection

- Inspected the current default branch, open PR stack, recent commits, and
  latest Actions runs before editing.
- PR #30/#32 userland validations passed, but the full image/boot workflow
  failed after rootfs handoff because Smithay's Winit backend had no host
  `DISPLAY` or `WAYLAND_DISPLAY` inside the bare QEMU guest.
- The existing `src/gui` framebuffer implementation was not built or packaged
  by the default rootfs path. Its launcher also exposed static/demo app entries,
  so it was not safe to present that UI as a full desktop.
- The scheduled Linux sync on the default branch failed while replacing
  `/linux` in the working tree. PR #25 already contains an index-only sync
  implementation and an isolated Git regression test; this run does not
  duplicate that work.
- The active PR stack remains unmerged. This work is based on PR #32's head and
  is proposed as a follow-up, not a direct change to `master`.

### Implemented

- Added a hardened C framebuffer fallback build to the AYUI rootfs path.
- Added framebuffer geometry, pitch, memory-size, and RGB bitfield validation.
- Added pixel conversion for 16-, 24-, and 32-bpp framebuffer layouts; invalid
  or overlapping layouts fail closed instead of assuming a pixel format.
- Changed the fallback launcher to expose only the working PTY terminal and a
  read-only root-directory snapshot; unimplemented static entries are no
  longer exposed by this fallback.
- Added first-frame readiness reporting after the framebuffer copy, not during
  initialization.
- Updated the PID 1 session supervisor to try Winit, then fbdev, then recovery.
- Updated QEMU boot validation to accept either a first-frame Winit compositor
  or a first-frame fbdev fallback, while failing if recovery later takes over.
- Added isolated C build and pixel-format regression tests.
- Kept all edits outside `/linux`; no disk installation or user-data operation
  was added.

### Files changed

- `Makefile`
- `README.md`
- `src/gui/ayui.h`
- `src/gui/graphics.c`
- `src/gui/graphics.h`
- `src/gui/ayui_session.c`
- `src/apps/apps.c`
- `scripts/aweos-session.sh`
- `scripts/build-rootfs.sh`
- `scripts/validate-rootfs-layout.sh`
- `scripts/run-qemu-tests.sh`
- `scripts/test-aweos-session-fallback.sh`
- `scripts/test-qemu-test-runner.sh`
- `scripts/test-rootfs-runtime-validation.sh`
- `scripts/test-ayui-framebuffer-build.sh` (new)
- `scripts/test-ayui-framebuffer-format.sh` (new)
- `docs/AI-DEVELOPMENT-LOG.md` (new)

### Validation

- Existing CI results inspected before this change do not validate these edits.
- New C build, pixel-format, rootfs, session-supervisor, and QEMU-runner tests
  are wired into `make test-shell`.
- Final results must come from this branch's new GitHub Actions runs. No
  BIOS/UEFI success is claimed until the image boots and emits a first-frame
  AYUI marker.

### Remaining blockers

- Native Smithay DRM/KMS is still not implemented. fbdev is a limited fallback,
  not an accelerated or multi-monitor compositor.
- The framebuffer path still needs QEMU BIOS/UEFI and physical-hardware tests
  for EFI/VESA framebuffer modes and input devices.
- Installer/updater transaction code remains deliberately fail-closed until
  real staging, deployment, bootloader, verification, and rollback backends
  exist.
- Signed package repositories, dependency resolution, sandboxing, and a
  complete network platform remain incomplete.
- ISO verification still needs a trusted expected SHA-256 or signature path.

### Next priorities

1. Inspect the new branch's actual CI logs and fix compile/runtime regressions.
2. Verify BIOS, UEFI, and direct-kernel QEMU boot with the framebuffer marker.
3. Add a screenshot/framebuffer capture assertion for the QEMU guest.
4. Design a separate native DRM/KMS backend using Smithay's udev/session/DRM
   APIs; do not describe fbdev as accelerated or multi-monitor capable.
5. Continue installer staging and ISO signature verification only behind
   fail-closed APIs and preservation tests.


## 2026-11-04 — AYUI framebuffer visible-region and device validation

### Review findings

- Inspected PR #33 current head (031e925) and its latest userland and
  image/boot workflow states before making this follow-up.
- The actual userland workflow #41777233762 passed, including the framebuffer
  build/format tests, session fallback regression, QEMU runner tests, Rust
  workspace tests, release binaries, and the Xvfb compositor smoke test.
- The full image/BIOS/UEFI workflow #41777233854 had completed all pre-image
  checks and was still building images at inspection time; no new boot result
  was available yet.
- Code review found that fbdev drawing ignored xoffset and yoffset from
  fb_var_screeninfo, and the previous bounds check only accounted for
  line_length multiplied by yres. A non-zero virtual-screen offset could
  therefore draw into the wrong visible region or exceed the validated
  mapped extent.
- The previous implementation also accepted non-truecolor, rotated, wrapped,
  or MSB-right layouts even though its pixel conversion assumes packed
  truecolor bitfields.

### Implemented in follow-up branch

- Require the selected framebuffer path to resolve directly to a character
  device; open it with O_NOFOLLOW and O_CLOEXEC.
- Accept only packed-pixel truecolor modes with standard bit ordering and no
  unsupported rotation, non-standard encoding, grayscale, or Y-wrap mode.
- Include virtual-screen xoffset/yoffset when validating pitch and mapped
  memory bounds.
- Use checked 64-bit offset arithmetic before mapping and before every frame
  copy; refuse a frame if the complete visible region does not fit.
- Render into the selected visible region instead of always writing from
  framebuffer byte zero.
- Guard rectangle edge arithmetic against signed integer overflow.
- Extend the C regression to test non-zero virtual-screen offsets, untouched
  guard bytes, and rejection of a truncated mapped-memory extent.
- Run the framebuffer format regression with AddressSanitizer and
  UndefinedBehaviorSanitizer.
- No changes to /linux; no disk, partition, installer, updater, or user-data
  writes are introduced.

### Files changed

- src/gui/ayui.h
- src/gui/graphics.c
- scripts/test-ayui-framebuffer-format.sh
- README.md
- docs/AI-DEVELOPMENT-LOG.md

### Validation

- The pre-existing PR #33 userland run #41777233762 passed before this
  follow-up and does not validate these new edits.
- The new ASan/UBSan framebuffer regression and full userland/image/boot
  workflows must pass on this follow-up head before it is considered ready.
- BIOS/UEFI first-frame output and real hardware framebuffer modes remain
  unverified until the corresponding end-to-end jobs complete.

### Next priorities

1. Inspect the new branch's actual CI logs, especially the sanitizer test.
2. Confirm BIOS, UEFI, and direct-kernel boots reach the fbdev first-frame
   marker without recovery takeover.
3. Capture and inspect a QEMU framebuffer screenshot rather than relying only
   on a serial readiness marker.
4. Continue the native Smithay DRM/KMS path as a separate backend; do not
   describe fbdev as accelerated or multi-monitor capable.
