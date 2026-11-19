# AWEOS AI Development Log

## 2026-11-12 — Rootfs regression and ISO-build stack integration

### Repository and stack state inspected
- Repository: `ARARAT33/AWEOS`; default branch: `master`.
- The default branch head remains `0939488f5261b04c9c3af150e5e4dc8888896a9f`; the active work is carried in separate, unmerged pull-request branches.
- PR #52 (`fix/rootfs-script-invocation-20261111`) is open and draft, based on `master`.
- PR #28 (`fix/hybrid-iso-efi-partition-20261103`) is open and draft, based on PR #27 (`fix/transaction-engine-fail-closed-20261101`). PR #27 is also open and draft, based on `master`.
- This run's integration branch is `stack/rootfs-iso-ci-hardening-20261112`, created from PR #28's head. It is intentionally stacked on PR #28 so the known ISO fix is inherited rather than copied or reimplemented.

### Actual CI diagnosis
- PR #52 userland run #42963145758 completed successfully. Its shell/rootfs regression, Cargo metadata, Rust workspace tests, release build, and expected-binary checks passed.
- PR #52 full image run #42963145650 failed in job #130334163189 during `make image`, after the Rust build, rootfs creation, rootfs validation, and initramfs creation had succeeded.
- The actual failing output was:
  - `libisofs: FAILURE : Cannot open data file for appended partition`
  - `xorriso : FAILURE : Failed to prepare session write run`
  - `make: *** [Makefile:75: iso] Error 32`
- The same failure was independently present in image run #42962547574.
- Inspection of PR #52's `scripts/build-iso.sh` found `-efi-boot-part -efi-boot-image`. The single-dash token is interpreted as a path argument, not the xorrisofs special EFI image token.
- This exact issue is already corrected in PR #28: its ISO builder uses `-efi-boot-part --efi-boot-image`, builds in a unique temporary workspace, and publishes the ISO only after xorriso and Limine BIOS installation succeed. Its mock regression test checks both the option pair and failure-safe publication. This run reuses that existing fix by stacking on PR #28; it does not duplicate the ISO implementation.

### Changes made on this branch
- `scripts/build-rootfs.sh`: invoke the optional GNOME rootfs builder through Bash. The script is stored without an executable Git mode, so direct execution would fail when `AWEOS_DESKTOP=gnome`.
- `scripts/test-rootfs-layout-validator.sh`: add a fixture-based regression that invokes the real `make validate-rootfs` target, accepts a valid rootfs layout, and rejects a missing boot-critical configuration file.
- `Makefile`: include the rootfs validator regression in `make test-shell`.
- `.github/workflows/build-aweos-x86_64.yml`: run the full shell/rootfs regression suite before image construction; capture `make image` output; publish the final log tail in the Actions step summary and upload build/QEMU logs on failure.
- No files under `/linux` were changed.

### Validation status
- Existing evidence from PR #52: userland workflow #42963145758 **PASS**.
- Existing evidence from PR #52: full image workflow #42963145650 **FAIL** at xorriso ISO assembly; BIOS/UEFI boot steps were skipped.
- The new stacked branch has just been created and updated. Its own GitHub Actions checks have not yet completed. No test on this exact branch is claimed as PASS.
- No local kernel, ISO, or QEMU build was run in this connector-only environment.

### Remaining issues
1. Run the new branch's shell/rootfs tests and inspect their exact output.
2. Run the full x86_64 image workflow against the combined PR #27 → PR #28 → this branch stack.
3. If ISO assembly succeeds, inspect the next actual failure rather than assuming the build or boot is complete.
4. Require BIOS and UEFI QEMU boot results, serial markers, and artifact validation before any boot-success claim.
5. Keep PRs #27 and #28 unmerged until their parent/stack relationships and final-head checks are reviewed.
6. The AWEOS network platform, device identity, distributed services, production package signing/sandboxing, and broad hardware support remain separate implementation work; do not imply they are complete from the current build checks.

### Next run priorities
1. Review this branch's Userland Validation and full image/boot workflow results.
2. Use the captured `build-make-image.log` artifact/summary to identify the next concrete failure, if any.
3. Fix only the proven failure with a regression test.
4. Re-run the affected checks and preserve the `/linux` read-only invariant.
5. Update this log with exact run IDs, job conclusions, and test evidence.


### CI follow-up — PR #53 first validation
- New stacked PR #53 triggered Userland Validation run #43158921437 and full image/boot run #43158921451.
- Userland run #43158921437: the complete `make test-shell` step **PASS**, repository-boundary validation **PASS**, and Cargo metadata validation **PASS**. Cargo workspace tests were still running at the last poll.
- Full image/boot run #43158921451: runner setup and build-dependency installation **PASS**; the Limine host utility build was in progress. Shell/rootfs tests, image assembly, and BIOS/UEFI QEMU boot remained pending at the last poll.
- These are checks on the new stacked branch. No full image, ISO, BIOS, UEFI, or boot success is claimed until the corresponding steps complete.


### Parent-stack boot blocker discovered during follow-up
- PR #28's full image run #41576689314 completed the image/ISO build successfully and passed the post-build `/linux` integrity check.
- Its BIOS QEMU test then failed with: `FAIL: root filesystem never reached its boot hand-off marker in BIOS mode.`
- The UEFI test and later artifact checks were skipped because the workflow stops after the BIOS failure.
- The prior workflow output exposed no serial lines from the BIOS QEMU run, and that workflow did not upload `build/qemu-bios.log` on failure. The absence of the hand-off marker alone does not prove whether the cause is firmware boot selection, serial-console visibility, kernel startup, or rootfs discovery.
- PR #53 adds failure-path upload of the QEMU serial logs. Use that evidence before changing the boot/initramfs path; do not mask the missing marker or weaken the boot assertion.


### CI completion update
- Userland Validation run #43158921437 completed with overall conclusion **success**. All steps passed, including `make test-shell` (which includes the new valid/invalid rootfs fixture), repository-boundary verification, Cargo metadata, Rust workspace tests, release userland build, and expected-binary checks.
- Full image/boot run #43158921451 had passed its setup, dependency installation, Limine host utility build, initial `/linux` integrity check, Rust workspace tests, and shell/rootfs regression suite. The `Build AWEOS images` step was still running at the last poll; BIOS/UEFI boot and release-artifact validation had not started.



## 2026-11-13 run — Boot-marker mismatch fix and annotation-based diagnostics

### CI results inspected
- PR #53 branch workflow runs on the final head all failed: run #576 (10m 32s), #577 (16m 11s), #578 (15m 9s), #579 (16m 29s), all exit code 2, no artifacts visible on the public run page.
- Actions logs and artifacts require an authenticated session and the REST API is rate-limited from this environment, so the failing step could not be read directly for runs #577-#579.
- Parent-stack evidence remains: PR #28's image run #41576689314 built the ISO successfully, then failed the BIOS QEMU test at the boot hand-off marker.

### Root cause found by source inspection
- `scripts/build-rootfs.sh` emits `AWEOS BOOT SUCCESS: mode=aweui` for the AYUI session (limine.conf passes `aweos.mode=aweui`), but `scripts/run-qemu-tests.sh` only accepted `mode=ayui`, `mode=gnome`, or the compositor marker. Once the hand-off marker appears, the boot test would fail on the session check even for a successful AYUI boot.

### Changes made
- `scripts/run-qemu-tests.sh`: accept `mode=aweui` and the legacy `mode=gui` default as the AYUI desktop session; emit the last serial-log lines as GitHub `::error::` annotations on every boot-test failure path so the concrete failure is readable on the public run page without sign-in.
- `.github/workflows/build-aweos-x86_64.yml`: the make-image failure diagnostics step now also emits the matching error lines from `build-make-image.log` as run-page `::error::` annotations.
- No production runtime code was changed; no files under `/linux` were touched.

### Validation status
- `bash -n` syntax checks were not run locally in this connector-only environment; the changes are validated by CI. No boot success is claimed.

### Next run priorities
1. Read the `::error::` annotations on the next PR #53 image run page to identify the exact failing command inside `make image` or `make test-qemu`.
2. Fix only the proven failure; keep the boot assertions strict.
3. Keep PRs #27, #28, #51, #52, #43-#50 unmerged until their own gates pass; the integration path remains #27 -> #28 -> #53.


## 2026-11-14 run — QEMU runner permission failure fixed

### Latest PR #53 CI evidence inspected
- PR #53 head before this fix: `facbf0e18cbd626656208f2b80a730dd96d09350`.
- Userland Validation run #43442358277 completed with conclusion **success**.
- Full image and boot run #43442358400 completed with conclusion **failure**. The job steps show that setup, Limine host utility build, `/linux` pre-check, Rust workspace tests, shell/rootfs regressions, image build, and post-build `/linux` check all passed.
- The `Build AWEOS images` step completed successfully. The ISO was assembled and Limine BIOS stages were installed successfully. The image target then completed; the post-build `/linux` integrity check passed.
- The next step, `Boot-test BIOS and UEFI ISO`, failed before QEMU started:
  `/bin/bash: line 1: ./scripts/run-qemu-tests.sh: Permission denied`
  `make: *** [Makefile:103: test-qemu] Error 126`
- Therefore neither BIOS nor UEFI boot was actually tested in this run. This is a script invocation/mode failure, not evidence of a kernel boot failure.

### Root cause
- `scripts/run-qemu-tests.sh` is tracked in Git with mode `100644` (not executable).
- The Makefile's `test-qemu` target attempted to execute it directly as `./scripts/run-qemu-tests.sh`.
- This is the same class of failure previously found in the optional GNOME rootfs builder and validator scripts: a non-executable shell script must be invoked through Bash.

### Changes made on the PR #53 branch
- `Makefile`: changed the QEMU test recipe to `bash ./scripts/run-qemu-tests.sh $(BUILD_DIR)` and documented why explicit Bash invocation is required.
- `Makefile`: added `scripts/test-qemu-runner-invocation.sh` to `make test-shell`.
- `scripts/test-qemu-runner-invocation.sh` (new): checks that the QEMU runner is tracked as mode `100644` and that the Makefile invokes it through Bash. This prevents the same permission regression from silently returning.
- No production kernel, initramfs, installer, partitioning, updater, or disk-write behavior was changed. No files under `/linux` were modified.

### Commits
- `e7d7a61a8b42b970499773255cf40aeaf8ef8fff` — invoke QEMU boot runner through Bash.
- `ed8006be5e700a3f5971b11f103d3e06617d1237` — add regression guard for the invocation.

### Validation status
- PR #53 Userland Validation run #43442358277: **PASS** on the pre-fix head.
- PR #53 full image/boot run #43442358400: image build and post-build `/linux` check **PASS**; boot-test step **FAIL** before QEMU launch due to the permission error above.
- The new fix has been committed to the same PR branch. Its fresh CI checks have not yet completed, so the new regression test and BIOS/UEFI boot results are **pending**.
- No local kernel, ISO, or QEMU build was run in this connector-only environment.

### Remaining issues
1. Confirm the new invocation regression passes in `make test-shell`.
2. Confirm the QEMU runner launches after the permission fix.
3. Inspect BIOS serial output and determine whether the expected boot marker and AYUI compositor are reached.
4. Run UEFI boot separately; do not infer it from BIOS.
5. Verify release artifacts and checksums only after the boot matrix passes.

### Next run priorities
1. Review fresh PR #53 Userland Validation and full image/boot runs on the updated head.
2. If BIOS fails after QEMU launches, use the serial log and error annotations to diagnose the actual boot path.
3. Run and record UEFI independently.
4. Keep PR #53 stacked on PR #28 and do not merge unverified stack components.
5. Continue preserving the `/linux` read-only integrity check.


### Post-fix CI and architecture/security audit — 2026-11-14
- Updated-head Userland Validation run #43558706411 completed with conclusion **success**. The `make test-shell` step passed, including the new `test-qemu-runner-invocation.sh`; its exact output was: `PASS: test-qemu invokes the mode-100644 QEMU runner through Bash.` Cargo metadata, workspace tests, release userland build, and expected-binary checks also passed.
- Updated-head full image/boot run #43558706392 was still **in progress** at the time of this log update. The runner setup, dependency installation, Limine host utility build, and initial `/linux` integrity check had passed. No image, BIOS, UEFI, or release-artifact result is claimed for this run yet.
- The invocation regression was also reproduced locally in an isolated temporary Git repository with the runner tracked as mode `100644`; the test passed.

### Additional concrete audit findings for follow-up
1. **AOSIN is not yet a real package payload system.** `src/aosin/aosin_core.c` ignores `payload_dir`, writes a fixed 1 KiB dummy payload, hardcodes the SHA-256 of an empty input, and its installer only writes package metadata. Inspection checks the magic value but does not validate the payload hash, format version, architecture, or a publisher signature. The C AOSIN sources are not included in the current Cargo workspace or current Makefile build.
2. **The installed legacy `awepkg` helper is unsafe for untrusted packages.** `scripts/build-rootfs.sh` copies `scripts/awepkg.sh` into the root filesystem as `/usr/bin/awepkg`. Its `install` path extracts an unsigned tar archive, then copies the extracted `root/` tree into `/` while suppressing copy errors. It has no signature/trust-anchor verification or safe archive-path validation. Treat package installation as a critical security blocker; do not represent this as a production-safe package manager.
3. **AYUI IPC requires a security redesign before production.** `AWEUI/src/state.rs` places the socket at `/tmp/aweui-ipc.sock`; `IpcServer::new` unconditionally removes the existing path; the server does not set a restrictive socket mode or authenticate peer credentials. The request API includes `LaunchCommand` and `PowerAction`. The current rootfs init launches `/usr/bin/aweui` directly from PID 1, so the compositor currently runs as root. Together these conditions create a local privilege-escalation risk if the socket is reachable by another local user.
4. **The active AYUI implementation is narrower than the README implies.** `AWEUI/src/wayland.rs` initializes Smithay's Winit backend; its event loop handles keyboard events and maps absolute pointer motion to focus on the first toplevel, but does not implement normal pointer-seat motion/button handling. The separate C framebuffer desktop under `src/gui` is not built by the current Makefile. The README describes that C desktop and C core/AOSIN stack as part of the active product, while the current Makefile primarily builds the Rust workspace, Linux kernel, rootfs, initramfs, ISO, and disk image.
5. **Documentation/build contract drift exists.** The README states that `make test` runs QEMU BIOS/UEFI checks, but the current Makefile's `test` target runs read-only, shell, and Rust tests only; QEMU is a separate `test-qemu` target. The README's stated default rootfs size also differs from the 512 MiB default in `scripts/build-rootfs.sh`.

### Next priorities after the current boot run
1. Complete the QEMU runner launch and inspect actual BIOS serial output; then verify UEFI separately. Keep boot assertions strict.
2. Harden AYUI IPC: place the socket in a private runtime directory, use safe socket ownership/type checks, set restrictive permissions, authenticate peers, and remove or gate privileged commands until authorization exists. Run the desktop as an unprivileged session user.
3. Disable unsafe unsigned `awepkg install` behavior until a real signed package format and trust-anchor management are implemented; add archive traversal and failure-atomicity tests.
4. Replace the dummy AOSIN payload with a versioned, bounded package format that verifies payload hashes and cryptographic signatures before installation; integrate its build and tests explicitly.
5. Reconcile the README with the actual build graph, or deliberately integrate the C desktop/core after reviewing duplicate Rust/C implementations.
6. Continue the network platform and hardware support only after the boot, privilege boundary, and package trust foundations are verified.


## 2026-11-14 follow-up — truthful AYUI and UEFI boot assertions

### Why the boot assertion was tightened
- Source inspection found that the prior QEMU runner treated `AWEOS BOOT SUCCESS: mode=...` as desktop success. The marker was printed by rootfs init before `exec /usr/bin/aweui`, so it proved only that init reached the hand-off, not that AYUI started.
- The initramfs fallback also printed a generic `AWEOS BOOT SUCCESS` while dropping into a recovery shell. The QEMU runner did not accept that exact generic marker, but the wording was misleading and could confuse manual diagnosis.
- The active Rust AYUI backend uses Smithay's Winit backend. A compositor readiness marker is now emitted only after the backend successfully submits its first frame. This is a compositor milestone, not proof that the full desktop shell, pointer handling, or multi-monitor features are complete.

### Changes made on PR #53
- `AWEUI/src/wayland.rs`: emit `AWEOS COMPOSITOR READY: session=ayui backend=winit first-frame=1` only after the first successful frame submission.
- `AWEUI/src/main.rs`: replace the premature boot-success claim with a userland-starting message; remove the premature “services online” claim.
- `scripts/build-rootfs.sh`: emit `AWEOS ROOTFS READY: mode=...` for the init hand-off, clearly distinct from compositor readiness.
- `scripts/build-initramfs.sh`: label the missing-rootfs fallback as `AWEOS BOOT RECOVERY` and `AWEOS RECOVERY SHELL READY`, not boot success.
- `scripts/build-rootfs-gnome.sh`: rename its pre-GDM marker to `AWEOS GNOME SERVICE STARTED`; it does not claim GNOME desktop readiness.
- `scripts/run-qemu-tests.sh`: require both the rootfs hand-off marker and an AYUI compositor/desktop readiness marker. Rootfs-only boot no longer passes as a desktop boot.
- `scripts/run-qemu-tests.sh`: reject unsupported target modes and fail the run if OVMF firmware is unavailable; UEFI can no longer be silently skipped. Added `AWEOS_OVMF_FIRMWARE` for an explicit firmware path.
- `scripts/test-qemu-boot-readiness.sh` (new): fake-QEMU regression verifies that rootfs-only output fails, compositor first-frame output passes, a valid OVMF path runs the UEFI check, and a missing OVMF path fails closed.
- `Makefile`: include the new boot-readiness regression in `make test-shell`.

### Local validation
- `bash -n` passed for the QEMU runner and its new regression test in an isolated local test harness.
- The fake-QEMU regression passed: `PASS: QEMU boot validation requires compositor readiness and cannot skip UEFI firmware.`
- These are local regression-harness results only. They do not prove a real kernel, BIOS, UEFI, or AYUI boot.

### GitHub Actions status at this update
- The earlier Userland Validation run #43558706411 passed on the pre-readiness-hardening commit and included the QEMU-runner permission regression.
- Latest-code runs for head `dfd2d989e32f21f42ded0cfd0b58f31ea7850556` were queued:
  - Userland Validation #43559417743 (pull_request) and #43559414990 (push).
  - Full image/boot #43559417776 (pull_request) and #43559415041 (push).
- Intermediate runs #43559324684 and #43559324643 were also queued for the previous code head `7c57e0b851c37343b11ddb4720737c56f162c828`.
- Earlier full image run #43558706392 remained in progress on the older head `7f38d449e61050616b186930b2193a68c3b56da0`; it predates the stricter compositor/UEFI assertions and must not be used to claim desktop readiness.

### Important limitations and next priorities
1. The default minimal rootfs has no X11/Wayland display server, while the current AYUI code initializes only Smithay's Winit backend. The stricter QEMU test may therefore expose that AYUI cannot yet start on bare hardware/headless QEMU. If it fails, implement and test a real DRM/KMS/udev backend or explicitly keep the desktop milestone blocked; do not restore the weaker rootfs-only success check.
2. A compositor first frame is not a complete desktop shell. Pointer-seat events, a rendered panel/launcher, application lifecycle, and multi-monitor support remain incomplete.
3. Review and fix the critical package-manager and AYUI IPC issues recorded above before treating the current userspace as production-safe.
4. Reduce duplicate Actions execution: both `push` and `pull_request` currently trigger the same validation workflows for a same-repository PR branch. Consider a concurrency policy or trigger adjustment after this boot run.
5. Keep PR #53 draft and stacked on PR #28; no BIOS, UEFI, release-artifact, or full-desktop success is claimed until the latest-head workflows complete.


### Commit trace for the 2026-11-14 boot-validation follow-up
- `7c458de613` — emit AYUI compositor first-frame marker.
- `82d4595119` — remove premature AYUI boot-success/services-online messages.
- `e0720cf911` — distinguish rootfs readiness from desktop readiness.
- `e88b71aac6` — mark initramfs fallback as recovery.
- `81f07f7032` — relabel the GNOME pre-GDM service marker.
- `e6f7cbf295` — require compositor readiness in the QEMU runner.
- `09b906d660`, `0aeefee8d4`, `7c57e0b851` — add and correct the fake-QEMU readiness regression.
- `e6c31d9458`, `dfd2d989e3` — fail closed for missing UEFI firmware and test both present/missing OVMF cases.
- `8912fad3fb` — record the strict boot-validation design and test status.
- Latest code tested by the queued workflows is `dfd2d989e3`; the current PR head is `8912fad3fb` because the final commit only updates this log.


## 2026-11-15 run — Optical rootfs discovery and boot diagnostics

### Repository and CI state inspected
- Continued from PR #54 integration head 63b06170134b41bd3e6a3a677feeaa9d22c1bbad on stack/rootfs-iso-ci-hardening-20261112; default master remains at 0939488f5261b04c9c3af150e5e4dc8888896a9f.
- PR #54 remains open and draft. Its latest inspected checks were:
  - Full image/boot run #43607134518: kernel build, rootfs validation, initramfs build, ISO assembly, and post-build /linux integrity check passed; BIOS boot failed before the rootfs hand-off marker.
  - Userland run #43607134538: passed.
  - Core archive/preservation run #43607134519: passed.
- The failed BIOS job's QEMU log was empty, so the failure cannot yet be called a confirmed kernel panic or confirmed rootfs mount failure. The previous workflow attempted to upload QEMU logs before QEMU ran, so a later boot failure produced no downloadable serial-log artifact.

### Source-level boot-path finding
- The live ISO stores rootfs.img under /boot/rootfs.img and the initramfs locates it by mounting the optical device and then loop-mounting the ext4 image.
- The kernel configuration enabled SCSI and ISO9660 but did not explicitly enable CONFIG_BLK_DEV_SR. That SCSI CD-ROM driver is required for the optical device path and is not available to the initramfs if it is only built as a module.
- The initramfs also performed a one-shot device scan after a fixed one-second sleep. This could miss asynchronously discovered optical/storage devices.
- These are concrete configuration/discovery gaps consistent with the observed missing rootfs marker; the next QEMU run must verify whether they explain the failure.

### Changes on fix/qemu-optical-rootfs-discovery-20261115
- scripts/config-kernel.sh: reapply AWEOS-required kernel settings even when an existing .config is present; explicitly build CONFIG_CDROM and CONFIG_BLK_DEV_SR into the kernel.
- scripts/verify-kernel-config.sh (new): fail closed unless boot-critical initramfs, ext4, ISO9660, loop, SCSI CD-ROM, SATA/AHCI, and block-device options are built in (=y).
- scripts/test-kernel-config-requirements.sh (new): verifies valid built-in settings pass and missing, module-only, or absent configuration fails.
- Makefile: include the kernel-config regression in make test-shell.
- scripts/build-initramfs.sh: retry direct and optical-media discovery for up to 15 seconds; validate the mounted rootfs has /sbin/init; mount the ISO's rootfs image read-only as an OverlayFS lower layer.
- Bootloader/x86_64/limine-ci.conf (new): enable Limine serial/verbose output, kernel log output, early serial console, and synchronous SCSI discovery for CI diagnostics.
- .github/workflows/build-aweos-x86_64.yml: build the CI image with the diagnostic Limine profile and upload build/QEMU logs after the boot-test step, including when QEMU fails.
- No files under /linux were modified. No installer partitioning, disk-write, updater, or user-data behavior was changed.

### Validation status
- The repository connector was used to inspect and edit the remote branch; this environment did not run a local kernel build or QEMU boot.
- The new shell regression and full CI image/BIOS/UEFI boot matrix are pending GitHub Actions on the new branch.
- No BIOS, UEFI, or full AYUI boot success is claimed.

### Remaining critical issues
1. Confirm that CONFIG_BLK_DEV_SR=y survives the real kernel's olddefconfig and that QEMU discovers /dev/sr0.
2. Inspect the newly retained serial logs if BIOS or UEFI still fails; diagnose the first failing boot stage rather than weakening the marker assertions.
3. Harden AYUI IPC: the current socket is in /tmp, stale paths are unconditionally removed, peer credentials are not authenticated, and privileged command/power actions are exposed.
4. Disable or replace the legacy unsigned awepkg install path: it extracts untrusted tar archives and copies payload files into / without signature verification or safe path validation.
5. Replace the dummy AOSIN payload/empty-input hash with a versioned, bounded, integrity-checked and signed package format before claiming package-manager readiness.
6. Keep PR #54 and its dependent stack draft until fresh BIOS and UEFI boot checks pass.

### Next run priorities
1. Review the new branch's Userland Validation, Core Data Preservation, and full image/boot workflow results.
2. If the kernel-config verifier fails, inspect the actual final .config and Kconfig dependencies; do not weaken the built-in-driver requirement.
3. If rootfs hand-off still fails, inspect the uploaded BIOS serial log and then run UEFI independently.
4. Once boot is reproducible, address AYUI IPC authorization and the unsigned package-installation path with focused tests.


## 2026-11-16 follow-up — Capture QEMU CPU/reset diagnostics for empty BIOS serial output

### Evidence inspected

- Continued from PR #55 head `e0b0d019984cc3322cfd7781aea684c0255928a2`.
- Inspected failed full-image/boot run #43678056202 and downloaded artifact
  #14146879118 (`aweos-build-and-boot-diagnostics.zip`).
- The artifact contains the completed image-build log and
  `build/qemu-bios.log`; the BIOS serial log is exactly **0 bytes**.
- The image build itself completed: kernel build, rootfs layout validation,
  initramfs creation, hybrid ISO assembly, and post-build `/linux`
  read-only verification passed.
- The BIOS QEMU test then failed because the rootfs init hand-off marker was
  absent. The job log shows the QEMU invocation returned without serial
  output; the existing artifact cannot distinguish a boot-selection issue,
  an early CPU reset/triple fault, or a serial-output initialization problem.
  No kernel panic or rootfs mount failure is confirmed from this evidence.

### Implemented on `fix/qemu-serial-debug-diagnostics-20261116`

- `scripts/run-qemu-tests.sh` now asks QEMU to write a separate emulator
  trace using `-d guest_errors,cpu_reset -D build/qemu-{bios,uefi}-debug.log`. The
  flags remain configurable through `AWEOS_QEMU_DEBUG_FLAGS`, so `int` can
  be enabled for a focused diagnostic run without producing interrupt-level
  traces on every normal boot.
  The flags are configurable through `AWEOS_QEMU_DEBUG_FLAGS`.
- On failure, the runner emits tails from both the guest serial output and
  the QEMU emulator trace. The two channels remain separate so host-side
  diagnostics cannot be mistaken for guest boot output.
- `scripts/test-qemu-boot-readiness.sh` now uses a fake QEMU executable to
  verify that BIOS and UEFI runs receive the expected debug arguments and
  create their separate trace files, while retaining the compositor
  first-frame readiness requirement and mandatory OVMF check.
- `.github/workflows/build-aweos-x86_64.yml` includes both debug traces in
  the failure summary and uploads them as workflow artifacts.
- No kernel source, installer, disk, partition, or user-data behavior was
  changed. No files under `/linux` were modified.

### Regression follow-up

- The first Userland Validation attempts on intermediate heads
  `3f5b456bb6` and `7fff4d4e33` failed in the new fake-QEMU readiness test
  before reaching Rust validation. The fake QEMU fixture now requires an
  argument-log path, but the rootfs-only negative case did not set that
  variable.
- Commit `e633b34354` supplies the missing path for that invocation. The
  latest-head Userland and full-image workflows must confirm the regression
  now passes; the earlier failures are retained as evidence and are not
  reported as passes.

### Validation status

- The source edits and workflow wiring are committed to the isolated
  follow-up branch. Fresh shell/C regression and full image/BIOS/UEFI
  workflows are required; no new CI pass is claimed yet.
- This connector-only run did not execute QEMU locally. The next Actions
  artifact must be inspected to determine whether the emulator trace
  records a CPU reset, exception, boot-device failure, or no guest activity.

### Next priorities

1. Inspect the new PR's Userland Validation and full image/boot results.
2. Download the next BIOS diagnostic artifact and inspect
   `qemu-bios-debug.log` alongside the serial log before changing kernel,
   Limine, or initramfs behavior.
3. If BIOS boots far enough to emit serial output, identify the first
   failing stage and verify `/dev/sr0`, ISO9660, loop, and rootfs image
   discovery rather than weakening readiness markers.
4. Run UEFI independently after the BIOS trace is understood; require the
   compositor first-frame marker for desktop readiness.
5. Keep PR #55 and this dependent PR draft/unmerged until the full boot matrix
   passes on the reconciled head.

## 2026-11-18 (run 2) — Device Identity Manager lands; boot issue stays blocked on CI evidence

### Continue-from inspection
- Resumed after the 2026-11-18 run that opened PRs #59-#63.
- All six open PRs are mergeable (no conflicts) with `mergeable_state: unstable`
  (checks outstanding or failing); no CI check data is retrievable from this
  connector-only environment, so no pass was assumed for any PR and nothing
  was merged, per the no-unverified-merges rule.
- PR #58 (AYUI IPC hardening) remains the only non-draft PR awaiting CI review;
  PRs #59-#63 stay draft. #59 is based on current master and is ready for
  exact-head CI evidence.

### Implemented (PR #64, branch `feat/device-identity-manager-20261118`)
- New Network Platform module 2 (Device Identity Manager) as a
  dependency-free C core:
  - `src/core/netid.c` / `src/core/netid.h`: FIPS 180-4 SHA-256,
    RFC 2104/RFC 4231 HMAC-SHA256, device identity derivation under the
    versioned label `AWEOS-NETID-V1`, bounded challenge/response via
    `aweos_netid_respond`, and constant-time `aweos_netid_mac_equal`.
    No dynamic allocation; fail-closed error codes; no secrets logged.
  - `scripts/test-netid.sh`: regression covering FIPS 180-4 vectors, RFC 4231
    Test Case 1, deterministic derivation, fingerprint format
    (`AWE-XXXXXXXX-XXXXXXXX-XXXXXXXX`), challenge/response accept, and
    rejection of tampered MACs, wrong nonces, foreign identities, oversized
    nonces and NULL parameters.
  - `Makefile`: added to `test-shell`.
  - `docs/NETWORK-IDENTITY.md`: scope, constraints, and non-goals.

### Test results
- In an isolated workspace the new regression compiled with
  `cc -std=c11 -Wall -Wextra -Werror` and passed all assertions.
- No GitHub Actions result is claimed for any PR this run; CI triggers were
  submitted by the branch pushes.
- The BIOS triple fault (PRs #61/#63) is unchanged: diagnosis requires the
  QEMU diagnostics artifact from the next full image workflow run.

### Unresolved issues
1. Boot still fails before the rootfs hand-off marker; the emulator trace from
   the PR #61/#63 diagnostics run must be inspected before kernel/ISO changes.
2. AYUI IPC authorization (PR #58) and awepkg fail-closed merge (PR #60) still
   await exact-head CI evidence.
3. Stacked PRs #56 and #53 remain pinned to older bases until their stacks
   reconcile against master.

### Next run priorities
1. Inspect the latest CI results for PRs #58-#64 and read any new QEMU
   diagnostics artifacts before touching bootloader/kernel behavior.
2. If PR #63's baseline-ISA fix passes the full boot matrix, prepare the
   integration order (#58 non-draft first, then #60, #61, #62, #63, #64).
3. Begin Connection Manager (module 4) handshake on top of the identity
   primitive from PR #64.


## 2026-11-19 — PR #64 strict-build correction and identity boundary review

### CI evidence inspected
- PR #64 Userland Validation run [#44324028340](https://github.com/ARARAT33/AWEOS/actions/runs/44324028340) and full build/boot run [#44324028332](https://github.com/ARARAT33/AWEOS/actions/runs/44324028332) both stopped in `make test-shell`.
- The exact compiler error was GCC `-Werror=unterminated-string-initialization` at `src/core/netid.c:10`: a 14-byte array was initialized from a 15-byte C string literal including its NUL terminator. Rust workspace tests had passed in the full-build job; image creation and QEMU boot were skipped after the shell-test failure. No boot result is inferred from these runs.
- The separate Core Data Preservation workflow passed on the same PR head.

### Changes made on `feat/device-identity-manager-20261118` (PR #64)
- Replaced the fixed-size string initializer with an inferred-size byte array and a compile-time `sizeof(...)-1` domain length. The protocol transcript remains the same 14 bytes, without truncation warnings.
- Strengthened `scripts/test-netid.sh` with known-answer checks for SHA-256 of one million `a` bytes and for a fixed device-secret identity/fingerprint.
- Corrected `netid.h` and `docs/NETWORK-IDENTITY.md` to state the actual trust boundary: HMAC response generation alone is not remotely verifiable from the public device ID. No peer verifier, asymmetric signature, enrollment, or secure secret provisioning exists yet. The module must not be used as remote authentication until those are designed and tested.

### Validation status
- The observed CI failure is understood and the source-level correction is committed to the existing PR branch.
- Fresh Userland Validation and full image/BIOS/UEFI checks on the updated head are pending. This run did not execute a local C build or QEMU; no pass is claimed.

### Additional repository health findings
- Scheduled branch-integration run [#44445897064](https://github.com/ARARAT33/AWEOS/actions/runs/44445897064) reported success, but its logs show repeated `gh pr create` failures because GitHub Actions is not permitted to create pull requests. The workflow currently masks those failures with `|| true`; its green conclusion is not evidence that proposals were created.
- Linux sync run [#44299022285](https://github.com/ARARAT33/AWEOS/actions/runs/44299022285) failed at the Linux-only replacement step with `fatal: path 'linux' exists on disk, but not in the index`. No push occurred; the index/worktree discrepancy needs a separate diagnosis.

### Next run priorities
1. Verify the new PR #64 head with fresh `make test-shell` and Userland Validation.
2. If userland passes, inspect the full build/boot run separately; the previous boot matrix never started.
3. Fix the scheduled branch-integration workflow so disabled PR-creation permissions are reported once and not silently treated as successful proposal creation.
4. Diagnose the Linux sync index/worktree failure without weakening the hard boundary that only `/linux` may change.
5. Design a publicly verifiable device identity and secure provisioning model before adding Connection Manager trust decisions.


## 2026-11-19 follow-up — Correct the fingerprint-format regression boundary

- The first post-fix Userland Validation run [#44460674814](https://github.com/ARARAT33/AWEOS/actions/runs/44460674814) compiled the identity module successfully and reached the new regression.
- It then exposed an existing test assertion bug: the hex-character loop included the literal `AWE-` prefix, so it incorrectly rejected the valid `W` character. The prefix and separator positions already have their own assertions.
- Updated the loop to validate only the 24 hexadecimal payload characters. The known-answer SHA-256 and identity checks remain enabled.
- Fresh CI on the newest branch head is pending. No test pass is claimed from the failed run.
