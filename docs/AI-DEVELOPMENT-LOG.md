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
- No changes to `/linux`; no disk, partition, installer, updater, or user-data
  operations.

### Validation status

- This change only adds failure attribution; it does not claim any previously
  failing test is fixed. Fresh userland and package-safety runs on this new
  branch head must pass, and the annotation (if any) must be inspected before
  the underlying failure can be diagnosed and fixed.

## 2026-11-04 — Attribution commit escaping defect and correction

- The first attribution commit pushed a broken `test-shell` recipe: the
  `$$script` Makefile escapes were written as single `$script`, so GNU make
  expanded `$s` to an empty string and the loop ran `bash -n "cript"`,
  which cannot exist. The resulting workflow run failed immediately inside
  the syntax-check loop and never reached the real test scripts.
- The defect was detected by the new annotation itself (the GitHub annotation
  rendered `bash -n syntax check failed for cript`), confirming the
  attribution mechanism works and that the failure came from the pushed
  recipe, not from any real AWEOS test script.
- The recipe is corrected to use `$$script`/`$$test_script` escapes. The
  corrected file was read back from the pushed branch before CI is trusted.
- The underlying `make test-shell` failure observed on PR #38 head
  `d8875b4` remains undiagnosed until a run of the corrected attribution
  completes and either passes or names the failing script.
- No changes to `/linux`; no disk, partition, installer, updater, or user-data
  operations.

## 2026-11-04 — Move test-shell execution into scripts/run-test-shell.sh

- The inline `make test-shell` attribution recipe could not be pushed
  reliably through the available API tooling: the required Makefile
  double-dollar escapes were collapsed to single-dollar forms in the pushed
  commits, so make expanded an empty variable and the loop ran
  `bash -n "cript"`, which cannot exist. Both pushed attribution commits
  (2d77c30 and 106dba2) are therefore defective in their inline recipe and
  failed CI inside the syntax-check loop before reaching any real test.
- The execution loop now lives in `scripts/run-test-shell.sh` as plain bash,
  which needs no Make-level escaping at all. The Makefile `test-shell`
  target is a single invocation of that driver. The script list, order, and
  semantics are identical to the previous Makefile recipe.
- The temporary escaping-probe file added to verify push round-tripping is
  removed with this commit.
- The underlying `make test-shell` failure observed on PR #38 head
  `d8875b4` remains undiagnosed until a run of this corrected head
  completes and either passes or names the failing script.
- No changes to `/linux`; no disk, partition, installer, updater, or user-data
  operations.

## 2026-11-04 — Trace-attributed awepkg rollback test fix and commit-temp correction

- The `make test-shell` driver (`scripts/run-test-shell.sh`) now records each
test under `bash -x` and embeds the last trace lines in the GitHub Actions
`::error::` annotation. Fresh userland runs
[#41853809647](https://github.com/ARARAT33/AWEOS/actions/runs/41853809647) and
[#41854990937](https://github.com/ARARAT33/AWEOS/actions/runs/41854990937) both
attributed the standing failure to `scripts/test-awepkg.sh`; the second run's
trace showed the BusyBox replay failing with "ERROR: injected mid-install
failure unexpectedly succeeded" in the rollback case.
- Root cause: the rollback regression injected its mid-transaction failure by
placing a mock `ln` first on `PATH`. In the userland runner's BusyBox replay
the mock was not invoked, the third payload file was published, and the
install completed, so the test correctly reported that the injection no longer
failed deterministically. The dedicated package-safety workflow used an
apt-installed BusyBox and passed, which is why code review and the
package-safety run could not reproduce the failure.
- Fix: the rollback injection no longer depends on PATH interception. The
pre-existing `z-blocked` payload parent directory is made non-writable, which
deterministically fails the staging `mktemp` for the third file in unprivileged
runs; the PATH-fronted mock `ln` is retained so root and GNU-host runs still
inject a publish failure. Either mechanism aborts the transaction and
exercises the real rollback path. A staging-leftover check was added for the
blocked directory.
- Also fixed a latent package-database bug found during review: the
commit-stage temporary names in `awepkg.sh` used PID-derived suffixes, and
one had already lost a dollar sign (`.{PKG_NAME}.files.$`). All three commit
temporaries are now created with `mktemp`, so concurrent installs cannot
collide and no PID-derived escapes remain anywhere in the package manager.
- No changes to `/linux`; no disk, partition, installer, updater, or
user-data operations.

### Validation status

- Fresh userland and package-safety runs on this head are required before the
fix is considered validated; all previous heads failed as described above.

## 2026-11-04 — Checked-out file mode regression from the API transport

- The commit that rewrote `awepkg.sh` lost the file's executable mode: the
  available push tooling commits blobs as mode 100644 and cannot restore
  100755. Both the userland run [#41856656063](https://github.com/ARARAT33/AWEOS/actions/runs/41856656063)
  and the package-safety run [#41856656113](https://github.com/ARARAT33/AWEOS/actions/runs/41856656113)
  failed with exit 126 ("Permission denied" executing `scripts/awepkg.sh`),
  attributed exactly by the new `bash -x` trace annotation.
- `scripts/test-awepkg.sh` now invokes the package manager through `sh` in
  its host pass (the BusyBox pass already did), so the suite no longer
  depends on the checked-out mode. `build-rootfs.sh` installs the rootfs
  copy with `install -D -m 0755`, so the produced image is unaffected.
- The `scripts/awepkg.sh` blob remains mode 100644 in this branch; a future
  run with direct git access should restore 100755 (for example
  `git update-index --chmod=+x scripts/awepkg.sh`) for developer
  convenience. The shebang and all functional behavior are unchanged.
- No changes to `/linux`; no disk, partition, installer, updater, or user-data
  operations.

## 2026-11-04 — Actual validation results: test-shell green on the package stack

- On commit `4fb83c9be607f59c7b3aca8e943bdb1f35eaba78` (branch
  `fix/test-shell-failure-attribution-20261104`, PR #39):
  - userland run [#41857308158](https://github.com/ARARAT33/AWEOS/actions/runs/41857308158): **PASS** —
    all 13 test-shell scripts (including the corrected awepkg suite with
    its BusyBox replay), repository boundary check, Rust workspace tests,
    release binaries, and the Xvfb compositor smoke test.
  - package-safety run [#41857308305](https://github.com/ARARAT33/AWEOS/actions/runs/41857308305): **PASS**.
  - A duplicate pair of runs ([#41857292552](https://github.com/ARARAT33/AWEOS/actions/runs/41857292552),
    [#41857292715](https://github.com/ARARAT33/AWEOS/actions/runs/41857292715)) also passed.
- This is the first fully green userland validation since the package
  fail-closed hardening entered the stack; the standing `make test-shell`
  failure attributed to `scripts/test-awepkg.sh` is resolved.
- The full build-and-boot workflow remains the known outstanding blocker:
  the default `qemu64` BIOS path triple-faults before the rootfs hand-off
  while the diagnostic `max` CPU model boots. That failure is unrelated to
  this branch and is tracked as the top boot priority.
- No changes to `/linux`; no disk, partition, installer, updater, or user-data
  operations.

### Next priorities

1. Restore mode 100755 on `scripts/awepkg.sh` with a git-capable client.
2. Diagnose the qemu64 triple-fault (BIOS boot) with QEMU debugging
   (-d int,cpu_reset) and compare Limine/kernel hand-off against the
   working `max` CPU model.
3. Reconcile PR #29 (fail-closed ISO verification) into this stack and
   re-run image construction and boot validation on the combined head.
4. Begin signed package manifests and trusted key management so
   `AWEPKG_ALLOW_UNSIGNED=1` can be retired for real installs.
5. Merge the validated PR chain (#27 through #39) toward master only
   after the boot blocker is diagnosed or an explicit merge decision
   is made by the maintainer.


## 2026-11-05 — Preserve primary QEMU CPU diagnostics across retry

### Inspection and evidence

- Re-inspected the active PR #39 head `2b59d27385cf8d2def28a1b504e007b865a4dbd4`,
  open PR stack, current workflow runs, and the QEMU diagnostic artifact from
  run [#41858076657](https://github.com/ARARAT33/AWEOS/actions/runs/41858076657).
- The full image build, ISO assembly, /linux integrity checks, and shell/C
  regression suite passed on that head. The primary QEMU `qemu64` run failed
  before rootfs hand-off in BIOS, UEFI, and direct-kernel modes; QEMU reported
  invalid-opcode (#UD), then #GP and a triple fault.
- The diagnostic retry with CPU model `max` reached the AYUI framebuffer
  first-frame marker in BIOS and UEFI and the explicit headless console in
  direct-kernel mode. This is diagnostic evidence only; it does not resolve
  the qemu64 failure.
- Found that serial logs were CPU-suffixed, but QEMU `-D` instruction/debug
  paths were hard-coded. The `max` retry therefore overwrote the primary
  `qemu64` debug logs, preventing reliable comparison of the failing and
  working CPU models.

### Implemented

- Give BIOS, UEFI, and direct-kernel QEMU debug logs the same CPU-model suffix
  as their corresponding serial logs.
- Extend the mock QEMU runner test to write a marker into each `-D` file,
  run a failing `qemu64` pass followed by a successful `max` pass, and assert
  that all six debug logs remain distinct and retain the correct CPU marker.
- Keep the primary `qemu64` boot check mandatory; no fallback to `max` is
  treated as a passing compatibility result.
- No changes to `/linux`, installer/updater behavior, disks, partitions, or
  user data.

### Files changed

- `scripts/run-qemu-tests.sh`
- `scripts/test-qemu-test-runner.sh`
- `docs/AI-DEVELOPMENT-LOG.md`

### Validation

- The new regression is wired into the existing `make test-shell` driver via
  `scripts/test-qemu-test-runner.sh`.
- A fresh GitHub Actions run on this branch is required to establish PASS.
  The prior PR #39 results do not validate this change.
- BIOS/UEFI with `qemu64` remain failed until the preserved instruction trace
  is inspected and the underlying CPU/boot issue is fixed.

### Next priorities

1. Run the QEMU runner regression and verify primary/retry debug artifacts are
   both retained.
2. Inspect the preserved qemu64 instruction trace at the faulting RIP and map
   it to the exact bootloader/kernel image.
3. Fix the underlying qemu64 compatibility fault without weakening the
   baseline CPU test.
4. Re-run image build, BIOS/UEFI desktop boot, and direct-kernel headless boot.


## 2026-11-05 — Restore QEMU runner executable mode

- The new userland workflow [#41970701983](https://github.com/ARARAT33/AWEOS/actions/runs/41970701983)
  passed on PR #40 head `767e75c3d887c405927a257be0330388a19ca476`:
  all 13 shell/C regression scripts, repository-boundary and Cargo metadata
  checks, Rust workspace tests, release binaries, expected-binary checks, and
  the Xvfb AYUI compositor smoke test succeeded.
- The full image workflow [#41970701981](https://github.com/ARARAT33/AWEOS/actions/runs/41970701981)
  built the kernel, rootfs, initramfs, and hybrid ISO and passed both
  `/linux` integrity checks. It then failed before launching QEMU:
  `./scripts/run-qemu-tests.sh: Permission denied` (exit 126). The diagnostic
  retry hit the same error, so this run produced no new BIOS/UEFI/direct-kernel
  boot result.
- Root cause: the Git tree commit that added CPU-suffixed debug paths recorded
  `scripts/run-qemu-tests.sh` as mode `100644`, although its parent had mode
  `100755`. This was a Git file-mode regression introduced by the API tree
  update, not a kernel or QEMU failure.
- Restore `scripts/run-qemu-tests.sh` to mode `100755` and add a regression
  assertion that fails the shell suite if this directly executed runner loses
  its executable bit again.
- No changes to `/linux`, installer/updater behavior, disks, partitions, or
  user data.

### Validation status

- Userland validation: PASS on the previous code head as above.
- The executable-mode assertion and corrected mode require a fresh CI run.
- QEMU boot validation remains pending; do not infer a qemu64 result from
  workflow #41970701981 because QEMU was never launched.

### Next priorities

1. Verify the executable-mode assertion and the full shell/C suite on the new
   head.
2. Re-run image build and confirm QEMU is actually launched.
3. Preserve and inspect qemu64 and max CPU debug logs separately.
4. Diagnose and fix the qemu64 boot fault without treating the max retry as
   a compatibility pass.


## 2026-11-05 — Disable the Rust whole-disk installer until data preservation exists

### Inspection and finding

- Re-inspected the repository tree outside the protected `/linux` source,
  current PR stack (#38–#40), recent workflow runs, README, build workflows,
  initramfs/session scripts, C transaction engine, package manager, and Rust
  installer sources before editing.
- Found a critical gap not covered by the C transaction fail-closed work:
  `AWEUI/installer/src/engine.rs` still called `sfdisk` and `mkfs` on the
  selected whole disk before deploying the root filesystem. The interactive
  path had no target-specific destructive confirmation or verified backup.
- `AWEUI/installer/src/main.rs` silently selected the first discovered disk.
  Its `--auto` path allowed whole-disk writes when
  `AWEOS_ALLOW_DESTRUCTIVE_INSTALL=1` was set.
- `InstallerState::default()` supplied the known password `aweos` and the
  same confirmation value. This was not a safe credential default.
- The C transaction engine already fails closed, but that did not protect the
  separate Rust GUI installer path. This change closes that bypass rather than
  duplicating C transaction work.
- Current PR #40 head `48c9dd7e32f79d2b441966b2011ba6b3e28dda39` has a green
  userland run [#41972271067](https://github.com/ARARAT33/AWEOS/actions/runs/41972271067).
  The two full image/boot runs #41972270906 and #41972263483 were still in
  progress at inspection time; no new qemu64 result is inferred from them.

### Implemented on a new stacked branch

- Disabled `engine::execute_installation` before device inspection, progress
  callbacks, target directory creation, mounting, copying, or bootloader work.
- Replaced `partition_and_format_disk` with a fail-closed compatibility
  guard; removed the reachable `sfdisk` / `mkfs.vfat` / `mke2fs` execution
  path from the Rust installer module.
- Removed automatic first-disk selection. Discovered devices are informational
  only and no target is selected.
- Disabled `--auto` unconditionally. The legacy
  `AWEOS_ALLOW_DESTRUCTIVE_INSTALL=1` environment variable no longer bypasses
  the safety hold.
- Made the Summary step non-advancing; pressing `I` reports that installation
  is disabled and exits non-zero rather than entering a fake progress flow.
- Cleared the default password and confirmation fields.
- Updated the installer screens and README to state that no disk operation is
  performed.
- Added `docs/INSTALLER-SAFETY.md` with explicit requirements before
  installation may be re-enabled.
- Added Rust unit regressions for no callbacks/no target path creation,
  disabled partitioning, empty default credentials, terminal Summary state,
  and user-visible safety disclosure.
- Added `scripts/test-installer-no-writes.sh` and a userland workflow step
  that exercises the built installer binary with the legacy override enabled
  and checks that `--auto` exits with status 2 before any disk command.

### Files changed

- `AWEUI/installer/src/engine.rs`
- `AWEUI/installer/src/partition.rs`
- `AWEUI/installer/src/state.rs`
- `AWEUI/installer/src/ui.rs`
- `AWEUI/installer/src/main.rs`
- `scripts/test-installer-no-writes.sh` (new)
- `.github/workflows/validate-userland.yml`
- `README.md`
- `docs/INSTALLER-SAFETY.md` (new)
- `docs/AI-DEVELOPMENT-LOG.md`

### Validation status

- The Rust unit and built-binary integration tests are wired into the
  userland workflow. Fresh CI on this branch is required before claiming PASS.
- The new branch is stacked on PR #40; no changes were made to `master` or
  `/linux`. No disk, partition, filesystem, bootloader, or user-data write was
  attempted during this development run.
- The active qemu64 BIOS/UEFI/direct-kernel triple-fault remains a separate
  boot blocker. The PR #40 CPU-suffixed debug-log fix must complete its fresh
  full build and preserve the primary qemu64 traces before that fault can be
  diagnosed.

### Next priorities

1. Inspect this branch's fresh userland run and the actual `--auto` test log.
2. Check PR #40's full build and retrieve both qemu64 and `max` diagnostics.
3. Diagnose the qemu64 invalid-opcode / general-protection / triple-fault
   sequence without treating the `max` retry as a qemu64 pass.
4. Replace the fake ISO verifier with a real, trusted-digest verification
   contract; until then ISO validation must fail closed.
5. Keep the installer disabled until partition-preserving staging, verified
   backup, bootloader rollback, and VM tests exist.


### Post-change CI and QEMU artifact review — 2026-11-05

#### Rust installer change validation

The final installer/UI commit at head
`e3860fd94210b51e0837b43d1eff9f6ed5c09650` has a successful userland run:

- [Validate AWEOS Userland #41974393089](https://github.com/ARARAT33/AWEOS/actions/runs/41974393089) — **success**.
- `make test-shell` — success, including build-dir, disk-image, C transaction,
  storage-discovery, ISO assembly, rootfs runtime, AYUI framebuffer, session,
  and QEMU-runner regressions.
- `verify-linux-readonly.sh` — `/linux: UNMODIFIED`.
- `cargo metadata --no-deps` — success.
- `cargo test --workspace` — success. The installer binary's test target
  reports **10 passed, 0 failed**, including the no-callback/no-target-path
  guard, disabled partition API, blank credentials, terminal Summary, and
  safety disclosure.
- All release userland binaries built and expected binaries were present.
- `scripts/test-installer-no-writes.sh target/release/aweui-installer` —
  success with `AWEOS_ALLOW_DESTRUCTIVE_INSTALL=1`; the built `--auto`
  binary still exited 2 before disk operations.
- AYUI Xvfb smoke — success; Winit bound `wayland-1` and rendered its first
  frame.

The final-head userland job is green. The full image/boot workflow
[#41974393087](https://github.com/ARARAT33/AWEOS/actions/runs/41974393087)
was still building AWEOS images at the time of this log update; no new
BIOS/UEFI result is claimed for PR #41.

#### Actual PR #40 QEMU diagnostics inspected

Downloaded and inspected the QEMU diagnostics artifact from
[full build #41972270906](https://github.com/ARARAT33/AWEOS/actions/runs/41972270906)
(artifact `AWEOS-QEMU-diagnostics`, 113,082,030 bytes).

Observed results:

- Image build and the pre-boot safety checks passed.
- Primary `qemu64` BIOS boot failed before a rootfs-ready marker. Its serial
  output stopped after Limine's handoff and `acpi: Found RSDP at 0xf5290`.
  The QEMU debug state recorded `#UD` (vector 6) at
  `RIP=0x3cd63c7`, followed by `#GP` (vector 13, error code `0x0032`),
  double fault (vector 8), and a triple fault.
- Primary `qemu64` direct-kernel serial output was empty and did not reach the
  explicit headless-console marker.
- Primary `qemu64` UEFI boot did reach the rootfs and AYUI startup. Winit
  could not create a display event loop because the QEMU run had no
  `DISPLAY`/`WAYLAND_DISPLAY`; the framebuffer fallback then initialized
  `/dev/fb0` at 1280x800 and emitted
  `AWEOS AYUI FRAMEBUFFER READY`.
- The `max` CPU diagnostic retry reached the rootfs/framebuffer fallback in
  BIOS and UEFI and emitted `AWEOS HEADLESS CONSOLE READY` for direct-kernel
  boot. This is diagnostic evidence only; it does not turn the failed
  `qemu64` BIOS/direct-kernel tests into passes.

The current primary qemu64 debug flags do not include `in_asm`, so the
instruction bytes at the failing RIP were not captured. The `max` trace is
not a substitute because it follows a different CPU feature model and does
not reproduce the qemu64 fault. Next boot-debug work must add a targeted
qemu64 instruction trace for only the failing modes, preserve the original
primary logs, and map the faulting instruction before changing kernel config
or CPU feature handling.

The full PR #40 run
[#41972270906](https://github.com/ARARAT33/AWEOS/actions/runs/41972270906)
and its duplicate
[#41972263483](https://github.com/ARARAT33/AWEOS/actions/runs/41972263483)
both completed with failure because the primary qemu64 BIOS/UEFI/direct-kernel
boot step failed. The max-CPU retry completed and uploaded diagnostics, but
is not counted as a primary boot pass.


## 2026-11-05 — Targeted qemu64 instruction trace for the triple-fault diagnosis

### Inspection and finding

- Re-inspected the PR #41 head `0f2e36b` CI state before editing: the
  userland workflow is green, while the full build-and-boot workflow still
  fails because the primary `qemu64` BIOS and direct-kernel boots fault before
  the rootfs hand-off.
- The preserved PR #40 diagnostics show `#UD` at `RIP=0x3cd63c7` followed by
  `#GP`, a double fault, and a triple fault on `qemu64`, while the `max` CPU
  model boots. The debug flags do not include `in_asm`, so the instruction
  bytes at the failing RIP were never captured, and the `max` retry cannot
  substitute because it follows a different CPU feature model.
- The CPU-suffixed log naming alone would make a second `qemu64` run overwrite
  the primary logs.

### Implemented on a new stacked branch

- `scripts/run-qemu-tests.sh` now supports an optional
  `AWEOS_QEMU_LOG_SUFFIX` that appends a sanitized tag to every serial and
  debug log name, so diagnostic retries with the same CPU model write to
  distinct logs (for example `qemu-bios-instrtrace.log`) and cannot overwrite
  the primary run's or any other retry's artifacts.
- The runner now supports an optional `AWEOS_QEMU_DFILTER` that passes QEMU
  `-dfilter` guest address ranges, so `in_asm` traces can target only the
  faulting region instead of logging every translated block.
- The boot workflow gained a new diagnostic step that, after a primary
  `qemu64` failure and before the `max` retry, re-runs all boot modes with
  `qemu64`, `in_asm` enabled, log tag `instrtrace`, and the address window
  `0x3c00000-0x3d00000` around the previously observed faulting RIP
  `0x3cd63c7`. It is skipped when the guest reached its recovery console,
  because that indicates a userspace/desktop failure rather than an early
  CPU fault.
- The primary `qemu64` boot check remains mandatory and unchanged; the trace
  retry and the `max` retry are diagnostics only and are never counted as a
  primary boot pass.
- The mock QEMU regression now records the `-dfilter` argument into the debug
  log and adds a full pass asserting that a tagged `instrtrace` run produces
  distinct per-mode logs containing the CPU model and the filter, while the
  earlier `max` logs remain intact.
- The shell edits were replayed locally for syntax and structure; full
  execution of the suite requires GitHub Actions because the development
  sandbox shell lacks `trap`, `timeout`, and `mktemp`.
- No changes to `/linux`, installer/updater behavior, disks, partitions, or
  user data.

### Files changed

- `scripts/run-qemu-tests.sh`
- `scripts/test-qemu-test-runner.sh`
- `.github/workflows/build-aweos-x86_64.yml`
- `docs/AI-DEVELOPMENT-LOG.md`

### Validation status

- The new regression is wired into `make test-shell` through the existing
  QEMU-runner test. Fresh userland and full image/boot runs on this branch
  are required before the change is considered validated; the PR #41 results
  do not validate these edits.
- The trace itself does not fix the qemu64 fault. Its purpose is to capture
  the exact faulting instruction bytes and exception sequence on the failing
  CPU model so the next run can map the RIP to the bootloader/kernel image
  and fix the compatibility fault itself.
- If the pushed `scripts/run-qemu-tests.sh` blob loses its executable mode
  through the API transport (a known past defect), the shell suite's mode
  assertion will fail the userland run; that must be fixed with a mode-only
  commit before CI results are trusted.

### Next priorities

1. Inspect the fresh userland run and, when the primary qemu64 boot fails,
   the qemu64 `instrtrace` diagnostics artifact.
2. Map the faulting RIP to the exact image using `System.map` / `vmlinux`
   disassembly and fix the underlying qemu64 compatibility fault without
   weakening the baseline CPU test.
3. Re-run BIOS/UEFI/direct-kernel boot validation on the fixed head.
4. Reconcile PR #29 (fail-closed ISO verification) into the stack and re-run
   image construction on the combined head.


## 2026-11-05 — QEMU runner file-mode regression repeat and mode-independent fix

### Evidence

- The first CI runs on commit `5f503b1` (userland run
  [#42046350969](https://github.com/ARARAT33/AWEOS/actions/runs/42046350969),
  PR-triggered duplicates, and both full image/boot workflows) failed within
  about a minute.
- The userland annotation names the exact cause: `make test-shell` failed at
  `scripts/test-qemu-test-runner.sh` on the executable-mode assertion, because
  the available API push transport again committed
  `scripts/run-qemu-tests.sh` as mode `100644`, exactly the documented
  transport defect from 2026-11-04/05. No other test failure is claimed or
  implied by these runs; they stopped before exercising any new trace logic.

### Implemented on the same branch

- `make test-qemu` and both QEMU diagnostic retry steps in the boot workflow
  now invoke the runner through `bash ./scripts/run-qemu-tests.sh`, so no CI
  path depends on the checked-out executable mode. This mirrors the
  `awepkg.sh` precedent from the 2026-11-04 mode regression.
- The runner regression now requires the bash interpreter line
  (`#!/usr/bin/env bash`) instead of the executable bit. The interpreter
  contract is what correctness actually depends on, because every CI path
  calls the runner through bash.
- A future run with direct git access may still restore mode `100755` on
  `scripts/run-qemu-tests.sh` (and `scripts/awepkg.sh`) for developer
  convenience; CI no longer requires it.
- No changes to `/linux`; no disk, partition, installer, updater, or
  user-data operations.

### Files changed

- `Makefile`
- `scripts/test-qemu-test-runner.sh`
- `.github/workflows/build-aweos-x86_64.yml`
- `docs/AI-DEVELOPMENT-LOG.md`

### Validation status

- Fresh userland and full image/boot runs on this corrected head are required;
  the failed runs on `5f503b1` did not exercise the new tagged-trace logic and
  prove nothing about it.

### Missing-firmware regression in the new trace test (2026-11-05)

- The corrected head `5b57906` passed the mode check and executed the full
  QEMU-runner suite, but userland runs
  [#42046994236](https://github.com/ARARAT33/AWEOS/actions/runs/42046994236)
  and [#42046981706](https://github.com/ARARAT33/AWEOS/actions/runs/42046981706)
  still failed inside the new `instrtrace` pass.
- Trace-attributed annotation shows the suite reached the new block and then
  exited during its runner invocation. Root cause: the new test invocation did
  not export `AWEOS_UEFI_FIRMWARE` like the other passes, so the runner looked
  for real OVMF firmware on the userland runner, found none, and correctly
  failed the UEFI boot test.
- Fix: the `instrtrace` pass now passes the mock firmware explicitly via
  `AWEOS_UEFI_FIRMWARE`, matching every other pass in the suite.


### Actual validation results on the final head (2026-11-05)

- Final head: `6d12b44c3524e2d7c2477286ba27d07bbcb30b4c` (branch
  `boot/qemu64-instruction-trace-20261105`, PR #42).
- Userland runs [#42047481992](https://github.com/ARARAT33/AWEOS/actions/runs/42047481992)
  and [#42047499037](https://github.com/ARARAT33/AWEOS/actions/runs/42047499037):
  **PASS** — the full shell/C suite including the new `instrtrace` regression,
  Rust workspace tests, release binaries, installer no-write test, and the
  Xvfb AYUI smoke test.
- Package-safety run [#42047499168](https://github.com/ARARAT33/AWEOS/actions/runs/42047499168):
  **PASS**.
- Full image/boot runs [#42047499118](https://github.com/ARARAT33/AWEOS/actions/runs/42047499118)
  and its duplicate: **FAILURE**, at the pre-existing primary `qemu64` boot
  blocker (the default qemu64 BIOS/direct-kernel boots still fault before the
  rootfs hand-off). The run reached the QEMU stage, ran the diagnostic retries,
  and uploaded the `AWEOS-QEMU-diagnostics` artifact (106 MB), which should
  now contain the tagged `qemu-bios/uefi/kernel-instrtrace` logs with the
  `-dfilter 0x3c00000-0x3d00000` instruction trace. This failure is the known
  blocker, not a regression from this change.
- The artifact contents were not yet inspected from this environment; that is
  the next run's first priority, together with mapping the captured faulting
  instruction to the bootloader/kernel image.

### Next priorities

1. Download and inspect the `AWEOS-QEMU-diagnostics` artifact from run
   #42047499118; read the qemu64 `instrtrace` logs around the `#UD` at
   `RIP=0x3cd63c7` and map the faulting instruction to the exact image.
2. Fix the underlying qemu64 compatibility fault without weakening the
   baseline CPU test, then re-run the full boot validation.
3. Reconcile PR #29 (fail-closed ISO verification) into the stack and re-run
   image construction on the combined head.
4. Merge the validated PR chain toward master only after the boot blocker is
   diagnosed/fixed or the maintainer makes an explicit merge decision.





## 2026-11-06 — Correct QEMU instruction-trace filter syntax

### Inspection and root cause

- Downloaded and inspected the actual AWEOS-QEMU-diagnostics artifacts from
  full-build runs #42047499118 and #42051106098 on PR #42.
- The primary qemu64 BIOS and direct-kernel debug logs still show #UD at
  RIP=0x3cd63c7, followed by #GP with error code 0x0032, then a double fault
  and triple fault.
- The new tagged instruction-trace logs did not contain disassembly. Each of
  qemu-bios-instrtrace.log, qemu-uefi-instrtrace.log, and
  qemu-kernel-instrtrace.log contained only:
  qemu-system-x86_64: -dfilter 0x3c00000-0x3d00000: Invalid range.
- Root cause: QEMU's documented -dfilter grammar accepts start+size,
  start-size, or start..end; it does not accept a hyphen-separated
  start/end pair. The previous mock QEMU test recorded the argument without
  validating the syntax, so it produced a false-positive regression result
  even though real QEMU rejected the trace invocation.
- Reference: https://www.qemu.org/docs/master/system/qemu-manpage.html

### Corrective change on PR #42 branch

- Changed the targeted address window to 0x3c00000..0x3d00000
  (documented start..end form).
- Hardened the mock QEMU in scripts/test-qemu-test-runner.sh to reject
  malformed range strings for the range form used by this diagnostic.
- Added a negative regression proving the old hyphen-separated form fails,
  followed by the positive tagged-trace regression using the corrected form.
- The trace retry remains diagnostic only; it cannot turn a failed primary
  qemu64 boot into a pass.
- No changes to /linux, installer/updater behavior, disks, partitions,
  or user data.

### Files changed

- .github/workflows/build-aweos-x86_64.yml
- scripts/test-qemu-test-runner.sh
- docs/AI-DEVELOPMENT-LOG.md

### Validation status

- The prior CI runs on PR #42 passed userland, package-safety, image assembly,
  and the QEMU runner mock suite, but the full boot job failed at the primary
  qemu64 BIOS/direct-kernel tests.
- Artifact inspection confirmed the previous trace retry was invalid and
  therefore did not capture the faulting instruction. The corrected mock
  regression has been added but has not yet run in GitHub Actions.
- A fresh userland and full image/boot workflow is required. Only a non-empty
  in_asm trace from real QEMU will count as evidence that the diagnostic
  filter is fixed; the qemu64 boot issue itself remains unresolved.

### Next priorities

1. Run the updated PR #42 userland and full image/boot workflows.
2. Inspect the new tagged instruction-trace logs and verify they contain
   assembly around 0x3cd63c7.
3. Map the captured instruction address against the exact boot image and
   vmlinux/decompressor symbols before changing kernel configuration.
4. Fix the qemu64 boot fault without weakening the baseline CPU test.
5. Reconcile the fail-closed ISO-verification work (PR #29) into the reviewed
   stack and re-run image construction and boot tests.


### Validation update (2026-11-06)

- Updated-head userland workflow #42164070638: **PASS**. The job completed
  successfully, including the shell/C regressions, Cargo workspace tests,
  release userland builds, installer no-write integration, and AYUI Xvfb
  smoke test.
- Updated-head package-safety workflow #42164070651: **PASS**.
- Updated-head full image/boot workflow #42164070703: the shell/C/rootfs/
  session/QEMU-runner regression step **PASS**, the pre-build /linux
  read-only verification **PASS**, and the Rust workspace test **PASS**.
- The full image workflow was still in the Build AWEOS images step at the
  time of this log update. Therefore no result is claimed yet for the new
  real-QEMU instruction trace, BIOS/UEFI/direct-kernel boot, post-build
  /linux check, or release artifact verification.
- The local shell regex sanity check also passed: the Bash expression
  accepts 0x3c00000..0x3d00000 and rejects the previous hyphen-separated
  form. This is supplemental; the GitHub Actions regression is the
  authoritative repository test.
- Run links:
  - https://github.com/ARARAT33/AWEOS/actions/runs/42164070638
  - https://github.com/ARARAT33/AWEOS/actions/runs/42164070651
  - https://github.com/ARARAT33/AWEOS/actions/runs/42164070703

## 2026-11-06 — Publish the qemu64 faulting instruction from CI instead of a 108 MB artifact download

### Inspection and evidence

- Followed the protocol: re-inspected the repository tree outside the
  protected `/linux` source, the open PR stack (#27–#42), the latest runs,
  and this log before editing.
- PR #42 head `caf5bc6` has green userland and package-safety runs; the full
  image/boot workflow `#42164070703` completed with **failure** at the known
  primary `qemu64` boot blocker (exit 1/exit 2 annotations), after ~20 minutes.
  It produced the corrected `-dfilter 0x3c00000..0x3d00000` tagged instruction
  trace in the 108 MB `AWEOS-QEMU-diagnostics` artifact.
- The full diagnostics artifact cannot be downloaded from this environment
  (unauthenticated GitHub API rate limit, no HTTP client in the sandbox), so
  the captured faulting instruction was still unread. The run page
  annotations are readable without authentication, which is the already
  proven route for publishing CI evidence.

### Implemented on a new stacked branch (head `caf5bc6`)

- Added `scripts/extract-qemu-instrtrace.sh`: summarizes the last CPU fault
  event (`v=06`/`v=08`/`v=0d`), the recent `check_exception` lines, and the
  `in_asm` disassembly around the faulting instruction pointer from a tagged
  QEMU debug log. Output is bounded (80 lines per log), and missing, empty,
  and fault-free logs are reported explicitly instead of failing silently.
- Added `scripts/test-qemu-instrtrace-extract.sh`: a fabricated-log
  regression covering fault-event extraction, faulting-address disassembly
  lookup, output bounds (≤320 lines for four logs), the fault-free tail
  fallback, and the empty/missing/usage-error paths.
- Wired the new test into `make test-shell` via `scripts/run-test-shell.sh`
  (14 test scripts now; list order otherwise unchanged).
- Extended `build-aweos-x86_64.yml`: after the tagged qemu64 instruction-trace
  retry, a new step runs the extractor over every
  `build/qemu-*-instrtrace-debug.log`, prints the summary in the job log and
  `GITHUB_STEP_SUMMARY`, and emits a `::error::` annotation with the faulting
  event line and instruction, so the exact faulting instruction becomes
  readable from the run page without any artifact download. A small dedicated
  `AWEOS-qemu64-instrtrace-summary` artifact (30-day retention) holds the same
  text. The summary step is diagnostics-only and is skipped when the guest
  reached its recovery console; it cannot turn a failed primary qemu64 boot
  into a pass.
- No changes to `/linux`; no disk, partition, installer, updater, or user-data
  operations.

### Files changed

- `scripts/extract-qemu-instrtrace.sh` (new)
- `scripts/test-qemu-instrtrace-extract.sh` (new)
- `scripts/run-test-shell.sh`
- `.github/workflows/build-aweos-x86_64.yml`
- `docs/AI-DEVELOPMENT-LOG.md`

### Validation status

- All pushed files were read back from the branch after the push to verify the
  API transport did not corrupt shell syntax or YAML expressions (a known
  past defect with Makefile/`$` escapes and file modes).
- Fresh userland and full image/boot workflows on this branch are required
  before this change is considered validated; the PR #42 results do not
  validate it.
- The qemu64 #UD at `RIP=0x3cd63c7` remains undiagnosed until the new summary
  annotation or artifact from a failing full-image run is inspected.

### Next priorities

1. Run this branch's userland workflow (new extraction regression) and the
   full image/boot workflow.
2. Read the faulting instruction from the new `::error::` annotation or the
   small `AWEOS-qemu64-instrtrace-summary` artifact, and map it to the exact
   image (Limine decompressor stage, compressed kernel head, or kernel
   proper) using `System.map`/`vmlinux` from the diagnostics artifact.
3. Fix the underlying qemu64 compatibility fault without weakening the
   baseline CPU test, then re-run BIOS/UEFI/direct-kernel validation.
4. Reconcile the fail-closed ISO-verification work (PR #29) into the reviewed
   stack and re-run image construction on the combined head.

### Local replay defect found and fixed (2026-11-06, same run)

- Before trusting CI, the first extractor version was replayed locally against
  the two real QEMU `-d int` address forms. The faulting-IP parsing only
  matched `0x`-prefixed values, but the actual QEMU x86_64 int log uses
  selector-form addresses (`IP=0008:0000000003cd63c7 pc=0000000003cd63c7`)
  without any `0x`. The summary would have reported "Could not parse a
  faulting instruction pointer" and the pushed regression would have been a
  false pass, because its fixture used the same selector form.
- The extractor now accepts both forms, prefers the original `v=06` event as
  the fault to explain (falling back to the last recorded fault event), and
  reports the disassembly for both addresses when they differ.
- The regression gained a second fixture for the `RIP=0x...` form; the
  output-bound assertion accounts for the fifth fixture. All fixture paths
  were replayed locally (selector form, 0x form, fault-free fallback, empty,
  missing, no-args usage error, and bounded total output) before the fix was
  pushed as commit `047166f`.
- The CI runs started on the first head `429b54f` will fail at this
  regression by design; the corrected head `047166f` re-runs them.


## 2026-11-07 — Trace the qemu64 #UD to BMI2 and enforce the x86_64 boot baseline

### Inspection and evidence

- Re-inspected PR #43, its latest full image/boot run #42237519208, the actual
  `AWEOS-QEMU-diagnostics` artifact, the compressed-kernel ELF, its
  `System.map`/symbols, the Makefile, x86 kernel build rules, and the existing
  trace extractor before changing code.
- The BIOS `qemu64` trace records `#UD` at
  `RIP=0x3cd63c7`. The preceding QEMU block is printed as the short address
  `0x03cd63bc:` followed by an `OBJD-T:` raw-byte record, not a 16-digit
  disassembly line. The bytes at the faulting IP are
  `c4 e2 fb f7 ca`; disassembly of the exact compressed `vmlinux` decodes
  this as `shrx rcx,rdx,rax` (BMI2) inside
  `kernel_ident_mapping_init`.
- The same code is relocated by 8 MiB on the UEFI path
  (`RIP=0x44d63c7`). The previous trace filter
  `0x3c00000..0x3d00000` covered BIOS but excluded this UEFI address, so
  the diagnostic retry could not capture both paths.
- Scanning the failing compressed-kernel ELF found multiple BMI1/BMI2
  instructions (89 matches in this artifact). The x86 compressed-kernel
  Makefile resets `KBUILD_CFLAGS`; it does not retain the normal x86
  `-march=x86-64` baseline flag. This lets the build compiler's default ISA
  leak into code that runs before CPU-feature alternatives are available.
- The earlier extractor searched only for a zero-padded exact 16-digit
  instruction address. It therefore missed QEMU's short-address
  `OBJD-T` block and produced an unhelpful 529-byte summary artifact.

### Implemented on a new stacked branch

- Updated the kernel build invocation to pass explicit
  `-march=x86-64 -mtune=generic -mno-bmi -mno-bmi2` compiler flags through
  Kbuild's `CC` command for the entire x86_64 kernel build. This keeps the
  compressed boot code on the x86_64 baseline without modifying the protected
  `/linux` source tree.
- Added `scripts/check-kernel-baseline-isa.sh`. After the kernel build it
  disassembles the actual compressed `vmlinux` and fails the image build if
  BMI1/BMI2 instructions appear. This is a post-build binary check, not a
  workflow-YAML-only assertion.
- Added `scripts/test-kernel-baseline-isa.sh`, which assembles a safe fixture
  and an explicit SHRX/BMI2 fixture, verifies that baseline code is accepted,
  and verifies that BMI2 code is rejected. Wired it into `make test-shell`.
- Updated the QEMU trace extractor to accept short and zero-padded addresses,
  read the `OBJD-T` raw-byte records, locate the instruction within a block,
  and decode the bytes with `objdump` when available.
- Expanded the targeted QEMU trace filter to
  `0x3c00000..0x45d0000` so the same diagnostic captures both BIOS and UEFI
  relocated fault addresses. Added BIOS and UEFI address fixtures to the
  extractor regression.

### Files changed

- `Makefile`
- `.github/workflows/build-aweos-x86_64.yml`
- `scripts/run-test-shell.sh`
- `scripts/test-qemu-test-runner.sh`
- `scripts/extract-qemu-instrtrace.sh`
- `scripts/test-qemu-instrtrace-extract.sh`
- `scripts/check-kernel-baseline-isa.sh` (new)
- `scripts/test-kernel-baseline-isa.sh` (new)
- `docs/AI-DEVELOPMENT-LOG.md`

### Validation status

- Local QEMU trace-extractor regression: **PASS**, including the BIOS short
  address, UEFI +8 MiB relocation, selector-form and `RIP=0x` fault records,
  decoded-instruction fallback, and bounded output.
- Local compressed-kernel ISA-checker regression: **PASS**. A safe object is
  accepted and a deliberately encoded SHRX object is rejected.
- Applied the new ISA checker to the actual failing CI compressed `vmlinux`:
  it **correctly FAILS** and reports the existing BMI1/BMI2 instructions,
  including SHRX. This is the expected pre-fix result and confirms the
  regression guard detects the real defect.
- The extractor was replayed against the actual BIOS trace and successfully
  decoded the faulting instruction as SHRX. The previous UEFI artifact did
  not contain the relocated trace block because its old filter was too narrow;
  the UEFI parser path is covered by a synthetic regression fixture.
- Fresh GitHub Actions userland, kernel build, post-build ISA scan, BIOS/UEFI
  QEMU boot, and /linux integrity results are **pending** on this new branch.
  No claim is made that the boot fault is fixed until those checks pass.

### Additional safety finding for the next cycle

- The C installer initialization still sets `selected_disk_idx = 0` when a
  disk is discovered, despite the documented no-implicit-target-selection
  invariant. The transaction backend currently fails closed before writes,
  but the default-selection mismatch should be corrected and regression-tested
  in a separate scoped safety change. No installer code or disk behavior was
  changed in this boot-diagnostics change.

### Next priorities

1. Run the new branch's full CI and inspect the actual compressed-kernel ISA
   scan result; confirm no BMI1/BMI2 instruction remains in the boot-critical
   compressed image.
2. Re-run qemu64 BIOS, UEFI, and direct-kernel paths. Require the primary
   qemu64 BIOS/UEFI tests to pass; do not substitute a `max` CPU retry.
3. Verify /linux before and after the full build, and inspect the actual
   ISO/disk-image artifacts and checksums.
4. Fix the C installer default target selection in a separate PR, keeping
   the transaction engine fail-closed and preserving user data.
5. Continue with signed package metadata/key management and AYUI native
   DRM/KMS only after boot reliability is re-established.


### CI follow-up — 2026-11-07

- First validation on commit `13ff8c3` found a stale assertion in
  `scripts/test-qemu-test-runner.sh`: the test expected the old narrow
  `0x3c00000..0x3d00000` filter even though the test invocation had already
  been widened to `0x3c00000..0x45d0000`.
- This was a regression-test fixture mismatch, not a QEMU or kernel failure.
  Updated the expected mock command line to the new range. The package-safety
  workflow passed; userland and full-build shell suites stopped at this
  assertion before the new kernel build/ISA scan could run.
- Re-run the full shell suite and build/boot workflow after this correction.


### Build-command review — 2026-11-07

- Reviewing the first CI traces exposed a Makefile escaping regression in the
  new kernel command: the recipe needs `$$(nproc)` so GNU Make passes
  `$(nproc)` to the shell. Corrected the line to preserve the existing
  parallel-build behavior while retaining the explicit compiler flags.
- The earlier shell-suite failure from the stale QEMU mock assertion has also
  been corrected in commit `9da2867`; the next workflow run is the first
  valid full validation of these changes.


### Stored Makefile verification — 2026-11-07

- A follow-up read-back found that the previous replacement-string operation
  had collapsed the required doubled dollar sign. Rewrote the recipe using a
  literal-safe replacement and verified the stored line now contains
  `$$(nproc)`, so GNU Make passes the job-count command substitution to the
  shell rather than expanding an undefined Make variable.

### QEMU trace follow-up — userspace #UD identified, 2026-11-07

- Inspected the real 506-byte summary artifact from QEMU run #42341230731
  (artifact #13562646643), rather than relying on the workflow's green
  diagnostic-retry step.
- The primary BIOS/UEFI/direct-kernel boot check failed. The tagged qemu64
  retry recorded an invalid-opcode exception (#UD, vector 6) at the same
  address in all three paths: PC/RIP 0x000000000056df50, CPL=3. This is a
  userspace fault, not the earlier compressed-kernel RIP at 0x3cd63c7.
- The compressed-kernel x86-64 baseline scan and image build passed, and
  /linux integrity passed after the build. That does not establish that the
  userspace binaries are baseline-compatible or that boot succeeds.
- The first tagged trace did not include instruction bytes because its filter
  covered 0x3c00000..0x45d0000 and omitted the observed userspace address
  0x56df50. The summary explicitly reported that no instruction-byte block
  covered the faulting PC.
- Updated the diagnostic range to include both 0x500000..0x600000 (the observed
  userspace fault region) and 0x3c00000..0x45d0000 (the previous compressed
  kernel region). QEMU's documented comma-separated -dfilter range syntax is
  used. The mock runner now validates each range in the list, and the trace
  extractor has a CPL3/0x56df50 regression fixture.
- The exact faulting instruction is still unknown. Do not attribute this #UD
  to BMI2 or claim the qemu64 boot issue fixed until the widened trace yields
  the bytes and the responsible userspace binary is identified.

Next:
1. Run the updated QEMU trace and inspect the decoded instruction at 0x56df50.
2. Map the PC to the responsible ELF in the initramfs/rootfs and inspect its
   build flags and linked libraries.
3. Fix the actual unsupported instruction or intentional trap, then rerun
   BIOS, UEFI, and direct-kernel QEMU tests on qemu64.
4. Preserve the current compressed-kernel ISA regression and /linux read-only
   checks.

### QEMU filter regression follow-up — 2026-11-07

- The first userland run after widening the trace filter (#42343041467) failed
  in scripts/test-qemu-test-runner.sh, before any real QEMU boot test. Review
  of the failing xtrace showed that the test-file edit had replaced the mock
  QEMU's dfilter printf with a grep assertion inside the mock process.
- Restored the mock's debug-log write and moved the fixed-string assertion to
  the parent test loop. The failure was in the test fixture, not in QEMU's
  comma-separated filter handling or the guest.
- A fresh userland run on the corrected head is required; no pass is claimed
  for the failed run.


### QEMU userland invalid-opcode root cause — 2026-11-07

#### Evidence from the real boot artifact

- Inspected diagnostics artifact `AWEOS-QEMU-diagnostics-run-42341230731.zip` from the actual BIOS/UEFI QEMU run, not only its summary.
- The BIOS kernel log reports: `traps: init[1] trap invalid opcode ip:56df50 ... in busybox`, followed by `Kernel panic - not syncing: Attempted to kill init!`.
- The faulting bytes are `c5 f9 6f 05 98 ff 05 00`. Disassembly of the exact BusyBox binary extracted from the initramfs identifies the instruction at `0x56df50` as `vmovdqa xmm0, XMMWORD PTR [rip+0x5ff98]` (VEX/AVX).
- The extracted ELF's package metadata identifies Ubuntu BusyBox `1:1.37.0-7ubuntu1` with `architectureVariant=amd64v3`. The host package was optimized for a newer CPU than QEMU's `qemu64` model. The kernel was able to start `/init`; PID 1 then faulted in BusyBox.
- This is a distinct userspace fault from the earlier compressed-kernel BMI2 finding. The prior kernel ISA guard remains necessary; this evidence does not establish that all BIOS/UEFI boot paths now pass.

#### Changes on branch `boot/busybox-x86-64-baseline-20261107`

- Added `scripts/build-busybox-baseline.sh`: downloads pinned BusyBox 1.38.0 source, verifies SHA-256 `34f9ea6ff8636f2c9241153b9114eefa9e65674a45318ae1ef95bb5f31c53bb2`, and builds a static binary with musl and explicit x86-64 baseline flags. It publishes to the build directory only after the binary, applets, static-linking property, and ISA scan pass.
- Added `scripts/check-qemu64-baseline-isa.sh` and `scripts/test-qemu64-baseline-isa.sh`. The checker rejects VEX/EVEX instructions (including AVX/AVX2/AVX-512) and a list of common post-baseline extensions; the regression uses explicit AVX and BMI2 byte fixtures.
- Made the baseline BusyBox a Makefile dependency and use the same binary for both rootfs and initramfs. The build no longer copies the host runner's potentially amd64v3 BusyBox.
- Rootfs validation now scans every packaged ELF under `/usr/bin` and the BusyBox binary. AYUI's framebuffer fallback and its test fixture are compiled with explicit x86-64 baseline flags.
- Added `musl-tools` to the full-build workflow and removed the host `busybox-static` dependency.

#### Validation performed in this run

- Local ISA regression fixture: PASS (baseline object accepted; explicit AVX and BMI2 objects rejected).
- The actual BusyBox extracted from the failed QEMU artifact is rejected by the new checker; its AVX instructions are reported. This independently confirms the diagnosis.
- Full repository `make test-shell`, BusyBox source build, ISO build, and BIOS/UEFI QEMU reruns have not yet been run on this branch. Fresh GitHub Actions results are required before treating this fix as validated.

#### Remaining blockers / next steps

1. Run userland regression CI and the complete x86_64 image/boot workflow on this branch.
2. Inspect the build log to confirm the pinned BusyBox builds statically with the required applets and passes the ISA scan.
3. Confirm the rebuilt image reaches the verified rootfs hand-off in BIOS, UEFI, and direct-kernel qemu64 modes.
4. If another #UD occurs, map its exact instruction to the responsible ELF; do not widen the CPU model or label the boot as fixed without evidence.
5. Keep PRs stacked and unmerged until the base-chain review and all required checks pass. Preserve `/linux` read-only verification and the no-implicit-destructive-install invariant.


### CI follow-up for baseline BusyBox branch — 2026-11-07

- Package Security workflow run `42345079130` (#51): PASS.
- Userland workflow run `42345079144` (#425): shell/C transaction safety tests, repository-boundary verification, Cargo metadata validation, and Rust workspace tests completed successfully. The Rust userland binary build was still running at the time of this update.
- Full x86_64 build workflow run `42345079128` (#482): Limine host utility build, shell/C/rootfs/session/QEMU-runner regressions, and the pre-build `/linux` read-only verification completed successfully. The Rust workspace test step was still running; image build and BIOS/UEFI/direct-kernel boot tests had not started.
- Therefore the new ISA regression and updated rootfs fixture are confirmed passing in GitHub Actions, but the pinned BusyBox source build and the rebuilt-image boot result remain pending. No boot-fix claim is made.

### CI follow-up: image build failed on the baseline BusyBox branch — 2026-11-07

- On branch `boot/busybox-x86-64-baseline-20261107` (PR #46):
  - "Validate AWEOS Userland" run 42345461611: **PASS**.
  - "Validate AWEOS Package Security" run 42345461617: **PASS**.
  - "AWEOS x86_64 Build, Image and Boot Tests" run 42345461570:
    **FAILURE**. The `build-and-boot-test` job passed checkout, dependency
    install, Limine host build, `make test-shell`, `/linux` read-only
    verification, and `cargo test --workspace`, then failed at the
    "Build AWEOS images" (`make image`) step with exit code 2 after
    16m29s.
- The only failure annotation is the generic "Process completed with exit
  code 2". The raw job log requires an authenticated session this environment
  does not have, and no `AWEOS-QEMU-diagnostics` artifact was uploaded
  because the failure happened before the QEMU steps.
- Therefore the exact failing target inside `make image` (busybox, kernel,
  rootfs, initramfs, finalize-rootfs, iso, or disk-image) is currently
  unknown. No root cause is claimed.

#### Implemented on branch `boot/busybox-build-failure-diagnostics-20261107`

- The "Build AWEOS images" step now tees the full `make image` output to
  `image-build.log` through `set -o pipefail`, preserving the real exit code.
- A new failure-conditioned step extracts the first make/script errors and
  the last 100 log lines into `build/image-build-failure-summary.txt`,
  appends them to the GitHub step summary, and emits a `::error::`
  annotation with the first error line so the failing target is visible
  from the run page without an artifact download.
- A new failure-conditioned step uploads `image-build.log` as the
  `AWEOS-image-build-log` artifact (30-day retention).
- No build recipe, boot logic, `/linux` handling, or packaged content
  changed. This mirrors the established qemu64-instrtrace-summary pattern.

#### Files changed

- `.github/workflows/build-aweos-x86_64.yml`
- `docs/AI-DEVELOPMENT-LOG.md`

#### Validation

- Workflow steps cannot be exercised by `make test-shell`; correctness
  depends on this branch's own Actions run. Success criteria: a failing
  `make image` must produce an annotation and step summary naming the
  actual failing target and error line; a passing build must behave
  unchanged.

#### Next priorities

1. Read the published `image-build.log` excerpt from this branch's run and
   identify the real `make image` failure.
2. Prime suspects once the log is available: the pinned BusyBox 1.38.0
   musl-gcc static build, or the new all-/usr/bin ELF qemu64 baseline ISA
   scan in `scripts/validate-rootfs-layout.sh` rejecting a packaged
   userland binary. Neither is confirmed.
3. Until the BusyBox baseline build passes and qemu64 BIOS/UEFI boots are
   proven, PRs #44/#45/#46 remain unmerged and no boot fix is claimed.

### BusyBox build failure diagnosis and Linux UAPI header prerequisite — 2026-11-08

#### Actual CI evidence

- Inspected the complete failed job logs, not only the workflow definition:
  - PR #46 full image workflow run `42345461570` failed during `make image`.
  - PR #47 diagnostics workflow run `42384042946` failed at the same target and successfully published the new `AWEOS-image-build-log` artifact and step-summary excerpt.
- The first failing compile unit is BusyBox `console-tools/kbd_mode.o`:
  `console-tools/kbd_mode.c:32:10: fatal error: linux/kd.h: No such file or directory`.
  The failure propagates through `console-tools` and the `busybox` Make target.
- The workflow installed `musl-tools` but did not explicitly install the Linux UAPI development headers. This is a build-dependency failure, not a qemu64 ISA-check failure or a kernel/ISO/boot result.
- The `/linux` read-only verification still passed in run `42384042946`. Because `make image` stopped before producing a new ISO, BIOS, UEFI, and direct-kernel QEMU tests were skipped.

#### Implemented on branch `fix/busybox-linux-uapi-headers-20261108`

- Added `linux-libc-dev` to the x86_64 image workflow's explicit apt dependencies.
- Added an early compile-only preflight for `<linux/kd.h>` using the same musl compiler and x86-64 baseline flags as the BusyBox build. Missing headers now produce a clear actionable error before downloading and compiling the BusyBox source archive.
- Updated README development status and build prerequisites to describe the actual blocker and the new follow-up branch.
- No files under `/linux` were modified. No installer, disk, partition, bootloader, updater, or user-data write behavior changed.

#### Validation status

- The previous PR #47 workflow run confirms the diagnostics step itself works and exposes the exact failing make target.
- Fresh `make test-shell`, Rust workspace tests, the Linux UAPI preflight, BusyBox source build, ISO build, and BIOS/UEFI/direct-kernel QEMU tests on this new branch are pending its GitHub Actions run.
- The prior PR #46 userland and package-security workflows passed, but they do not validate this new build-dependency fix.

#### Next priorities

1. Inspect the new branch's userland, package-security, and full image workflow results.
2. Confirm the musl preflight finds `linux/kd.h` and the pinned BusyBox build completes with all required applets, static linking, and qemu64 ISA checks.
3. Require the primary `qemu64` BIOS, UEFI, and direct-kernel tests to pass before claiming the boot path is repaired.
4. Keep the PR stack unmerged until its base chain is reconciled and fresh required checks pass.
5. Preserve `/linux` read-only verification and the no-implicit-destructive-install invariant.
### Follow-up: musl-gcc excludes host UAPI include paths — 2026-11-08

#### Actual CI evidence

- The first dependency-fix run `42446411572` installed `linux-libc-dev` successfully (`linux-libc-dev:amd64 7.0.0-43.43`), but the new preflight still failed before the BusyBox source build.
- The failure was now explicit: `ERROR: Linux UAPI header <linux/kd.h> is unavailable to musl-gcc`.
- This exposed the second half of the dependency issue: the musl-gcc wrapper uses `-nostdinc`, so it does not search the host's normal `/usr/include` and architecture-specific include directories unless they are added explicitly. Installing the package alone is insufficient.
- The same run passed shell/C/rootfs/session/QEMU-runner regressions, `/linux` read-only verification, and `cargo test --workspace`; it failed only at the image build preflight. BIOS/UEFI/direct-kernel tests were not reached.

#### Corrective change on the same PR branch

- Add `-idirafter /usr/include` and `-idirafter /usr/include/x86_64-linux-gnu` to both the compile-only preflight and the BusyBox `CC` command.
- Use `-idirafter` rather than `-I` so musl's own libc headers retain precedence and distro UAPI headers are used only as a fallback.
- The preflight now exercises the same include search configuration as the actual BusyBox build.

#### Validation status

- The earlier preflight implementation correctly detected the missing include path and prevented a long, opaque compile failure.
- No local compile result is claimed: this container's `cc`/GCC executable resolves to a stub that exits with status 1, and `musl-gcc` is not installed. The actual musl-gcc GitHub Actions run is authoritative.
- Fresh CI on the updated head is required to prove that the musl-gcc include path resolves `linux/kd.h`, that BusyBox builds statically with the required applets, and that the resulting ISO passes the qemu64 BIOS/UEFI/direct-kernel boot matrix.

#### Next priorities

1. Inspect the updated PR workflow's actual BusyBox compile and image-build logs.
2. If image creation succeeds, inspect BIOS, UEFI, and direct-kernel QEMU results and verify the root hand-off markers.
3. Keep `/linux` read-only verification and installer fail-closed guarantees mandatory.
### Local toolchain validation limitation — 2026-11-08

- A follow-up inspection showed that the container's `/usr/bin/x86_64-linux-gnu-gcc-14` is a 17-byte stub that exits with status 1; `musl-gcc` is also absent. Therefore the earlier local header-check output is not accepted as compiler evidence and is explicitly superseded.
- The updated script now passes the UAPI include directories with `-idirafter` to both the preflight and actual BusyBox compiler command. Only a fresh GitHub Actions run using the real Ubuntu musl-gcc toolchain can validate this change.
- Do not count the local shell harness as a passing compile test.

### BusyBox `tc` applet incompatibility with modern Linux UAPI — 2026-11-08

#### Actual CI evidence

- Inspected the complete build-and-boot job log for workflow run `42447168781` (job `128628431999`) on PR #48's merge commit `10f6d484d844883b118cc6578c141980bba75eae`.
- The musl-gcc preflight for `<linux/kd.h>` passed, and BusyBox compilation progressed beyond the earlier `kbd_mode` failure. The first failing target is now `networking/tc.o`.
- The compiler reports missing legacy CBQ UAPI declarations, including `TCA_CBQ_MAX`, `TCA_CBQ_RATE`, `TCA_CBQ_LSSOPT`, `TCA_CBQ_WRROPT`, `TCA_CBQ_FOPT`, `TCA_CBQ_OVL_STRATEGY`, and incomplete `struct tc_cbq_*` types.
- Inspected the pinned kernel source's `linux/include/uapi/linux/pkt_sched.h` at the PR head. It contains no CBQ declarations. This is an upstream UAPI compatibility issue, not another missing include directory.
- Upstream Buildroot removed BusyBox `CONFIG_TC` from its default configuration because the applet fails to build with Linux kernel headers >= 6.8 (Buildroot commit [44c221c856a473179daeb9e49bcb89af2b1b1405](https://git.buildroot.net/buildroot/commit/?id=44c221c856a473179daeb9e49bcb89af2b1b1405)).
- In run `42447168781`, shell/C/rootfs/session/QEMU-runner regressions passed, `cargo test --workspace` passed, and `/linux` read-only verification passed. The image build failed at BusyBox `networking/tc.o`; ISO creation and BIOS/UEFI/direct-kernel QEMU tests were skipped. Failure diagnostics were uploaded.

#### Implemented on PR #48 branch `fix/busybox-linux-uapi-headers-20261108`

- Added `scripts/configure-busybox-baseline.sh` to make the baseline configuration explicit and repeatable:
  - keep `CONFIG_STATIC=y`;
  - disable unused `CONFIG_TC` and `CONFIG_FEATURE_TC_INGRESS`;
  - run BusyBox `oldconfig` to regenerate derived configuration headers;
  - verify that the requested configuration survived Kconfig processing.
- Updated `scripts/build-busybox-baseline.sh` to use the configuration helper after `defconfig`. The required AWEOS applet list remains unchanged; `tc` was never a required bootstrap applet.
- Added `scripts/test-busybox-baseline-config.sh`, which exercises the config transformation against a fixture, checks that unrelated options are preserved, and verifies idempotence.
- Added the new test to `scripts/run-test-shell.sh`.
- Updated README's development status with the current observed blocker and scoped correction.

#### Validation status

- The previous CI run proves that the Linux UAPI header preflight now succeeds, but it does not validate the new `CONFIG_TC` change.
- The fixture test and shell syntax checks must pass in a fresh CI run. The pinned BusyBox static build, required-applet check, qemu64 ISA scan, image assembly, and BIOS/UEFI/direct-kernel boot matrix remain pending.
- No local BusyBox compiler result is claimed because this environment does not provide the real musl-gcc toolchain.
- `/linux` remains read-only; no kernel source files were modified. Installer, updater, partitioning, disk-write, bootloader deployment, and user-data preservation behavior were not changed.

#### Next priorities

1. Inspect the new PR #48 workflow run and verify the BusyBox config helper test passes.
2. Confirm BusyBox 1.38.0 compiles statically with the full required applet set and passes the qemu64 ISA scan.
3. If the image builds, inspect the ISO and actual BIOS, UEFI, and direct-kernel QEMU results, including root hand-off and AYUI/recovery markers.
4. Keep the stacked PR chain unmerged until its bases are reconciled and fresh required checks pass.
5. Continue enforcing `/linux` read-only verification and fail-closed, non-destructive installer/updater behavior.

### Fresh CI validation after the BusyBox `tc` configuration change — 2026-11-08

- `Validate AWEOS Userland` run `42448407387` completed successfully on commit `05982fa93c1c324f752be3e7b9b66faaadb61442`. All 13 job steps passed, including:
  - the shell/C regression suite (which now includes `test-busybox-baseline-config.sh`);
  - `/linux` read-only verification;
  - Cargo metadata and `cargo test --workspace`;
  - release builds and expected-binary checks;
  - the Rust installer no-unattended-write test;
  - AYUI Winit compositor smoke test under Xvfb.
- The final PR head `ac08eab68471bbdb6e6635a294995af389ce5305` adds only README/development-log documentation after that code-tested commit; the build/test scripts are unchanged.
- The latest `AWEOS x86_64 Build, Image and Boot Tests` run `42448461287` on the final head has so far passed the shell/C/rootfs/session/QEMU-runner regression step and `/linux` read-only verification; Cargo workspace tests also passed. The image build step has not yet completed, so no BusyBox, ISO, BIOS, UEFI, or direct-kernel success is claimed.
- Final-head userland run `42448461252` completed successfully; all 13 steps passed, including the full shell/C suite, `/linux` integrity, Cargo tests and release build, installer no-write test, and AYUI Xvfb smoke test.
- Code-identical build run `42448461287` on `ac08eab` has passed shell/C regressions, `/linux` integrity, and Cargo workspace tests; its image build is still in progress.
- Final-head build run `42448670031` on `ac3fdb7` has passed dependency installation, Limine host utility build, shell/C regressions, and `/linux` integrity; Cargo and image build steps remain pending.
- Keep PR #48 in draft and do not merge until a final-head image build and the required boot matrix complete successfully.

## 2026-11-08 — BusyBox SHA hardware acceleration breaks the qemu64 baseline ISA scan

### Actual CI evidence

- The latest full image/boot runs on the PR #48 head `7609a34a4c9e33a9b03ed6f0a3bf8b2c4ae82cbc` (runs #507, #509, #510, e.g. run 42448670031) all failed at the same point: the pinned BusyBox 1.38.0 static musl build completed, and the qemu64 baseline ISA scan then rejected the produced binary with "contains instructions outside the AWEOS qemu64/x86-64 baseline". The raw report lines are inside the uploaded `AWEOS-image-build-log` artifacts; the single-line CI annotation only showed the first error line, so the exact mnemonics were not published to the run page.
- Inspection of the BusyBox source explains the failure without guessing: BusyBox's `libbb/Config.src` defines `CONFIG_SHA1_HWACCEL` and `CONFIG_SHA256_HWACCEL`, both default y. Their x86-64 implementations are hand-written assembly (`libbb/hash_sha1_hwaccel_x86-64.S`, `libbb/hash_sha256_hwaccel_x86-64.S`) that BusyBox's `libbb/Kbuild.src` adds to `lib-y` unconditionally on x86-64. Those sources contain SHA-NI instructions (`sha1rnds4`, `sha256rnds2`, `sha256msg1/2`) and SSSE3/SSE4.1 instructions (`pshufb`, `palignr`, `pinsrd`), several of which are in AWEOS's rejection list. Compiler flags such as `-march=x86-64` cannot restrict hand-written assembly, so the default-defconfig build links post-baseline instructions into the bootstrap binary even with the baseline `CC` flags.
- This matches upstream practice: Buildroot, OpenEmbedded and the docker-library BusyBox images all carry patches or configuration changes that disable SHA1/SHA256 hardware acceleration on x86.

### Implemented on branch `boot/busybox-sha-hwaccel-baseline-20261108`

- `scripts/configure-busybox-baseline.sh` now disables `CONFIG_SHA1_HWACCEL` and `CONFIG_SHA256_HWACCEL` before `oldconfig`, and verifies both survived Kconfig processing. With both options off, `libbb/hash_md5_sha.c` compiles no CPUID dispatch and emits no references to the hwaccel objects, so the static linker does not pull the post-baseline assembly into the bootstrap binary. The portable generic SHA1/SHA256 implementations and the required applet set (`sha256sum`, `sha1sum`, etc.) are unchanged.
- `scripts/test-busybox-baseline-config.sh` gained HWACCEL-enabled fixture entries and assertions that both options are forced off and that the transformation stays deterministic and idempotent.
- `scripts/check-qemu64-baseline-isa.sh` now prints a compact mnemonic histogram (up to 20 mnemonics with counts) on the first error line, so a future rejection is diagnosable directly from the single-line CI annotation without downloading the log artifact. Rejection semantics are unchanged; the existing AVX/BMI1/BMI2 regression still passes because the detailed report lines are still printed.
- `README.md` development status records the new blocker and correction.
- No changes under `/linux`; no disk, partition, installer, updater, bootloader, or user-data behavior changed.

### Files changed

- `scripts/configure-busybox-baseline.sh`
- `scripts/test-busybox-baseline-config.sh`
- `scripts/check-qemu64-baseline-isa.sh`
- `README.md`
- `docs/AI-DEVELOPMENT-LOG.md`

### Validation status

- The previous PR #48 image runs prove the BusyBox source build itself now works (UAPI headers resolved, `tc` disabled, static link succeeded); the failure was solely the ISA scan. This branch's change removes the known source of post-baseline instructions, but no pass is claimed until a fresh run completes: the config-helper regression in `make test-shell`, the real BusyBox static build, the ISA scan, ISO assembly, and the qemu64 BIOS/UEFI/direct-kernel boot matrix must all pass on this branch's own head.
- If the ISA scan still fails after this change, the new mnemonic histogram in the annotation will identify the remaining offender directly; do not widen the CPU model or weaken the baseline check.

### Next priorities

1. Inspect this branch's userland and full image/boot workflow results.
2. If the ISA scan passes, inspect the qemu64 BIOS, UEFI, and direct-kernel boot results, including root hand-off and AYUI/recovery markers.
3. If boot faults recur, capture the faulting instruction with the existing tagged instruction-trace machinery before changing anything else.
4. Keep the stacked PR chain (#43 through this branch) unmerged until the base chain is reconciled and fresh required checks pass.
5. Preserve `/linux` read-only verification and the fail-closed, non-destructive installer/updater invariants.


## 2026-11-09 — Enforce BusyBox x86-64 baseline flags last

### Repository and CI inspection

- The default `master` branch is still at commit `0939488f5261b04c9c3af150e5e4dc8888896a9f` (2026-09-25); the active development work is on an unmerged stack. Do not treat the default branch as containing the November boot work.
- Inspected the open stack: PR #49 (draft) is based on PR #48 (draft), which is based on PR #47; PR #47 is based on PR #46. All remain unmerged. The new work is based on PR #49's head `7e7bb459770b37ade7590dcc55c517122017397e`, not on `master`.
- Latest PR #49 userland run `42492061640` passed all 13 steps, including shell/C regressions, Rust workspace tests, release builds, installer no-unattended-write verification, and AYUI's Xvfb compositor smoke test.
- Latest full image run `42492061559` failed at the real pinned BusyBox build's qemu64 ISA scan. The BusyBox configuration helper confirmed both `CONFIG_SHA1_HWACCEL` and `CONFIG_SHA256_HWACCEL` were disabled, and the static link completed, but the final ELF still contained VEX/AVX mnemonics (`vmovdqa`, `vmovaps`, `vpxor`, etc.), BMI instructions (`tzcnt`, `blsi`), and `movbe`. The ISO and BIOS/UEFI/direct-kernel boot tests were skipped because image creation stopped at this gate.
- The previous PR #48 image run also failed at the same ISA gate after resolving the UAPI headers and `tc` incompatibility. The latest result therefore does not support claiming that the BusyBox baseline is fixed.

### Implemented on `boot/busybox-cc-flags-last-20261109`

- Added `scripts/cc-x86_64-baseline.sh`, a compiler wrapper that appends the AWEOS x86-64-v1 target policy after every argument passed by BusyBox's build system. This addresses the observed gap in the previous approach: placing flags in the `CC` value did not guarantee they were the final target options once BusyBox supplied its own compile flags.
- The enforced policy selects `-march=x86-64 -mtune=generic` and explicitly disables AVX/AVX2/AVX-512F, BMI1/BMI2, MOVBE, POPCNT, LZCNT, SSE3/SSSE3/SSE4.1/SSE4.2, AES, PCLMUL, RDRAND, RDSEED, and ADX.
- The same wrapper is now used by the `<linux/kd.h>` musl UAPI preflight and by every BusyBox compile/link invocation. The actual `CC` command also preserves both `-idirafter` Linux UAPI include directories, so the earlier `linux/kd.h` fix remains in force while the final ISA policy is appended last.
- Added `scripts/test-x86_64-baseline-cc.sh`. It uses a fake compiler to verify that the baseline options are the final arguments even when conflicting `-march=native`, `-mavx2`, and `-mbmi2` flags are supplied; it also verifies compiler exit-code propagation and fail-closed handling of a missing compiler.
- Wired the new regression into `scripts/run-test-shell.sh`.
- Updated README status with the exact latest CI failure and the fact that boot tests were not reached.
- No files under `/linux` were changed. No installer, partition, disk, bootloader, updater, or user-data behavior was changed.

### Files changed

- `scripts/cc-x86_64-baseline.sh` (new)
- `scripts/test-x86_64-baseline-cc.sh` (new)
- `scripts/build-busybox-baseline.sh`
- `scripts/run-test-shell.sh`
- `README.md`
- `docs/AI-DEVELOPMENT-LOG.md`

### Validation

- The parent PR #49 head's userland CI passed, but that run does not validate this follow-up.
- This branch's compiler-wrapper regression, full `make test-shell`, Rust tests, BusyBox static build, qemu64 ELF scan, ISO build, and BIOS/UEFI/direct-kernel boot tests have not yet run. No pass is claimed.
- The local environment in the prior run lacked a working GCC/musl-gcc toolchain; GitHub Actions with the real Ubuntu toolchain remains the authoritative build test.
- `/linux` remains outside the change set by design; CI must continue to run `scripts/verify-linux-readonly.sh`.

### Unresolved issues and next priorities

1. Run the new branch's userland workflow and confirm the compiler-wrapper regression passes.
2. Run the full image workflow and inspect the actual BusyBox compiler commands and ISA scan. If post-baseline instructions remain, identify the offending object/toolchain component; do not weaken the scanner or widen the qemu64 CPU model.
3. Require a successful static BusyBox build, complete required applet check, qemu64 ISA scan, ISO assembly, and BIOS/UEFI/direct-kernel QEMU matrix before claiming image/boot success.
4. Reconcile the stacked PR bases only after fresh checks pass on the final head; do not merge an unverified stack.
5. Continue preserving the read-only `/linux` boundary and fail-closed installer/updater guarantees.


## 2026-11-09 — Diagnose the remaining BusyBox x86-64 baseline violation

### Fresh CI evidence

- Full image/boot run `42565058549` on PR #50 head `9f887e25bd692c973235b60e4ba4bf2067b84ab9` completed the shell/C/rootfs/session/QEMU-runner regressions, `/linux` read-only verification, and Cargo workspace tests successfully.
- The real pinned BusyBox 1.38.0 static build completed, but `check-qemu64-baseline-isa.sh` rejected the resulting ELF. The diagnostic reported VEX/AVX instructions (including `vpxor`, `vmovdqa`, `vmovaps`), BMI instructions (`tzcnt`, `blsi`, `sarx`), and `movbe`.
- ISO assembly and BIOS/UEFI/direct-kernel QEMU boot tests were skipped because the BusyBox ISA gate failed. No image or boot success is claimed.
- The same commit's userland validation run `42565058648` passed. This does not validate the real BusyBox image build.

### Implemented on `boot/busybox-cc-flags-last-20261109`

- Extended `scripts/test-x86_64-baseline-cc.sh` to exercise an installed real musl compiler, deliberately pass hostile `-march=native -mavx2 -mbmi2` options, compile a probe object through the wrapper, and run the actual object through the qemu64 ISA scanner.
- The real-compiler test also inspects GCC's effective `-Q --help=target` state and requires AVX, BMI, MOVBE, POPCNT, LZCNT, post-baseline SSE, AES, PCLMUL, RDRAND, RDSEED, and ADX to be disabled while baseline SSE2 remains enabled. It skips only in test environments without the musl compiler; the image workflow installs `musl-tools` and the BusyBox build itself still requires the compiler.
- `scripts/build-busybox-baseline.sh` now writes `build/busybox-compiler-target-report.txt` and fails before the BusyBox source build if the real compiler does not report the expected target feature state.
- `scripts/check-qemu64-baseline-isa.sh` now includes the enclosing symbol label with rejected instruction lines, so the next CI failure can identify which function contains the non-baseline code.
- No files under `/linux` were changed. Installer, disk, partition, bootloader deployment, updater, and user-data behavior remain unchanged.

### Files changed in this run

- `scripts/test-x86_64-baseline-cc.sh`
- `scripts/check-qemu64-baseline-isa.sh`
- `scripts/build-busybox-baseline.sh`
- `docs/AI-DEVELOPMENT-LOG.md`

### Validation status

- The source changes have been committed to the existing PR #50 branch in three small commits. The new real-compiler probe, target-report gate, and symbol-aware scanner have not yet been validated by a fresh GitHub Actions run.
- The previous run's passing shell/C tests, Cargo tests, and `/linux` integrity check are evidence for the prior head only; do not carry those results forward as validation of the new commits.
- No local musl toolchain is available in this environment, so no local BusyBox build or local musl compiler result is claimed.

### Next priorities

1. Inspect the fresh PR #50 userland run and require the real compiler probe to pass on the image runner.
2. Inspect the fresh full image run. Confirm the effective target report explicitly disables the required extensions.
3. If the BusyBox ELF still fails, use the newly emitted symbol labels and verbose instruction context to locate the offending function; determine whether it is compiler-generated code, an assembly object, or a linked library before changing build flags.
4. Do not weaken the qemu64 ISA scanner or widen the CPU model to hide the incompatibility.
5. Only after the BusyBox static build, required applet check, ISA scan, ISO assembly, and BIOS/UEFI/direct-kernel boot matrix pass on the final reconciled head should the stacked PRs be considered for merge.


### CI correction — remove an ambiguous TZCNT probe instruction (2026-11-09)

- Follow-up full-image run `42567483733` stopped in `make test-shell` before image building. The new real-compiler probe itself produced one `tzcnt` mnemonic from `__builtin_ctzll`; the symbol-aware scanner correctly exposed the probe function, but the test was not isolating the intended AVX/BMI2 override behavior.
- GCC can encode a nonzero-input count-trailing-zeros operation using the REP-prefixed BSF encoding, which modern `objdump` names `tzcnt`. On CPUs without BMI1 that encoding executes as BSF; the probe explicitly guarded against zero. The current scanner intentionally remains conservative and rejects the mnemonic, so the probe should not manufacture it.
- Replaced the probe's `__builtin_ctzll` expression with low-bit extraction and a variable shift. These patterns still exercise AVX/BMI code generation under the hostile flags without intentionally requesting the ambiguous TZCNT/BSF encoding.
- This run did not reach the BusyBox build. The separate prior BusyBox failure remains unresolved: its report included AVX/VEX instructions, `blsi`, `sarx`, and `movbe` in addition to `tzcnt`. No conclusion about the actual BusyBox binary can be drawn from the probe-only failure.
- The `/linux` read-only verification step still passed after the shell-test failure. ISO assembly and all boot tests were skipped.
- The corrected probe has not yet been validated by a fresh workflow run. Keep PR #50 in draft until the new test, BusyBox build, ISA scan, ISO, and BIOS/UEFI/direct-kernel boot checks pass.
## 2026-11-09  -  Attribute the remaining BusyBox qemu64 ISA violation with persistent CI evidence

### Repository and CI inspection

- The active stack is unchanged: PR #50 (draft) is based on PR #49 (draft); PR #47/#48/#49 and their bases remain unmerged; `master` is still at `0939488` (2026-09-25). This run continues on the existing PR #50 branch head `2dad984547e4290d5c9fcd4e70d3af4a9eab07bc` without force pushes.
- PR #50's userland run `42567776056` passed. The full image run `42567776075` failed at the BusyBox qemu64 ISA gate before ISO assembly or any boot test, with mnemonics `vmovdqa(61), vmovaps(80), vcvtsi2sd(15), movbe(22), vpermpd(2), vinserti128(4), tzcnt(5), blsi(2), ...` in the linked ELF.
- Decisive observation: the new pre-build effective-target gate passed on this run, which proves the wrapper produces a correct x86-64-v1 target state for the invocations it compiles. The remaining violating instructions therefore come either from linked inputs the wrapper never compiles (prebuilt musl `libc.a`, `libgcc.a`, crt objects on the runner) or from invocations that bypass the wrapper. The previous CI evidence could not distinguish these cases: the symbol-labeled scan report was deleted by the checker's EXIT trap and the raw job log is not readable through the available tooling.
- No change to the BusyBox result is claimed; the failure remains unresolved until the attribution evidence and a green image run exist.

### Implemented on `boot/busybox-cc-flags-last-20261109`

- `scripts/check-qemu64-baseline-isa.sh`:
  - `AWEOS_ISA_REPORT_OUT=<path>` persists the full symbol-labeled report file; the fail-closed verdict and exit codes are unchanged.
  - The first ERROR line now also names the top six offending symbols, so the single-line CI annotation identifies the actual functions without downloading logs.
  - New `AWEOS_ISA_SOFT=1` diagnostic mode never fails: it prints machine-readable `AWEOS_ISA_OFFENDERS=<count>` and `AWEOS_ISA_SYMBOLS=<names>` and exits 0. In soft mode the checker also accepts `ar` archives so linked static-library inputs can be scanned; strict mode still rejects non-ELF inputs.
- `scripts/build-busybox-baseline.sh`: when the final BusyBox ELF fails the ISA scan, the build now persists the report to `build/busybox-isa-report.txt` and writes an attribution to `build/busybox-isa-attribution.txt` by soft-scanning every linked input: all BusyBox `built-in.a` archives (falling back to all non-`scripts/` objects if kbuild archives are absent), the prebuilt musl `libc.a` (located via the compiler or standard musl paths), `libgcc.a`, and the crt objects. It prints a `DIAGNOSIS:` section naming exactly which inputs are dirty, then still exits non-zero: packaging remains fail-closed.
- `.github/workflows/build-aweos-x86_64.yml`: the image-build failure summary now inlines the attribution file, and the failure artifact upload includes the BusyBox ISA report, attribution, compiler target report, and failure summary.
- `scripts/test-qemu64-baseline-isa.sh`: regressions for report persistence (both failing and passing inputs), symbol names on the error line, soft-mode offender counts and symbols, soft-mode archive scanning, strict-mode archive rejection, and soft-mode exit status.
- No files under `/linux` were changed. No installer, disk, partition, bootloader, updater, or user-data behavior changed. The qemu64 ISA scanner was not weakened and the qemu64 CPU model was not widened.

### Files changed

- `scripts/check-qemu64-baseline-isa.sh`
- `scripts/build-busybox-baseline.sh`
- `scripts/test-qemu64-baseline-isa.sh`
- `.github/workflows/build-aweos-x86_64.yml`
- `docs/AI-DEVELOPMENT-LOG.md`

### Validation status

- The edited scripts were line-by-line reviewed, but this environment provides no usable shell (`bash -n` is unavailable here) and no musl toolchain, compiler, or binutils, so no local syntax run, BusyBox build, or checker execution is claimed. GitHub Actions remains the authoritative validator.
- No workflow run has validated this head yet. The expected outcome of the next run is: userland passes; the image build fails (expected) at the ISA gate, but now with a `DIAGNOSIS:` section, persisted symbol report, and artifacts naming the offending linked input. If the dirty input is a prebuilt musl/libgcc archive, the correct fix is building those components from source under the same baseline policy, not flag changes and not scanner weakening.

### Unresolved issues and next priorities

1. Read the new attribution evidence from the next CI run and fix the actual source of the violation (primary hypothesis: prebuilt musl `libc.a` or `libgcc.a` from the runner's `musl-tools` package).
2. If toolchain archives are confirmed as the source, add a pinned from-source musl build under the enforced x86-64-v1 policy so the bootstrap binary no longer depends on distro-built archives.
3. Keep PR #50 in draft and the stacked chain unmerged until the static BusyBox build, required applet check, qemu64 ISA scan, ISO assembly, and BIOS/UEFI/direct-kernel boot matrix all pass on a reconciled head.
4. Preserve the fail-closed installer/updater invariants and the read-only `/linux` boundary in every subsequent change.

## 2026-11-10 — Repair PR #50 BusyBox build-script regressions

### Repository and CI inspection

- Continued on the existing draft PR #50 branch `boot/busybox-cc-flags-last-20261109`, based on head `04232014125fea586f7dbd5a82f5d15f9f92f4ea`; the stacked PR chain remains unmerged.
- Latest full-image run `42634171192` and userland run `42634171131` both stopped in the shell regression gate. The exact failure was `bash -n`: `scripts/build-busybox-baseline.sh: line 272: unexpected EOF while looking for matching '"'`.
- The failing step ran before Rust tests, image assembly, ISO generation, or BIOS/UEFI/direct-kernel boot tests. The `/linux` read-only integrity check passed.

### Implemented on this branch

- Removed the extra trailing quote from the temporary BusyBox checksum filename assignment, restoring valid shell syntax.
- Corrected the `getconf` key from the misspelled `_NPROCESSORS_ONLO` to Linux's `_NPROCESSORS_ONLN`, so automatic build parallelism is detected instead of always falling back to two jobs.
- Fixed a false-positive required-applet check. The previous code compared each applet against itself, so missing BusyBox commands could never be detected. Extracted the check into `scripts/check-busybox-applets.sh`; it now reads the actual binary's `--list` output and fails closed on missing applets or a failed `--list` command.
- Extended `scripts/test-busybox-baseline-config.sh` with fake-BusyBox regressions for complete applet lists, missing applets, and `--list` execution failure. The existing `make test-shell` runner syntax-checks every `scripts/*.sh` file and runs this regression script.

### Files changed

- `scripts/build-busybox-baseline.sh`
- `scripts/check-busybox-applets.sh` (new)
- `scripts/test-busybox-baseline-config.sh`
- `docs/AI-DEVELOPMENT-LOG.md`

### Validation status

- Changes are committed to the existing PR #50 branch; this entry does not claim that tests passed.
- Fresh GitHub Actions results are required to verify shell syntax, the BusyBox applet regression, Rust/userland checks, the real BusyBox build, qemu64 ISA validation, ISO assembly, and the BIOS/UEFI/direct-kernel boot matrix.
- No files under `/linux` were modified. No installer, partition, disk, updater, or user-data behavior was changed.

### Next priorities

1. Inspect fresh PR #50 userland and full-image workflow runs; confirm the shell and applet regressions pass.
2. Continue from the first real build failure after the shell gate. Use the persisted ISA report and linked-input attribution rather than weakening the x86-64 baseline scanner.
3. Keep PR #50 and its stacked predecessors in draft/unmerged state until the final reconciled head passes the required build and boot matrix.

## 2026-11-10 follow-up — Keep the ISA checker report output opt-in

- A post-commit review found that `AWEOS_ISA_REPORT_OUT` defaulted to the literal `-`, while the EXIT cleanup treated every non-empty value as a destination path. Normal checker invocations could therefore create a stray file named `-` in the caller's working directory.
- Changed the unset default to an empty string. Report persistence remains enabled only when an explicit output path is supplied; fail-closed scan behavior is unchanged.
- Extended `scripts/test-qemu64-baseline-isa.sh` to run the checker with no report path from an isolated directory and assert that no `-` file is created. Existing explicit report-persistence tests remain.
- Validation: this follow-up is committed to the PR #50 branch. Fresh GitHub Actions results are required; no pass is claimed until the updated shell/ISA tests and image pipeline complete.
