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
