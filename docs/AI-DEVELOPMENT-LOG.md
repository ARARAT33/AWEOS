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
