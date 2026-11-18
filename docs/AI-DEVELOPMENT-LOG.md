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
4. Reduce duplicate Actions execution: both `push` and `pull_request` currently trigger the same validation workflows, so one commit can start redundant full image builds.

### Next priorities
1. Inspect the latest exact-head Userland Validation and full image/boot workflow results.
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
- The older, still-open stacked PR #44 inspected the same address and decoded bytes `c4 e2 fb f7 ca` as `SHRX` (BMI2) in `kernel_ident_mapping_init`. Its proposed kernel baseline fix is not present on current `master`; PR #44 is based on an older stacked branch, so this PR carries only the focused kernel-build guard onto current `master`.
- The downloaded PR #61 diagnostic artifact (run #44241406946) independently confirms the exact bytes at the failing RIP: the filtered BIOS trace records `c4 e2 fb f7 ca` immediately before `#UD`, then `#GP`, double fault and triple fault. BIOS serial output stops after ACPI RSDP discovery; neither BIOS nor UEFI reaches the rootfs hand-off marker.

### Changes on `fix/kernel-baseline-isa-20261118`
- Added `AWEOS_KERNEL_CPU_FLAGS` defaulting to `-march=x86-64 -mtune=generic -mno-bmi -mno-bmi2`, passed through Kbuild's `CC` command so compressed boot code cannot inherit a newer host ISA.
- Added `scripts/check-kernel-baseline-isa.sh` to scan the actual `arch/x86/boot/compressed/vmlinux` after each kernel build and fail the image build if BMI1/BMI2 instructions remain.
- Added a fixture-based regression that accepts baseline code and rejects an explicitly encoded SHRX/BMI2 instruction.
- Wired the regression into `make test-shell` and the post-build ISA check into the real `kernel` target.
- No files under `/linux` were changed.

### Validation
- Local fixture regression using the available C compiler and `objdump`: **PASS** (safe object accepted; explicit SHRX/BMI2 object rejected).
- Shell syntax checks for the new checker and test: **PASS**.
- Exact-head GitHub userland, kernel build, compressed-kernel ISA scan, BIOS/UEFI QEMU boot and `/linux` integrity checks were pending at the start of this follow-up.
- The pre-fix PR #61 full-image run #44241406946 failed both BIOS and UEFI; no successful boot is claimed.

### Follow-up — Make the ISA verification fail closed
- Code review found a fail-open edge in the new verifier: if `objdump` itself failed, the pipeline could be treated like an empty grep result and incorrectly print PASS.
- `scripts/check-kernel-baseline-isa.sh` now captures disassembly first, checks the `objdump` exit status, requires actual disassemblable instruction lines, and distinguishes grep's “no match” result from execution errors.
- `scripts/test-kernel-baseline-isa.sh` now covers three cases: baseline code accepted, explicit SHRX/BMI2 rejected, and malformed non-ELF input rejected before a clean result can be reported.
- Local regression run after the change: **PASS** for all three cases. Shell syntax validation: **PASS**.
- The prior exact-head full-image workflow for commit `20822b2e7d65` was still running when this follow-up was pushed; it does not validate the new follow-up commit. Fresh push/PR workflows for the new head are required.

### Next priorities
1. Inspect the fresh exact-head userland and image/boot runs for the follow-up commit; do not reuse the previous head's results.
2. Confirm the post-build scanner reports no BMI1/BMI2 instructions in the real compressed `vmlinux`.
3. Require fresh BIOS and UEFI QEMU boots to reach rootfs hand-off and AYUI compositor first-frame markers; if they still fail, inspect the new trace and map the first faulting instruction.
4. Keep PR #63 draft/unmerged until the exact-head CI and boot matrix pass; preserve the upstream `/linux` tree unchanged.
