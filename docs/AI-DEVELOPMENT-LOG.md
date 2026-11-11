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
