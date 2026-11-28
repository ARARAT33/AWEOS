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


## 2026-11-18 run — Enforce the x86-64 baseline ISA in the compressed kernel

### Evidence
- Current `master` head: `d4d300545558d660abb2127d297d3a00ef017dae`. Its kernel build target passed the host compiler defaults through Kbuild without an explicit x86-64 baseline, and it had no post-build compressed-kernel ISA scan.
- The current BIOS interrupt trace on PR #61 records the first `#UD` at `RIP=0x3cd63c7`, followed by `#GP` (error code `0x32`), double fault and triple fault.
- The older, still-open stacked PR #44 inspected the same BIOS RIP in its actual QEMU instruction trace and decoded bytes `c4 e2 fb f7 ca` as `SHRX` (BMI2) in `kernel_ident_mapping_init`. Its proposed kernel baseline fix is not present on current `master`; PR #44 is based on an older stacked branch, so this PR carries only the focused kernel-build guard onto current `master`.
- The new current-head `in_asm` trace is still running and will be used to independently confirm the opcode. The old instruction decode is strong evidence, but this change does not claim the new head is fixed until its own build and boot tests pass.

### Changes on `fix/kernel-baseline-isa-20261118`
- Added `AWEOS_KERNEL_CPU_FLAGS` defaulting to `-march=x86-64 -mtune=generic -mno-bmi -mno-bmi2`, passed through Kbuild's `CC` command so compressed boot code cannot inherit a newer host ISA.
- Added `scripts/check-kernel-baseline-isa.sh` to scan the actual `arch/x86/boot/compressed/vmlinux` after each kernel build and fail the image build if BMI1/BMI2 instructions remain.
- Added a fixture-based regression that accepts baseline code and rejects an explicitly encoded SHRX/BMI2 instruction.
- Wired the regression into `make test-shell` and the post-build ISA check into the real `kernel` target.
- No files under `/linux` were changed.

### Validation
- Local fixture regression using the available C compiler and `objdump`: **PASS** (safe object accepted; explicit SHRX/BMI2 object rejected).
- Shell syntax checks for the new checker and test: **PASS**.
- Exact-head GitHub userland, kernel build, compressed-kernel ISA scan, BIOS/UEFI QEMU boot and `/linux` integrity checks are pending on this branch.
- The pre-fix PR #61 full-image run #44239001611 failed both BIOS and UEFI; no successful boot is claimed.

### Next priorities
1. Confirm the filtered current-head QEMU trace identifies the same SHRX instruction at `0x3cd63c7`.
2. Run the post-build checker on the new compressed `vmlinux`; if it finds further BMI1/BMI2 instructions, keep the build fail-closed and correct the remaining compiler/assembly source.
3. Re-run BIOS and UEFI on the exact fixed head and require the rootfs hand-off plus AYUI first-frame markers.
4. If the kernel #UD is removed but a userspace #UD remains at a different address, map that address to its ELF and fix it separately rather than broadening kernel flags blindly.


## 2026-11-18 follow-up — Make the compressed-kernel ISA verifier fail closed

### Evidence
- Downloaded and inspected the PR #61 BIOS diagnostic artifact from run #44241406946. The filtered QEMU instruction trace records bytes `c4 e2 fb f7 ca` at RIP `0x3cd63c7`, decoded as `SHRX` (BMI2), followed by `#UD`, `#GP`, double fault and triple fault. BIOS serial output stops after ACPI RSDP discovery; UEFI also fails before rootfs hand-off.
- Code review found a fail-open edge in the new verifier: if `objdump` failed, the pipeline could be interpreted as an empty grep result and incorrectly print PASS.

### Changes on `fix/kernel-baseline-isa-20261118`
- `scripts/check-kernel-baseline-isa.sh` now captures disassembly first, checks the `objdump` exit status, requires actual disassemblable instruction lines, and distinguishes grep's “no match” result from execution errors.
- `scripts/test-kernel-baseline-isa.sh` now covers three cases: baseline code accepted, explicit SHRX/BMI2 rejected, and malformed non-ELF input rejected before a clean result can be reported.
- No files under `/linux` were changed.

### Validation
- Local regression using the available C compiler and `objdump`: **PASS** for all three cases.
- Shell syntax validation for the checker and test: **PASS**.
- The exact-head full-image workflow for the prior commit `20822b2e7d65` was still running when this follow-up was pushed; it does not validate the follow-up commit. Fresh push/PR workflows for the new head are required.

### Next priorities
1. Inspect fresh exact-head userland and image/boot runs for the follow-up commit; do not reuse the previous head's results.
2. Confirm the post-build scanner reports no BMI1/BMI2 instructions in the real compressed `vmlinux`.
3. Require fresh BIOS and UEFI QEMU boots to reach rootfs hand-off and AYUI compositor first-frame markers; if they still fail, inspect the new trace and map the first faulting instruction.
4. Keep PR #63 draft/unmerged until exact-head CI and the boot matrix pass; preserve the upstream `/linux` tree unchanged.

## 2026-11-20 run 10 follow-up — Make the x86-64 baseline enforceable on reused build directories

### New boot evidence
- Inspected the fresh PR #65 full-image run #44672877358 and downloaded its diagnostic artifact #14600679940. Kernel build, rootfs, hybrid ISO creation, disk-image creation, and the post-build `/linux` read-only integrity check all passed.
- BIOS QEMU still fails before the rootfs hand-off marker. The earlier exact-head PR #61 instruction trace (run #44241413286, artifact #14400546292) contains the bytes `c4 e2 fb f7 ca` at RIP `0x3cd63c7`; local `objdump` decodes them as `shrx rcx,rdx,rax` (BMI2), followed by #UD, #GP, double fault, and triple fault.
- Re-inspected the existing PR #63 kernel-baseline branch instead of duplicating its implementation. Its Makefile recipe had `-j"$(nproc)"` (GNU Make expands this as an undefined Make variable) instead of the required escaped shell substitution `-j"$$(nproc)"`. Its config script also reused an existing `.config` without explicitly disabling `CONFIG_X86_NATIVE_CPU`; the upstream x86 Makefile emits `-march=native` when that option is enabled, which can override the intended baseline flags.

### Changes on the existing PR #63 branch
- `Makefile`: corrected the kernel parallelism recipe to pass `$(nproc)` to the shell rather than expanding an empty GNU Make variable.
- `scripts/config-kernel.sh`: explicitly disables `CONFIG_X86_NATIVE_CPU` every time AWEOS reapplies its required kernel configuration, including when reusing an existing build directory.
- `scripts/test-kernel-config-requirements.sh`: added regression assertions for the native-CPU disable, x86-64 baseline compiler flags, and correctly escaped parallel job-count expression.
- No files under `/linux` were modified; only the build configuration and checks changed.

### Validation status
- The fresh PR #65 Userland Validation run #44672886433 passed. Its shell/C suite includes the AOSIN v2 create/verify/inspect/install/remove regression and CLI verification; the Rust workspace tests and all expected release binaries also passed.
- The fresh PR #65 full image run #44672877358 passed Rust tests, shell/rootfs regressions, kernel build, rootfs/initramfs creation, ISO and disk-image creation, and the `/linux` integrity check, but failed the BIOS QEMU rootfs hand-off test with a triple fault. The UEFI step was not reached in this failed push run.
- The PR #63 branch correction is not yet validated by a fresh exact-head build/boot run. No successful BIOS or UEFI boot is claimed.

### Next priorities
1. Run the exact PR #63 head through the full image build and verify the compressed-kernel BMI1/BMI2 scan passes on the actual `vmlinux`.
2. Re-run the qemu64 BIOS and UEFI tests and inspect both results independently; retain the rootfs hand-off and AYUI first-frame requirements.
3. Reconcile PR #63 with PR #65 only after the exact-head ISA scan and QEMU results are known. Do not merge an unverified stacked branch.
4. Continue the AOSIN uninstall-scope and metadata-atomicity review as a separate security task.

## 2026-11-20 run 10 correction — Preserve Make's escaped job-count expression and script mode

- Read-back of the first PR #63 correction found that the GitHub blob contained a single `$` in `-j"$(nproc)"`, because the replacement-string API interpreted `$$` as a literal single dollar. The earlier entry therefore overstated that this recipe had been corrected.
- Rebuilt the replacement using a literal callback so the committed Makefile now contains the required `-j"$$(nproc)"` text. The regression assertion was updated to check the exact two-dollar form.
- Restored `scripts/config-kernel.sh` to its original executable Git mode `100755` and added a test that fails if this direct-invocation script loses that mode again.
- The previous exact-head image run #44674438775 stopped before kernel compilation because the script mode had been lost; it did not validate the baseline flags or compressed-kernel scan.
- Fresh exact-head CI is required. No kernel build, ISA scan on a real image, or boot success is claimed for that failed run.

## 2026-11-20 run 10 follow-up — Capture the first userspace invalid-opcode instruction

### Evidence
- The exact PR #63 head 7a2aa278080dfbab73c65844dc3197b0aae855db completed the full kernel build, rootfs creation, ISO/disk-image creation, and /linux integrity check in run #44674841664.
- The compressed-kernel build target completed, including its real-vmlinux BMI1/BMI2 scan. Boot progressed beyond the earlier kernel triple fault and reached PID 1.
- BIOS still fails: the kernel reports SIGILL (exitcode 0x00000004) for PID 1 at user-mode RIP 0x56df50. The faulting bytes include c5 f9 6f, a VEX-encoded instruction outside the qemu64 x86-64 baseline. This is a new userspace fault, not evidence that the kernel BMI2 issue remains.
- The current logs do not yet identify which ELF contains the faulting instruction. Do not broaden kernel compiler flags or change the QEMU CPU model to hide this userspace incompatibility.

### Changes on fix/qemu-userland-isa-diagnostics-20261120
- Added scripts/trace-qemu-user-isa-fault.sh. When a serial log contains a user-mode RIP, it re-runs the same QEMU command with a 512-byte address window and int,in_asm tracing.
- Updated scripts/run-qemu-tests.sh to invoke the targeted trace only after a userspace RIP is observed.
- Updated the x86_64 workflow to include the targeted trace in the job summary and diagnostic artifact.
- Added scripts/test-qemu-user-isa-trace.sh and wired it into make test-shell. The regression checks the exact address filter and verifies that no QEMU invocation occurs without a user-mode RIP.
- No files under /linux were changed.

### Validation status
- GitHub read-back confirms the helper, runner integration, workflow artifact paths, and regression are present.
- Exact-head shell regression and full BIOS/UEFI diagnostic runs are pending. No userspace fix or successful boot is claimed.

### Next priorities
1. Run the targeted trace on BIOS and map the VEX instruction to its ELF using the actual build artifacts.
2. If the fault is in BusyBox or a library, replace/rebuild that component for the x86-64 baseline rather than relaxing QEMU's CPU features.
3. Re-run BIOS and UEFI and require the rootfs hand-off plus AYUI first-frame markers.
4. Keep PR #63 and this diagnostic follow-up draft/unmerged until the exact-head boot matrix passes.


## 2026-11-20 run 10 follow-up — Rebuild early userspace BusyBox for the x86-64 baseline

### Evidence
- PR #67 exact-head full image run #44676952897 passed Rust tests, shell/rootfs regressions, kernel build, compressed-kernel BMI1/BMI2 scan, rootfs/initramfs creation, ISO and disk-image creation, and the post-build `/linux` integrity check. BIOS boot still failed with PID 1 SIGILL at RIP `0x56df50`; UEFI was not reached because BIOS failed first.
- The kernel serial log records the fault bytes `c5 f9 6f`; the targeted QEMU `in_asm` trace decodes the instruction at `0x56df50` as `vmovdqa`, a VEX/AVX instruction unavailable on the required `qemu64` baseline.
- Source inspection shows that the AYUI rootfs copies the host `busybox` binary from PATH, creates `/bin/sh` as a BusyBox applet symlink, and runs `/sbin/init` as a shell script. The initramfs independently copies the same host BusyBox. This makes a host-built BusyBox the leading, testable source of the userspace ISA mismatch; the exact ELF symbol is not yet proven.

### Changes on `fix/busybox-x86-64-baseline-20261120`
- Added a pinned BusyBox 1.38.0 source build using static musl and explicit `-march=x86-64 -mtune=generic` flags with AVX/BMI disabled. The source archive is SHA-256 verified before extraction.
- The same built binary is now passed explicitly to both persistent-rootfs and initramfs builders; they no longer silently copy the CI host's BusyBox.
- Added a targeted ELF instruction scanner and regression fixtures that accept baseline code and reject AVX, BMI and invalid ELF inputs.
- Added the same checked BusyBox to the GNOME rootfs so the shared rootfs validator has consistent boot tooling.
- Added the BusyBox build to the Makefile and CI release checksum/artifact list. Fixed the Makefile's desktop selection assignment so the shell default is expanded by Bash rather than interpreted as a Make variable.
- No files under `/linux` were changed.

### Validation status
- Local targeted ISA-scanner regression: **PASS** (baseline ELF accepted; AVX, BMI and invalid ELF fixtures rejected).
- Local shell syntax checks for the new build/check/test scripts: **PASS**.
- The source archive could not be downloaded in this development container, so the full BusyBox compile was not run locally.
- Upstream currently labels BusyBox 1.38.0 as an unstable release; this version is pinned for reproducible testing, not presented as a stable-release claim.
- Exact-head Userland Validation run #44680050497: **PASS**. It completed shell/C transaction tests (including the rootfs validator and new ISA scanner), repository-boundary validation, Cargo metadata, Rust workspace tests, and all expected Rust binary builds.
- Exact-head image run #44680050408 was still running at this log update. No successful BIOS or UEFI boot is claimed.

### Next priorities
1. Run exact-head CI and confirm the pinned BusyBox build is static and passes the AVX/BMI scanner.
2. Re-run BIOS and UEFI; require rootfs hand-off and the AYUI compositor first-frame marker in both modes.
3. If SIGILL persists, use the retained BusyBox ELF and QEMU trace to map the new RIP to a symbol and correct that component without enabling non-baseline CPU features.
4. Keep this PR and its boot-diagnostic parent draft/unmerged until the exact-head build and boot matrix pass.


### Additional repository architecture findings
- The current image build is a Linux-kernel/Limine boot path with a Rust `AWEUI` workspace and Rust system applications under `APPS/`. The older C implementations under `src/core`, `src/aosin`, `src/gui`, `src/installer`, `src/updater`, and `src/wlin` are not members of the current root `Cargo.toml` workspace and are not built by the current `make image` path; their integration must be verified separately rather than inferred from their presence.
- The repository contains additional EFI binaries for ARM64, RISC-V64, LoongArch64 and IA32, but the current Makefile, kernel configuration and QEMU CI exercise x86_64 only. Those other architecture binaries are not evidence of a working AWEOS port.
- No dedicated distributed Network Platform service tree was found in the current module layout. The Linux networking stack exists, but AWEOS device identity, service discovery, peer authentication and distributed resource orchestration remain future implementation work.


## 2026-11-20 run 11 fix — Supply kernel headers so the pinned BusyBox build compiles

### Evidence
- Exact-head PR #68 full image run #44680612284 (job #136102828774) failed during the BusyBox source build, not during boot:
  - `console-tools/kbd_mode.c:32:10: fatal error: linux/kd.h: No such file or directory`
  - `make[2]: *** [scripts/Makefile.build:197: console-tools/kbd_mode.o] Error 1`
  - `make: *** [Makefile:46: busybox] Error 2`
- The PR #68 Userland Validation run #44680612390 passed; this is a build-configuration failure only.
- Root cause: the pinned BusyBox is compiled statically with musl-gcc, and neither musl nor the CI host's libc development headers are guaranteed to provide `linux/kd.h`, which is a kernel-headers file.

### Changes on this branch
- `scripts/build-busybox-baseline.sh`: generate x86_64 kernel headers out-of-tree with `make O=build/linux-headers ARCH=x86_64 headers_install` from the read-only `/linux` source (overridable with `AWEOS_LINUX_SRC`), fail closed if `linux/kd.h` is still absent, and prepend that directory to `CONFIG_EXTRA_CFLAGS` so kbd_mode and siblings compile against the real kernel headers. `/linux` itself is never written.

### Validation status
- The exact-head Userland Validation run #44680612390 passed for the pre-fix head; the new fix has fresh exact-head Userland and full image/boot workflows pending on the updated head. No build or boot success is claimed for the fix commit yet.

### Next priorities
1. Confirm the fixed BusyBox build completes, the static binary passes the AVX/BMI ISA scanner, and image assembly succeeds.
2. Re-run BIOS and UEFI; require the rootfs hand-off marker plus the AYUI compositor first-frame marker in both modes.
3. If a userspace invalid-opcode fault remains, map the new RIP to its ELF with the retained trace and fix that component for the x86-64 baseline.
4. Keep this PR and its boot-diagnostic parent draft/unmerged until the exact-head build and boot matrix pass.



## 2026-11-21 follow-up - Correct BusyBox kernel-header path and test compiler configuration

### Latest CI evidence
- PR #68 head `4d8d6d78f0bf37f32ae87f486766f9ccde2b6c8d` was checked directly.
- Userland Validation run #44757503344: **PASS**. Shell/C regressions, repository-boundary validation, Cargo metadata, Rust workspace tests, release builds, and expected binary checks all completed successfully.
- Full image run #44757503330: **FAIL** at `Build AWEOS images`; the kernel and BusyBox image build did not reach boot testing.
- Exact failure: `ERROR: kernel source tree not found at /linux; cannot generate linux-headers`. BIOS and UEFI steps were skipped. The `/linux` integrity check before the image build passed.
- The repository Makefile already defines `KERNEL_SRC := $(PWD)/linux`. GitHub Actions checks the repository out beneath the runner workspace, so `/linux` (the filesystem-root path) is not the checked-out kernel directory.

### Changes on `fix/busybox-x86-64-baseline-20261120`
- `scripts/build-busybox-baseline.sh`: resolve the default kernel source as `../linux` relative to the script/repository root, validate that its `Makefile` exists, and canonicalize the path. `AWEOS_LINUX_SRC` remains an explicit override.
- Corrected `CONFIG_EXTRA_CFLAGS` so the absolute out-of-tree kernel-header include path is expanded by the shell instead of being written literally as `${KERNEL_HEADERS_ABS}` into BusyBox `.config`.
- Added `scripts/test-busybox-build-config.sh`: a network-free fake-tool integration test that exercises default source-path resolution, out-of-tree header generation, expanded include flags, static ELF output, and the x86-64 baseline scanner.
- Wired the new regression into `make test-shell`.
- No files under `linux/` were modified; generated headers remain under the selected build directory.

### Validation
- Local isolated integration harness: **PASS**. It simulated `headers_install`, BusyBox configuration/build, and a static x86-64 ELF; verified the source path resolves to the repository's `linux/` directory and the compiler include path is expanded.
- Exact-head GitHub CI for this new commit has not run yet. The previous head's Userland Validation passed, but the image build failed at the absolute `/linux` path. No ISO, BIOS, UEFI, or desktop boot success is claimed for this follow-up.

### Next priorities
1. Confirm the new regression passes in Userland Validation.
2. Confirm BusyBox's real `headers_install` stage and static musl build complete in the full image workflow.
3. Require the BusyBox ISA scan, rootfs/ISO/disk image checks, and `/linux` integrity checks to pass.
4. Only then run BIOS and UEFI QEMU tests and require rootfs hand-off plus AYUI first-frame readiness in both modes.
5. If the next build fails, use the exact job log and diagnostic artifact; do not relax the x86-64 baseline or boot markers.


### Regression-harness correction and exact-head CI follow-up
- The first harness commit `efbe6c4306fb6ecb881393356c0c54309715c039` exposed a malformed glob in the new fake-Make assertion. Userland run #44868652889 failed at `make test-shell` in that test fixture; the reported flags did contain the expected expanded include path, so this was a test assertion defect rather than a BusyBox compile failure.
- Corrected the pattern in commit `ff7b5026f598ea50984d61d7b5861472467820a7` and reran the workflows on that head.
- Userland run #44868716919: the shell/C transaction and regression step **PASS**, repository-boundary validation **PASS**, and Cargo metadata validation **PASS**. Rust workspace tests were still running at the last inspection; the workflow had not reached its final release-binary checks.
- Full image run #44868716935: dependency installation and Limine host utility setup completed; the Rust workspace test step was running. The BusyBox source build, image assembly, BIOS/UEFI tests and release artifact checks had not yet run at the last inspection.
- No full image, ISO, BIOS, UEFI, or desktop boot success is claimed from these in-progress runs.

## 2026-11-21 run — BusyBox tc applet fix on PR #68

### CI evidence inspected
- PR #68 latest exact-head build-and-boot run #44868882500 (job #136738673754) **failed** with exit code 2, while its Userland Validation run passed.
- The failure annotations were: `make[2]: *** [scripts/Makefile.build:197: networking/tc.o] Error 1`, `make[1]: *** [Makefile:749: networking] Error 2`, `make: *** [Makefile:46: busybox] Error 2`. The pinned BusyBox 1.38.0 build broke on the `tc` traffic-control applet, before kernel, rootfs, ISO, or QEMU stages.
- Root cause: busybox `tc` depends on the CBQ qdisc ABI (TCA_CBQ_*) that modern kernels removed, so it does not compile against the freshly installed UAPI headers with musl. The applet is not needed for boot or early userspace.

### Changes on `fix/busybox-x86-64-baseline-20261120` (PR #68)
- `scripts/build-busybox-baseline.sh`: explicitly `set_config CONFIG_TC n` with an inline root-cause comment; defconfig defaults had left the failing applet enabled.
- `scripts/test-busybox-tc-disabled.sh` (new): structural regression that fails unless CONFIG_TC is explicitly disabled and the root cause is documented, so a future defconfig refresh cannot silently re-enable it.
- `Makefile`: wire `test-busybox-tc-disabled.sh` into `make test-shell`.
- No files under `/linux` were touched; no kernel, rootfs, installer, or userland runtime behavior changed beyond the BusyBox applet set.

### Validation status
- The tc-disable guard was verified dynamically: the decoded builder contains the exact working `grep -q "^\${key}="` / `sed -i "s|^\${key}=.*|..." ` config lines plus `set_config CONFIG_TC n`.
- New CI runs on the updated head are pending; no build, boot, BIOS, UEFI, or desktop success is claimed. (Note: the immediately preceding intermediate commit on this branch was a push with mangled placeholder content and had to be immediately repaired; its evidence is retained in history.)

### Remaining issues
1. Watch the next `build-and-boot-test` run; if a different applet or object fails next, fix only the proven failure with evidence.
2. BIOS/UEFI boot matrix, AYUI compositor readiness, UEFI firmware checks, and release-artifact validation remain unproven.
3. Do not merge PR #68 (or its parent stack #67/#63) until the full matrix passes on one reconciled head.

### Next run priorities
1. Read the new run's exact failure (if any) from annotations/diagnostics and continue the cycle.
2. After a passing image build, verify BIOS boot first, then UEFI independently; keep strict compositor-readiness markers.
3. Continue the recorded security backlog: signed package payload, sandboxing and privilege boundaries.


## 2026-11-22 run 11 — Restore corrupted BusyBox build-configuration regression

### Repository and CI evidence
- The default branch remains `master` at `d4d300545558d660abb2127d297d3a00ef017dae`; this work continues on the existing PR #68 branch `fix/busybox-x86-64-baseline-20261120`, stacked on PR #67 and the earlier x86-64 kernel baseline work. No default-branch merge was performed.
- Exact-head PR workflows for `50e7889380dc85cc54676feb0701cf69e464955a` failed before any image build:
  - Userland Validation run #44913056890 failed in `make test-shell`.
  - Full image/boot run #44913056888 failed at its shell/rootfs regression step, before image assembly.
- Both logs identify the same failure: `scripts/test-busybox-build-config.sh: line 1: ÿôÄÿÿÿ: command not found` (exit 127). The file had been overwritten with a 7-byte non-shell payload, so the previously added network-free BusyBox build regression could not execute. Kernel build, BusyBox compilation, ISO creation, BIOS, and UEFI were not reached by these runs.

### Fix on the existing PR #68 branch
- Restored `scripts/test-busybox-build-config.sh` from its previously validated version. The final blob SHA is `0b30b5edcb411ecbcb7368ea16cc7309048c69bc`, identical to the known-good version already present earlier in this branch history.
- The restored test again exercises repository-relative kernel source discovery, out-of-tree headers installation, expanded `CONFIG_EXTRA_CFLAGS`, static ELF output, and the baseline ISA checker using fake build tools without network access.
- The first restoration write contained escaping errors; it was corrected immediately in the next commit. The final branch head is `6c32f054d932d9f52992d4e04da49fbd1c885d59` and the file was read back from GitHub to verify its exact blob SHA.
- No files under `linux/` were changed. No force push, branch deletion, or merge was performed.

### Exact-head validation
- New workflow runs for head `6c32f054d932d9f52992d4e04da49fbd1c885d59` were observed:
  - Userland Validation PR run #44987358465: **in progress**.
  - Full image/boot PR run #44987358525: **in progress**.
  - Corresponding push-triggered runs #44987354904 and #44987354867: **in progress**.
- These are pending, not passes. No new shell-test, BusyBox compilation, ISO, BIOS, UEFI, or AYUI readiness success is claimed in this log entry.

### Remaining issues and next priorities
1. Inspect the exact-head shell/C regression result; confirm the restored build-config test and tc-disable guard both pass.
2. Confirm real kernel `headers_install` and pinned BusyBox 1.38.0 static musl compilation complete; then require the ELF baseline scanner to pass.
3. Confirm kernel, rootfs, initramfs, ISO, disk image, and post-build `linux/` integrity checks complete.
4. Run BIOS and UEFI independently and require rootfs hand-off plus AYUI first-frame readiness; do not treat an image build as a boot pass.
5. If a new BusyBox object fails, use the actual compiler diagnostic and disable/fix only the proven incompatible applet; do not weaken the x86-64 baseline.
6. After boot is unblocked, return to the documented security backlog: signed package trust, application isolation, and AYUI session privilege boundaries.


### Run 11 validation update — 2026-11-22
- Exact code head `6c32f054d932d9f52992d4e04da49fbd1c885d59` passed Userland Validation:
  - PR run #44987358465: **success**.
  - Push run #44987354904: **success**.
  - Confirmed passing steps: shell/C safety regressions (including the restored BusyBox build-config harness and `CONFIG_TC=n` guard), repository-boundary validation, Cargo metadata, Rust workspace tests, all Rust release binaries, and expected-binary verification.
- Full image runs #44987358525 (PR) and #44987354867 (push) passed Rust tests and shell/rootfs regression tests, and were still in `Build AWEOS images` at the last poll. Kernel/BusyBox image build, ISO/disk image, BIOS, UEFI, and compositor readiness are therefore still **pending**; no boot success is claimed.
- The push and pull-request triggers ran duplicate copies of each workflow for the same commit. This is an efficiency issue to review separately; neither run was cancelled.
- Separate default-branch workflow observation: Safe branch integration run #44966568387 completed **success** on `master`. Linux upstream sync run #44898847608 failed at `Update ONLY /linux` with `fatal: path 'linux' exists on disk, but not in the index`; the pre-update clean check and tree comparison passed, while the post-update boundary and push steps were skipped. No kernel sync commit was pushed. The leftover path must be diagnosed before adding any cleanup that could delete ignored data.
- AYUI IPC hardening PR #58 remains open and non-draft; its Userland Validation run #44237900509 passed, but its image/boot run #44237900437 failed at the BIOS/UEFI boot-test step. It remains unmerged and is not treated as a verified production security boundary.


## 2026-11-23 run 11 — Enforce BusyBox compiler ISA floor at the driver boundary

### Exact-head CI evidence
- PR #69 head e6ace26d9e3e87098b7f8df40750b2af6d3acb85 passed Userland Validation run #45036957032, but the full image run #45036957026 failed during make image at the BusyBox baseline ISA check.
- The kernel build and out-of-tree header installation completed. BusyBox 1.38.0 compiled and linked, but the produced static ELF contained VEX/AVX instructions (vpxor, vmovdqu, vpinsrq, vpsubq) and BMI2 instructions (shrx, shlx). ISO assembly and BIOS/UEFI boot tests were not reached.
- The CI Kconfig transcript confirms that CONFIG_EXTRA_CFLAGS contained the requested -march=x86-64, -mno-avx, and -mno-bmi2 options. That proves the values reached BusyBox configuration, but does not by itself prove every compiler invocation received them.

### Changes on fix/busybox-static-link-config-20261122 (PR #69)
- scripts/build-busybox-baseline.sh: centralize the x86-64 baseline compiler flags and pass them through both CONFIG_EXTRA_CFLAGS and the CC command supplied to GNU make. This is a defensive enforcement at the compiler-driver boundary; it does not weaken or bypass the post-build ELF scanner.
- scripts/test-busybox-build-config.sh: capture the fake make invocation's CC= value and assert that the direct compiler command includes -march=x86-64, -mno-avx, and -mno-bmi2, and excludes -march=native.
- .github/workflows/build-aweos-x86_64.yml: include the built build/busybox ELF in the always-uploaded diagnostic artifact so a future scanner failure can be inspected rather than inferred from text output.
- docs/AI-DEVELOPMENT-LOG.md: record this run's evidence and the next diagnostic branch.
- No files under linux/ were changed. No existing branch or commit was rewritten; no merge or force push was performed.

### Validation status
- The source-level test harness was updated to verify compiler-command propagation. Its actual CI result is pending for this new head.
- No claim is made that the real BusyBox ELF now passes the baseline scanner. The previous exact-head full-image run failed at that scanner, and this change must be confirmed by a new full-image run.
- If the scanner still rejects the ELF, download and inspect the retained BusyBox artifact, map the first offending addresses to symbols, and distinguish BusyBox objects from statically linked musl/libgcc objects before changing the toolchain.

### Next priorities
1. Confirm Userland Validation passes with the new compiler-command regression.
2. Confirm the real BusyBox binary passes the x86-64 baseline scanner without relaxing its instruction list.
3. If it still fails, inspect the retained ELF and compiler/toolchain metadata; isolate the static runtime from BusyBox objects with a separately compiled static probe.
4. Continue kernel/rootfs/ISO/disk-image checks only after BusyBox passes.
5. Run BIOS and UEFI independently and require the rootfs hand-off and AYUI first-frame markers in both modes.

### Current-head validation update — 2026-11-23
- Current PR #69 head at the time of validation: 2d37939ee391eb45d650637615a43371a29cd442.
- Userland Validation run #45111620971: **PASS**. The shell/C safety step passed, including the updated BusyBox compiler-command propagation regression; repository-boundary validation, Cargo metadata, Rust workspace tests, all release userland binaries, and expected-binary checks also passed.
- Full image/boot run #45111621008: **IN PROGRESS** at the Build AWEOS images step. Kernel/BusyBox build, ISO, disk image, BIOS boot, UEFI boot, and AYUI first-frame results are not yet available. No image or boot success is claimed.
- The PR remains draft and unmerged. The default branch remains unchanged.

### Documentation audit finding
- README.md still describes the older C desktop/package modules under src/gui and src/aosin as if they are the active build path, and lists make targets such as make ayui, make aosin, make installer, make updater, and make wlin that are not present in the current root Makefile. The active Cargo workspace builds the Rust AWEUI and APPS workspace. Reconcile the README with the actual build graph after the current boot blocker is resolved; do not present unbuilt C modules as shipped functionality.

### Next priorities
1. Finish the exact-head BusyBox ELF baseline scan and full image build.
2. If the scan fails, inspect the uploaded BusyBox ELF and map offending instructions to symbols before changing compiler/runtime components.
3. Complete BIOS and UEFI boot validation, requiring both rootfs hand-off and AYUI first-frame markers.
4. Correct the README/build-graph mismatch and document which legacy C modules are archived, experimental, or scheduled for integration.

## 2026-11-23 run 13 — Rebuild musl from source for the x86-64 baseline

### Exact-head CI evidence
- PR #69 head 242cb74469bc4aa992fded04bbada59fedcdf6dc passed Userland Validation run #45111620971, but the full image run #45112312153 (job #137487197842) failed again at the BusyBox baseline scan.
- The run-page annotations show VEX/AVX instructions inside the final static ELF: vpsubq, vpextrq, vmovq, vmovdqa, and vpaddq clustered at 0x430021..0x430143, immediately before 'make: *** [Makefile:46: busybox] Error 1'.
- The baseline flags are already verified to reach both CONFIG_EXTRA_CFLAGS and the direct CC command. They govern only code compiled from source in this build. The remaining explanation for VEX instructions at those addresses is statically linked runtime code from the distribution's prebuilt musl libc.a, which inherits the packaging host's optimization target and cannot be fixed by compiler flags.
- ISO assembly and BIOS/UEFI boot tests were not reached. No boot result is claimed for this head.

### Changes on fix/busybox-static-link-config-20261122 (PR #69)
- scripts/build-musl-baseline.sh (new): builds pinned musl 1.2.5 (SHA-256 verified, including caller-supplied archives via AWEOS_MUSL_ARCHIVE) from source with the x86-64 baseline flags into build/musl, static-only; verifies a representative static smoke program with the baseline checker and then scans every archive object in build/musl/lib fail-closed before stamping baseline-verified.
- scripts/build-busybox-baseline.sh: the default compiler is now this baseline-verified musl wrapper (build/musl/bin/musl-gcc) instead of the distribution musl-gcc; AWEOS_BUSYBOX_CC remains an explicit override used by the fake-tool regression tests.
- scripts/check-x86-64-baseline-isa.sh: offending-instruction errors now name the nearest disassembly symbol, so the next failure can identify its ELF component directly from run-page annotations.
- scripts/test-x86-64-baseline-isa.sh: requires the symbol attribution in diagnostic output.
- scripts/test-musl-baseline-build.sh (new) and Makefile wiring: network-free regression proving the archive checksum gate fails closed and installs nothing from a rejected archive, and that the BusyBox builder is wired to the baseline musl builder.
- No files under linux/ were changed. No branch, commit, or workflow trigger was rewritten.

### Validation status
- Patch targets were checked against the live blobs before the push; the pushed commit is being read back from GitHub to confirm content. No local musl or BusyBox compile, image build, ISO, BIOS, UEFI, or AYUI boot was executed in this connector-only environment. No build or boot success is claimed yet.

### Next run priorities
1. Confirm Userland Validation passes with the new symbol-attribution assertion and musl-builder regression.
2. Confirm the full image run compiles baseline musl 1.2.5, passes the per-object archive scan, links a baseline-clean static BusyBox, and completes ISO/disk-image assembly.
3. Then run BIOS and UEFI independently, requiring the rootfs hand-off and AYUI compositor first-frame markers in both modes.
4. If the scan still fails, use the new symbol attribution plus the retained BusyBox ELF artifact to identify the remaining object before changing anything else.


## 2026-11-24 run 11 — Isolate BusyBox regression harness from the musl source build

### Exact-head CI diagnosis
- Inspected PR #69's actual head `8926b693983c5d5f10a5ee7b91ec0e34363b3b20` and its exact-head workflow runs:
  - Userland Validation run #45192271093: **FAIL** in `make test-shell`.
  - Full image/boot run #45192270872: **FAIL** in the shell/rootfs regression step, before `Build AWEOS images`.
- Both workflows failed at the same deterministic line:
  `bash: /tmp/aweos-busybox-config-test.*/repo/scripts/build-musl-baseline.sh: No such file or directory` (exit 127).
- Root cause: `scripts/test-busybox-build-config.sh` creates a minimal fake repository and copies `build-busybox-baseline.sh` plus the ISA checker into it, but it did not copy the newly introduced `build-musl-baseline.sh`. The production BusyBox builder now invokes that script by default, so the isolated fake-tool test accidentally crossed into the real musl-build path and failed before its intended assertions.
- The logs show the Rust workspace tests passed in the full image workflow before the shell regression failed. ISO/image assembly and BIOS/UEFI tests were skipped; no build or boot success is claimed.

### Fix committed on the existing PR #69 branch
- `scripts/test-busybox-build-config.sh`: pass the already-provided fake compiler as `AWEOS_BUSYBOX_CC=${FAKE_BIN}/musl-gcc` to both positive and negative harness invocations.
- This uses the builder's explicit test override, keeping the fixture isolated and network-free. The harness continues to verify Kconfig rewriting, direct compiler ISA flags, static-link acceptance, and rejection of a dynamic ELF.
- The separate `scripts/test-musl-baseline-build.sh` remains responsible for checking that the production builder invokes the pinned musl build and rejects a malformed/checksum-invalid archive. No production build behavior or ISA guard was weakened.
- New commit: `e0b86d66db9cfaeecc01a3f7f00d9f606ed1b0e8` — `test: isolate BusyBox harness from baseline musl build`.
- No files under `linux/` were changed. No force push, branch deletion, or merge was performed.

### Validation status
- The new harness change has been committed and read back from GitHub. It has **not yet** been validated by a fresh Actions run at the time of this entry.
- No local execution was possible in this connector-only environment. The next exact-head Userland Validation run must prove the regression suite passes; only then can the full image job reach the real pinned musl and BusyBox builds.

### Next priorities
1. Inspect the fresh exact-head CI runs for commit `e0b86d66db9cfaeecc01a3f7f00d9f606ed1b0e8`.
2. Confirm `make test-shell` passes, including both the isolated BusyBox builder test and the separate musl checksum/wiring regression.
3. If userland passes, inspect the real musl 1.2.5 build, archive-object ISA scan, static BusyBox ELF scan, kernel/rootfs/ISO/disk-image assembly.
4. Run BIOS and UEFI independently only after image assembly; require rootfs hand-off and AYUI first-frame readiness in both modes.
5. Keep PR #69 draft and unmerged until the full exact-head validation matrix passes.


## 2026-11-25 run 11 — Fix musl archive-member ISA verification

### Exact-head CI diagnosis
- Rechecked PR #69 at head `f0e470a1046171735b6b3e7083be3adbda400ec8`.
- Userland Validation run #45330148966 completed **success**.
- Full image/boot run #45330149099 completed **failure** in `Build AWEOS images`, before BusyBox, ISO, disk-image, BIOS, or UEFI validation could finish.
- The exact failure was in `scripts/build-musl-baseline.sh`: after `ar x`, the scanner iterated only `${OBJ_DIR}/*.o`. No extracted archive member matched that suffix, so Bash passed the literal wildcard path to the ELF checker. The checker then reported that the literal path was not an ELF. The archive scan therefore failed before the actual member ISA compatibility could be determined. The previous PASS status for Userland Validation did not imply the image pipeline passed.
- The same CI inspection found the independent Linux sync workflow #45408594481 failed at `Update ONLY /linux` with `fatal: path 'linux' exists on disk, but not in the index`. No kernel sync was committed or pushed. This remains a separate unresolved workflow issue; no cleanup of the kernel tree was attempted.

### Changes on `fix/musl-archive-member-scan-20261125`, stacked on PR #69
- Added `scripts/check-x86-64-baseline-archive.sh`: enumerate archive members with `ar t`, reject empty archives and duplicate names, extract each member by its archive name, and run the existing strict x86-64 ELF/ISA checker on every member. The scanner no longer assumes that archive objects end in `.o`.
- Updated `scripts/build-musl-baseline.sh` to use the new archive scanner for every static archive and to fail if no archives are found.
- Versioned the musl verification stamp as `archive-member-scan-v2`; a cache stamped by the old suffix-dependent scanner is not accepted as verified.
- Added `scripts/test-x86-64-baseline-archive.sh` and wired it into `make test-shell`. The regression uses a `.lo` archive member, confirms baseline code passes, confirms AVX code is rejected with the offending member named, rejects non-ELF members, and rejects empty archives.
- No files under `linux/` are modified. No force push, branch deletion, merge, or kernel-tree cleanup was performed.

### Validation status
- Changes have been prepared on a new branch based on the exact PR #69 head. The isolated archive-scanner positive/negative fixtures were also executed in the local Linux tool environment: baseline `.lo` accepted, AVX `.lo` rejected with member attribution, non-ELF member rejected, and empty archive rejected. The complete `make test-shell` suite and real musl 1.2.5 build are still being verified by exact-head GitHub Actions; no full OS image or boot is claimed.
- The next Userland Validation run must pass the new archive regression. The full image workflow must then build pinned musl, scan every archive member, build and scan static BusyBox, and proceed to image assembly.
- BIOS/UEFI boot and AYUI first-frame results remain unverified.

### Next priorities
1. Confirm the archive regression passes on the new branch.
2. Confirm real musl 1.2.5 archive members are all scanned and baseline-safe; inspect the first named offending member if the checker rejects one.
3. Confirm BusyBox is statically linked and passes the existing x86-64 ISA guard.
4. Complete kernel, rootfs, initramfs, ISO, and disk-image construction.
5. Run BIOS and UEFI separately and require rootfs hand-off and AYUI first-frame readiness.
6. Diagnose the Linux sync index/worktree mismatch in a separate change, preserving the strict `/linux` boundary.


### Architecture audit — AYUI backend and active product surface
- The active Rust AYUI compositor currently enables Smithay's `backend_winit` feature and calls `winit::init::<GlesRenderer>()` in `AWEUI/src/wayland.rs`. The QEMU readiness marker also explicitly identifies `backend=winit`. The current `AWEUI/src/renderer.rs` `DrmKms` enum is only a mode label/counter and is not a DRM/KMS backend. Therefore, even a successful Winit first-frame marker would not prove a standalone direct-display compositor suitable for a bare-metal session. A real DRM/KMS + udev/input backend remains a required product milestone.
- The minimal rootfs still creates `/run/user/0` and starts `aweui` from PID 1 as UID 0. PR #58 contains IPC hardening but remains open/unmerged; private socket permissions do not replace the missing unprivileged desktop-session split.
- The root `Makefile` builds the Rust Cargo workspace for AYUI and bundled apps. The legacy C modules under `src/gui`, `src/aosin`, `src/installer`, `src/updater`, and `src/wlin` are not part of the current Makefile build graph. In particular, the default-branch C `src/aosin/aosin_core.c` writes a fixed dummy payload and only registers metadata; it is not a production payload package manager. The real AOSIN v2 work is still in open PRs #65/#66 and must not be described as shipped until integrated and validated.
- These are scope/architecture findings, not failures introduced by the archive-scanner patch. They are recorded to keep future progress reports from overstating desktop, package, or hardware readiness.

### Follow-on priorities from architecture audit
1. Complete the x86-64 image and BIOS/UEFI boot pipeline without weakening the rootfs or AYUI first-frame checks.
2. Implement a genuine Smithay DRM/KMS backend with udev device discovery, input, VT/session handling, and a QEMU/real-hardware test path; keep Winit as a development backend only.
3. Move AYUI and ordinary applications to an unprivileged user session; put narrowly scoped privileged operations behind a separate broker.
4. Reconcile README claims with the actual Cargo/Makefile build graph and clearly label legacy C modules as inactive/experimental.
5. Integrate and test AOSIN v2, package signatures, dependency validation, and safe rollback before claiming a production package ecosystem.


## 2026-11-26 run 11 — Scan duplicate musl archive members by occurrence

### Exact-head CI diagnosis
- Inspected PR #70 at head `960b9308aebcfef0b38885d5f30e7f6c99cbea93` and downloaded its retained image-build diagnostic artifact from run #45545991763.
- Userland Validation passed on the PR head, but the full x86_64 image/boot workflow failed in `Build AWEOS images` while scanning the freshly built musl `libc.a`.
- The exact failure named duplicate archive members `clone.lo`, `free.lo`, and `realloc.lo`. These duplicate basenames are valid in static archives when objects originate from different source directories. The previous scanner rejected duplicates because plain `ar p` cannot select a particular occurrence. Simply ignoring duplicates would be unsafe because a later same-named object could contain non-baseline instructions.

### Changes on `fix/musl-archive-duplicate-members-20261126`, stacked on PR #70
- Updated `scripts/check-x86-64-baseline-archive.sh` to track each member-name occurrence and extract it with GNU `ar xN` into a separate directory. Every archive entry is checked, including repeated basenames; the error identifies the offending occurrence. Unsafe path-shaped member names fail closed.
- Extended `scripts/test-x86-64-baseline-archive.sh` with two duplicate-name fixtures: a safe archive with two baseline `clone.lo` entries must pass, while an archive whose second `clone.lo` contains AVX must fail and identify occurrence #2. Existing `.lo`, AVX, non-ELF, and empty-archive cases remain covered.
- Bumped the musl verification stamp from `archive-member-scan-v2` to `archive-member-scan-v3` so cached output produced by the previous scanner is not trusted.
- No files under `linux/` were changed. No force push, branch deletion, or merge was performed.

### Validation status
- Local regression executed with GNU binutils `ar 2.44`: **PASS**. The scanner verified both duplicate baseline members and rejected the second duplicate when it contained `vmovdqa`; the existing positive/negative fixtures also passed.
- Exact-head GitHub Actions for this new branch are pending. The real musl image build, BusyBox static link, ISO/disk image, BIOS/UEFI boot, and AYUI first-frame remain unverified; no OS build or boot success is claimed.

### Next priorities
1. Require Userland Validation to pass the duplicate-occurrence regression on the new PR head.
2. Confirm the real musl 1.2.5 `libc.a` scan verifies every member, including duplicate names, and that static BusyBox passes the x86-64 ISA guard.
3. Complete kernel/rootfs/initramfs, ISO, and disk-image assembly.
4. Run BIOS and UEFI separately and require rootfs hand-off plus AYUI first-frame readiness.
5. Diagnose the separate Linux sync failure (#45620871584, `linux` exists on disk but not in the index) without broad cleanup or changes to the vendored kernel tree.


## 2026-11-27 run 12 — Accept verified data-only x86-64 relocatable archive members

### Repository and CI inspection
- Inspected the repository metadata, default branch, root build graph, Cargo workspace, AWEUI and application source layout, bootloader assets, build scripts, CI workflows, and the existing development log. The default branch is `master` at `d4d300545558d660abb2127d297d3a00ef017dae`; the active build work remains in stacked pull-request branches.
- PR #71 (`fix/musl-archive-duplicate-members-20261126`, head `ee256b7fdf32647cfd55363897b80e1549925633`) has a passing Userland Validation job but its image workflow #45753801723 fails during the musl archive scan.
- The exact failure is `__environ.lo`: GNU objdump emits no instruction lines because this is a valid data-only x86-64 relocatable ELF object. The prior checker treated every no-disassembly object as invalid, preventing the pinned musl build from reaching BusyBox and image assembly.
- The independent Linux synchronization workflow #45823429575 also fails at the index/worktree boundary (`linux` exists on disk but is not in the index after the attempted replacement). This is a separate issue and is deliberately not changed here.

### Changes on `fix/musl-data-only-archive-members-20261127`, stacked on PR #71
- Updated `scripts/check-x86-64-baseline-isa.sh` to inspect the ELF type and section headers when objdump produces no instruction lines. It accepts only ET_REL objects with no non-empty executable section, which covers legitimate data-only musl objects without weakening executable-code checks.
- Preserved fail-closed behavior for non-relocatable ELF files with no disassembly, malformed section tables, and relocatable objects that declare non-empty executable sections but produce no instruction lines.
- Extended `scripts/test-x86-64-baseline-isa.sh` with a data-only ET_REL positive fixture and a code-less ET_EXEC negative fixture.
- Extended `scripts/test-x86-64-baseline-archive.sh` with a data-only `.lo` archive member, while retaining duplicate-member, AVX, non-ELF, and empty-archive checks.
- No files under `linux/` were changed. No existing branch, commit, or pull request was deleted, force-pushed, or merged.

### Validation
- Local GNU Binutils 2.44: `test-x86-64-baseline-isa.sh` **PASS** (baseline accepted; data-only ET_REL accepted; AVX, BMI, invalid ELF, and code-less ET_EXEC rejected).
- Local GNU Binutils 2.44: `test-x86-64-baseline-archive.sh` **PASS** (baseline, data-only, and duplicate archive members accepted; second duplicate containing AVX rejected; non-ELF and empty archives rejected).
- `bash -n` passed for the three changed shell scripts.
- The new branch has not yet completed GitHub Actions. A real musl 1.2.5 build, static BusyBox validation, rootfs/initramfs, ISO/disk image, and BIOS/UEFI boot remain unverified. No full OS build or boot success is claimed.

### Next priorities
1. Require both Userland Validation and the full image workflow to pass on this exact branch head.
2. Confirm every member of the real musl 1.2.5 archives is checked and static BusyBox passes the x86-64 baseline guard.
3. Complete rootfs, initramfs, ISO, and disk-image construction.
4. Run BIOS and UEFI boot tests and verify rootfs hand-off plus AYUI readiness.
5. Diagnose the separate Linux sync index/worktree mismatch in an isolated change without broad cleanup or modifications to the vendored kernel tree.


## 2026-11-28 run 13 — Validate musl's intentionally empty compatibility archives

### Exact-head CI diagnosis
- Rechecked PR #72 at head `cd4e2f83cb217899a1b0291a27a3adf542a6f3b8`. Its Userland Validation run #45943318059 passed, but the full x86_64 image/boot run #45943318027 failed in `Build AWEOS images`.
- The log confirms the new scanner accepted the data-only `__environ.lo` and verified all 1,345 members of musl's `libc.a`. The next failure was `libcrypt.a`: the archive exists but has no members, so the generic archive scanner rejected it before BusyBox could build.
- This is expected musl behavior, not a missing library: musl's upstream Makefile defines the compatibility archives `libm.a`, `librt.a`, `libpthread.a`, `libcrypt.a`, `libutil.a`, `libxnet.a`, `libresolv.a`, and `libdl.a` as empty archives. The implementations are provided by `libc.a` (see the [musl FAQ](https://wiki.musl-libc.org/faq) and the [musl Makefile](https://sources.debian.org/src/musl/1.2.2-1/Makefile)). The build stopped at `Makefile:46: busybox`; rootfs, ISO, disk-image, BIOS, and UEFI stages were not reached.
- PR #72 remains a draft and unmerged. No files under `linux/` were changed.

### Changes on `fix/musl-data-only-archive-members-20261127`, stacked on PR #71
- Added `scripts/check-musl-baseline-archives.sh` to validate the complete installed static-library set. It permits an empty archive only when its exact basename is in musl's documented compatibility allowlist.
- Every non-empty archive is still passed to the existing object-by-object x86-64 ISA scanner, including an allowlisted archive if it unexpectedly contains members. Unknown empty archives, zero-byte files, malformed archives, and a missing/empty primary `libc.a` fail closed.
- Updated `scripts/build-musl-baseline.sh` to use the archive-set validator and bumped the cache stamp to `archive-member-scan-v4`, so outputs produced under the previous validation policy are not trusted.
- Added a regression assertion to `scripts/test-musl-baseline-build.sh` that the cache-read check and cache-write stamp both use `archive-member-scan-v4`; this prevents a stale or mismatched verification marker.
- Added `scripts/test-musl-baseline-archives.sh` and wired it into `make test-shell`. The regression covers the allowlisted empty archives, an unknown empty archive, AVX code hidden in a non-empty `libcrypt.a`, and missing/empty `libc.a`.
- No existing branches, commits, or pull requests were deleted, force-pushed, or merged.

### Validation
- Local GNU `ar`/Binutils regression for the archive-set policy: **PASS** (allowlisted empty compatibility archives accepted; unknown empty archive rejected; AVX object in non-empty `libcrypt.a` rejected; missing/empty `libc.a` rejected).
- The exact production archive helper and full `make test-shell` suite still require GitHub Actions validation after this commit. The full musl/BusyBox build, rootfs/initramfs, ISO/disk image, BIOS/UEFI boot, and AYUI readiness remain unverified.

### Next priorities
1. Require Userland Validation and the full image workflow to pass on the new exact PR #72 head.
2. Confirm the complete musl 1.2.5 archive set is scanned/allowlisted as expected and static BusyBox builds successfully.
3. Continue through rootfs, initramfs, ISO, and disk-image construction.
4. Run BIOS and UEFI QEMU tests; require rootfs hand-off and AYUI first-frame readiness.
5. Diagnose the separate Linux synchronization index/worktree failure in an isolated branch without broad cleanup or changes under `linux/`.
