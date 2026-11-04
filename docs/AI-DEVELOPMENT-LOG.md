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
- The full image workflow #41777233854 built the ISO and disk image and
  verified /linux, but the primary qemu64 BIOS/UEFI/direct-kernel boot step
  failed. Its max-CPU diagnostic retry reached BIOS and UEFI framebuffer
  readiness; the direct-kernel path reached rootfs but had no /dev/fb0.
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
- Validate xoffset/yoffset against the reported virtual resolution, then
  include those offsets when checking pitch and mapped-memory bounds.
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


## 2026-11-04 — Cross-PR integration audit

- The current AYUI/boot stack (PRs #27, #28, #30, #32, #33, #35, and #37)
  is not the whole repository's security stack. The branch was inspected
  against the separate package and ISO-validation PRs before any merge claim.
- The current stack still contains the legacy src/core/iso_verify.c that
  accepts any regular file larger than 1 MiB and fills in a hard-coded empty
  SHA-256 value. PR #29 contains the fail-closed replacement and a regression
  test; its userland and core-preservation workflows passed, while its full
  image workflow failed at ISO assembly because it did not yet include the
  hybrid-ISO EFI argument correction from PR #28. The final combined stack
  must re-run image construction and boot validation after reconciling #29.
- The current stack also still contains the older scripts/awepkg.sh. PR #21
  contains the path/collision/hash/rollback hardening and its dedicated
  package-safety workflow plus userland validation passed. Its full boot
  workflow failed because the then-current AYUI Winit backend could not start
  in a headless QEMU guest. The package branch is separate from the boot stack
  and must be reconciled and revalidated before package safety is claimed for
  the product branch.
- Do not merge or describe the current PR stack as production-ready until
  these sibling security changes are integrated, their tests pass on the
  final combined head, and BIOS/UEFI boot succeeds with the current AYUI
  fallback. No branch or commit was deleted or force-pushed.


## 2026-11-04 — Separate direct-kernel headless validation from firmware desktop boot

### QEMU evidence reviewed

- Full image construction and /linux read-only checks passed in workflow
  #41777233854, but its primary qemu64 BIOS/UEFI attempts triple-faulted
  before the verified rootfs hand-off.
- The diagnostic retry using QEMU CPU model max booted BIOS and UEFI through
  the verified rootfs and reached the AYUI fbdev first-frame marker at
  1280x800, 32 bpp.
- The same direct-kernel retry reached the verified rootfs but had no
  /dev/fb0. This is expected for a kernel loaded directly with -kernel/-initrd:
  that path bypasses Limine and firmware framebuffer hand-off, so it is not
  a valid desktop test.
- The previous QEMU runner incorrectly required a compositor/fbdev marker in
  direct-kernel mode and therefore reported that test as a failure even
  though the kernel/initramfs reached the rootfs. BIOS/UEFI remain the actual
  desktop boot tests.

### Implemented in follow-up branch

- Direct-kernel QEMU boot now passes aweos.mode=headless explicitly.
- The runner requires both AWEOS ROOTFS READY: mode=headless and
  AWEOS HEADLESS CONSOLE READY for that path; a mounted rootfs alone is not
  considered sufficient.
- BIOS and UEFI continue to require a real first-frame AYUI compositor or
  fbdev readiness marker, and still fail if the recovery console takes over.
- The mock-QEMU regression now models headless direct boot and includes a
  negative case proving that the direct-kernel path fails without its
  headless-console marker.
- This does not change initramfs storage discovery, root mount flags, or
  firmware boot behavior. It does not make the qemu64 triple-fault issue
  disappear or claim that CPU compatibility has been solved.
- No changes to /linux and no writes to disks, partitions, or user data.

### Files changed

- scripts/run-qemu-tests.sh
- scripts/test-qemu-test-runner.sh
- docs/AI-DEVELOPMENT-LOG.md

### Validation

- The earlier PR #33 diagnostic retry proved BIOS and UEFI framebuffer
  fallback readiness on QEMU CPU model max, but its full workflow remained
  failed because the primary qemu64 attempt triple-faulted and the direct
  kernel path had no framebuffer.
- The new mock regression and full QEMU runner must pass on this branch.
- The new direct-kernel path must reach the explicit headless marker in
  actual QEMU; BIOS/UEFI must still reach their first-frame desktop markers.

### Remaining blockers

1. Diagnose why Limine/kernel startup triple-faults with QEMU qemu64 while
   the diagnostic max CPU model boots BIOS/UEFI successfully. Do not silently
   drop the qemu64 compatibility check.
2. Obtain QEMU screenshot/framebuffer capture to verify actual pixels, not
   only the serial first-frame marker.
3. Verify native hardware and firmware combinations beyond QEMU.


## 2026-11-04 — QEMU runner regression follow-up

- PR #35 userland workflow #41779212914 completed successfully. Its actual
  log confirms the framebuffer fallback hardened build, the ASan/UBSan
  framebuffer pixel/offset/bounds test, session fallback test, Rust
  workspace/release build, and Xvfb first-frame smoke test all passed.
- PR #36 userland workflow #41780062941 failed inside make test-shell after
  the build-safety, disk-image, transaction, storage, ISO, rootfs, framebuffer
  sanitizer, and session-fallback tests had passed.
- Inspecting the actual job log and mock runner showed the failure was a stale
  assertion: the runner's recovery message had been clarified, but the test
  still grepped for the old wording. Updated the assertion to the exact new
  message. This is a test expectation correction, not a product behavior
  change; the corrected test still requires a non-zero runner exit when
  recovery takes over.
- The corrected test has not yet been rerun on a fresh head and remains
  pending validation.


- PR #36 was closed as superseded after its actual userland run exposed the
  stale recovery-message assertion; its branch and commits were retained.
- PR #37 contains the corrected assertion and is the active validation PR
  for the direct-kernel headless test. Its fresh CI runs are pending.


## 2026-11-04 — Package subsystem fail-closed hardening

- Inspected PR #37 head `e4b47c2c50e91e97e6abe54b81fdd1bc99b1766b`, current open boot/AYUI PR stack, recent
  Actions runs, and package sources before editing.
- Found the active stack still had a legacy `awepkg` implementation that
  copied archive payloads into `/` with `cp -rf`, ignored copy failures, and
  removed files without ownership/hash checks. PR #21 held safer code but was
  based on stale `master` and was not integrated into the boot stack.
- Found C AOSIN v1 still generated a dummy 1 KiB payload, hard-coded the
  empty-file SHA-256, and accepted a magic number as verification.
- Integrated the reviewed path/collision/archive-type/hash/rollback package
  manager protections into this active stack. Unsigned installation now
  fails closed by default; `AWEPKG_ALLOW_UNSIGNED=1` is development-only.
- Normalize installed file modes to 0755/0644, constrain the package database
  to the selected root, and test rollback with deterministic injected failure
  so the test runs as root or unprivileged user.
- All legacy C AOSIN v1 public operations now fail closed without touching
  output files, target roots, or package metadata.
- Added package-security documentation and dedicated package-safety CI.
- No changes to `/linux`, disks, partitions, installer/updater, or user data.

### Validation status

- Shell package and C AOSIN ASan/UBSan tests are wired into `make test-shell`
  and the dedicated workflow. Fresh CI results on the final PR head are
  required before merge; validation is pending.

### Remaining blockers

1. Implement signed manifests and trusted key management before enabling
   production package installation.
2. Add archive expanded-size and file-count limits.
3. Replace shell path checks with race-resistant descriptor-relative
   extraction/deployment.
4. Implement dependency resolution, repository metadata, sandboxing, and
   application permissions.
5. Replace AOSIN v1 with a real versioned format after compatibility review.


### Actual validation results (2026-11-04)

- Package-safety workflow run [#41782694987](https://github.com/ARARAT33/AWEOS/actions/runs/41782694987)
  on commit `96dc3101a165f6b3e4942f26ce0536baa97c8f5d`: **PASS**.
  The actual job completed all six steps: checkout, `/linux` read-only
  integrity, POSIX shell syntax, shell package integration, and C AOSIN
  AddressSanitizer/UndefinedBehaviorSanitizer regression.
- The shell log explicitly exercised unsigned-install rejection, outside-root
  and symlinked DB rejection, duplicate-install rejection, modified-file
  preservation, overwrite and DB-path collision rejection, archive-link
  rejection, protected base-system removal, permission normalization, and
  deterministic mid-transaction rollback.
- The C sanitizer log reported:
  `PASS: AOSIN APIs fail closed and preserve existing files, package metadata, and target roots.`
  and `PASS: AOSIN C API regression (ASan/UBSan).`
- An earlier run [#41782330916](https://github.com/ARARAT33/AWEOS/actions/runs/41782330916)
  failed because `_GNU_SOURCE` was defined both in the test source and compiler
  flags. The duplicate definition was removed; the corrected run
  [#41782422449](https://github.com/ARARAT33/AWEOS/actions/runs/41782422449)
  passed before the final DB-path and help-output assertions were added.
- Userland and full image/boot workflows on the final package head were still
  running when this log entry was written; their results must be checked
  separately and are not represented as passed here.
- The prior full boot run [#41780373297](https://github.com/ARARAT33/AWEOS/actions/runs/41780373297)
  failed in the default `qemu64` BIOS path before the kernel reached the
  rootfs hand-off. The UEFI run reached the rootfs and AYUI framebuffer
  fallback; the diagnostic retry using QEMU CPU model `max` reached the
  framebuffer desktop in BIOS and UEFI. This remains a firmware/CPU-model
  compatibility blocker, not a passing default BIOS boot.


## 2026-11-04 — Package manager target-runtime contract

- Added a second package integration pass that invokes `awepkg` through
  BusyBox `ash` and places BusyBox applets first on `PATH`, matching the
  minimal target rootfs rather than only the Ubuntu host environment.
- The rootfs validator now requires executable `/usr/bin/awepkg` and checks
  the target BusyBox binary for the applets used by archive validation,
  hashing, staging, rollback, and removal.
- The dedicated package-safety workflow installs BusyBox so this compatibility
  pass cannot silently skip on GitHub-hosted runners.
- Validation is pending on the new commit; any missing applet or unsupported
  BusyBox option will fail the test rather than shipping a host-only package
  manager.


### BusyBox compatibility regression and correction (2026-11-04)

- The first target-runtime run [#41783344894](https://github.com/ARARAT33/AWEOS/actions/runs/41783344894)
  correctly exposed a host-only assumption: BusyBox 1.37.0 `find` does not
  implement GNU `-printf`. The GNU-host package tests passed, but the BusyBox
  replay failed at file-list generation.
- Replaced GNU `find -printf` with `find -print` plus POSIX `sed` after the
  existing NUL-based newline-name check. This keeps the line-delimited
  ownership database safe while supporting BusyBox.
- Added `sed` and `rmdir` to the target BusyBox applet contract. The
  package-safety workflow is rerun on the corrected branch; no BusyBox pass
  is claimed until its fresh log completes.


### BusyBox hard-link validation regression (2026-11-04)

- The second BusyBox replay exposed a security-relevant format difference:
  BusyBox tar 1.37.0 displays a hard-link entry with a regular-file mode
  prefix followed by `-> TARGET`, whereas GNU tar uses an `h` type marker
  and `link to TARGET`. Checking only the first listing character therefore
  allowed a hard-link entry through the BusyBox path.
- Added explicit rejection of both ` -> ` and ` link to ` markers before
  extraction. The existing hard-link archive integration case now exercises
  both GNU tar and BusyBox tar output.
- This is a real security regression found by the target-runtime test; the
  previous BusyBox failure was not treated as a passing result. A fresh
  package-safety run is required before the package change is considered
  validated.

## 2026-11-04 — test-shell failure attribution for the package stack

- PR #38 head `d8875b4` passed the dedicated package-safety workflow, but both
  the userland and full image workflows failed inside the `make test-shell`
  step (exit 2) on that same commit. Raw job logs are not readable from this
  environment, so the exact failing script could not be identified from the
  step-level annotation alone.
- Code review of every test-shell script on this head found no reproduction:
  the rootfs runtime fixture and validator contract were replayed locally with
  stubbed cc/readelf/ldd and pass both the expected-failure and success
  phases; the awepkg and AOSIN suites passed in the package-safety run on the
  same commit; every other test-shell script is unchanged since PR #37's
  green userland run.
- To make CI failures attributable without raw log access, `make test-shell`
  now prints the name of each script before running it and emits a GitHub
  Actions `::error::` annotation naming the exact script that failed. The
  test list, order, and semantics are unchanged.
- No changes to `/linux`; no disk, partition, installer, updater, or
  user-data operations.

### Validation status

- This change only adds failure attribution; it does not claim any previously
  failing test is fixed. Fresh userland and package-safety runs on this new
  branch head must pass, and the annotation (if any) must be inspected before
  the underlying failure can be diagnosed and fixed.
