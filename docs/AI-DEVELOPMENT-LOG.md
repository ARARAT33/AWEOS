# AWEOS AI Development Log

## 2026-11-11 — Root filesystem build reliability

### Repository baseline inspected
- Default branch: `master`.
- Baseline commit: `0939488f5261b04c9c3af150e5e4dc8888896a9f` (2026-09-25).
- The upstream Linux source is vendored under `/linux`; this work does not modify it.
- The repository already contains a native Rust/Smithay AYUI desktop, a Linux/Limine x86_64 boot path, AOSIN userland, rootfs/ISO build scripts, and QEMU boot-test automation. The README describes both the AYUI default and an optional Ubuntu GNOME profile; those are distinct implementation paths and must be validated separately.

### Findings
- PR #51's Linux staged-subtree regression workflow passed, and its Rust userland validation passed.
- The x86_64 image workflow on PR #51 failed after successfully building the Rust workspace and rootfs. The exact failure was:
  `/bin/bash: ./scripts/validate-rootfs-layout.sh: Permission denied`.
- Git tree inspection confirmed `scripts/validate-rootfs-layout.sh` is mode `100644`, while the Makefile executed it directly.
- A second mode mismatch was found in the optional GNOME path: `scripts/build-rootfs.sh` directly executed `build-rootfs-gnome.sh`, which is also mode `100644`.

### Changes in this run
- Updated the Makefile to invoke the rootfs layout validator explicitly with Bash in both `rootfs` and `validate-rootfs` targets.
- Updated the GNOME rootfs dispatch to use `exec bash`, avoiding dependence on the non-executable Git mode of the GNOME script.
- Added `scripts/test-rootfs-layout-validator.sh`, which builds a minimal valid fixture, exercises the actual Makefile target, and verifies that a missing boot-critical configuration is rejected.
- Added this development log. The Linux source tree remains untouched.

### Test status
- Existing remote CI evidence before these changes: PR #51 Linux index-subtree regression **PASS**; PR #51 Rust userland validation **PASS**; PR #51 x86_64 image build **FAIL** at the rootfs validator permission boundary.
- The new regression test and updated build path have not yet been executed by GitHub Actions in this run. Their status is **PENDING CI**, not PASS.
- No local build was claimed because this run used the GitHub repository connector rather than a checked-out build environment.

### Remaining issues and next priorities
1. Run the new rootfs regression test and the full x86_64 image/boot workflow; inspect the first real failure after the permission issue is removed.
2. Check whether the GNOME profile has further build/runtime issues after the dispatch fix; it requires its own CI coverage and is not implied to work by AYUI results.
3. Continue the independent Linux sync PR #51 only after reviewing its complete check set.
4. Audit the installer, updater, package manager, and AYUI runtime against their actual tests; keep unimplemented hardware/network features explicitly marked as unsupported until exercised.
5. Preserve the read-only `/linux` boundary and do not merge unverified changes.


### CI follow-up — 2026-11-11

- The first intermediate branch checks exposed a second, independent baseline issue: clean Ubuntu runners could not link `-linput` and `-lxkbcommon`. The logs showed the missing native libraries explicitly. Added `libinput-dev` and `libxkbcommon-dev` to both CI dependency sets; this overlaps the same runner fix already present in the independent Linux-sync PR #51.
- Added `make test-shell` to both relevant workflows so the new fixture-based rootfs regression is actually executed by CI, rather than merely being present in the repository.
- Final-head PR userland workflow **PASS** on `0ad6bd2f8fc863060f10a0649151ef3a69cad5d5` (run [#42962547537](https://github.com/ARARAT33/AWEOS/actions/runs/42962547537)). Verified completed steps: repository boundary, shell/rootfs regression, Cargo metadata, Rust workspace tests, release build, and expected binary checks all passed.
- The rootfs regression output confirmed both the valid layout and fail-closed missing-config case:
  - `AWEOS rootfs layout validation passed`
  - `PASS: Makefile invokes the rootfs validator and invalid rootfs layouts are rejected.`
- The full x86_64 image/BIOS/UEFI QEMU workflow [#42962547574](https://github.com/ARARAT33/AWEOS/actions/runs/42962547574) was still running at the last poll, after the new shell regression and Rust workspace tests had passed and while `Build AWEOS images` was in progress. No ISO or boot success is claimed yet.
- PR #52 remains a draft and unmerged. Do not merge until the full image/boot workflow finishes and its logs are reviewed.


### Architecture audit notes for the next development cycle

- The current Makefile's production userland path is the Rust Cargo workspace (`AWEUI` plus `APPS`). The parallel C implementation under `src/gui` is not built by the current Makefile path; it must not be described as part of the shipped desktop until a separate build/integration path is added and tested.
- The Rust AYUI compositor currently handles keyboard input and a limited pointer-motion focus path, but the inspected Wayland handler does not yet implement a complete pointer/seat interaction path. Window titles and app IDs are currently hard-coded for newly created toplevels. Full desktop input/window-management support remains unverified.
- The current master IPC constructor unconditionally unlinks the configured path before binding. PR #21 already contains a safer stale-socket-only cleanup, a private socket mode, a per-session runtime path, and regression coverage; review that existing work rather than reimplementing it.
- The C updater in master does not check the result of `aweos_tx_preserve()` before continuing. PR #23 already addresses fail-closed preservation and adds archive/updater regression tests; keep the updater disabled from destructive use until that branch's tests and integration are verified.
- The C WLIN path currently initializes `target_disk_idx = 0` and accesses that index without first proving that storage discovery found a disk; its staging function sets a state flag but does not yet stage a kernel/initramfs payload. Treat WLIN as incomplete, not a working cross-OS installer.
- The QEMU helper checks serial boot markers and panic patterns; it does not yet prove interactive input, window creation, pointer operation, or application launch. A boot marker is not equivalent to a desktop acceptance test.

These are source-inspection findings, not claims that the affected paths were executed in this run. They are recorded to prevent planned or partial functionality from being presented as production-ready.


## 2026-11-11 second run — Publish image-build failure diagnostics

### CI results inspected
- PR #52 userland workflow 42962547537: PASS on 0ad6bd2 (repository boundary, shell/rootfs regression, Cargo metadata, Rust workspace tests, release build, expected binary checks).
- PR #52 full x86_64 image workflow 42962547574: FAIL. The single job build-and-boot-test finished in 16m 51s with exit code 2; no artifacts were published and the only annotation is the exit code, so the first real failing command inside make image is still unknown.
- GitHub Actions logs require an authenticated web session and the unauthenticated Actions REST API was rate-limited from this environment, so the failing command could not be read directly this run. No speculative build fix was made for that reason.

### Implemented
- .github/workflows/build-aweos-x86_64.yml: the Build AWEOS images step now runs make image 2>&1 | tee build-make-image.log under set -o pipefail, preserving the make exit code while capturing the full output.
- New Publish make-image failure diagnostics step (if: failure()): appends the last 300 lines of the captured log to the job step summary.
- New Upload make-image and QEMU logs step (if: failure()): uploads build-make-image.log plus the QEMU BIOS/UEFI serial logs as the aweos-build-failure-logs artifact, so image and boot failures are readable without a web login.
- No production build or runtime code path was changed; the existing steps and the /linux verification order are preserved.

### Files changed
- .github/workflows/build-aweos-x86_64.yml
- docs/AI-DEVELOPMENT-LOG.md

### Validation status
- No pass is claimed. The change is CI-only; the authoritative validation is the next run of the x86_64 image workflow on this branch.

### Next priorities
1. Read the step summary or the aweos-build-failure-logs artifact from the next run and identify the actual failing command inside make image (or make test-qemu).
2. Fix that concrete failure; do not merge PR #52 until a full image + BIOS/UEFI boot run passes.
3. Keep the separate PR #43-#50 boot stack and the PR #51 Linux-sync work unmerged until their own gates pass.
