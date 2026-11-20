# AWEOS implementation status

**Snapshot:** 2026-11-20  
**Scope:** repository code and the latest observed GitHub Actions evidence. This is an implementation inventory, not a product-readiness certification.

## Status key

- **Implemented and tested** — code is present and a named test passed.
- **Implemented, integration pending** — code/build wiring exists, but the current exact head has not completed the relevant integration test.
- **Partial** — some real code exists, but the full advertised capability is not implemented.
- **Not implemented / not validated** — no production implementation or adequate test evidence was found.

## Current product baseline

| Area | Status | Evidence / boundary |
|---|---|---|
| Linux kernel build | Implemented and tested | Upstream Linux is built out-of-tree for x86_64. The vendored `/linux` tree is guarded by read-only integrity checks. This is not an independent AWEOS kernel. |
| Kernel x86-64 baseline | Implemented and tested | PR #63 applies baseline compiler flags and scans the built compressed vmlinux for BMI1/BMI2 instructions. |
| BIOS boot | Partial / failing | The image builds, but BIOS boot reaches PID 1 and then fails with a userspace SIGILL at RIP 0x56df50. The rootfs init hand-off marker is not reached. |
| UEFI boot | Not validated on the current failure path | The boot matrix stops after the BIOS leg fails; do not claim UEFI boot success from image creation alone. |
| AYUI compositor | Partial | Rust/Smithay Wayland compositor code is present. Current tested backend is nested Winit/GLES, not direct DRM/KMS. Popup, pointer/touch, decorations, panel rendering and multi-monitor behavior remain incomplete or unvalidated. |
| Rust userland | Implemented and tested | The workspace builds and its unit tests pass in the Userland Validation workflow. A passing workspace build does not prove every application feature is complete. |
| AOSIN v2 format | Implemented and tested | Bounded package header/file table, SHA-256 payload integrity, create/verify/inspect/install/remove code, and negative tests are present. |
| AOSIN rootfs CLI integration | Implemented, integration pending | A Makefile target and rootfs install/validation wiring now ship `/usr/bin/aosin`; exact-head image validation is still pending. |
| Legacy awepkg wrapper | Hardened in source | The unsafe tar extraction and absolute-path deletion paths are disabled. Install/remove delegate only to native `aosin`; wrapper regressions are included in Userland Validation. |
| Package authenticity | Not implemented | SHA-256 detects payload corruption; it does not authenticate a publisher. No trusted signing keys, signed repository metadata, or dependency resolver exists. |
| Device identity primitives | Implemented and tested | SHA-256/HMAC helpers and deterministic identity derivation have known-answer and negative tests. |
| Peer authentication / encrypted network | Not implemented | No verifier, public-key enrollment, protected key provisioning, encrypted transport, service discovery, or network daemon is integrated. See NETWORK-IDENTITY.md. |
| Installer / updater / WLIN C modules | Source-level only | C source exists, but these modules are not built or installed by the default image pipeline and are not end-to-end validated. |
| ARM64 / RISC-V / LoongArch | Not implemented / not validated | Bootloader EFI files do not constitute kernel ports. The current kernel/image build target is x86_64. |
| Physical hardware support | Not validated | Current evidence is QEMU x86_64. No device-specific support claims should be made for GPU, Wi-Fi, Bluetooth, audio, touch, or storage controllers without hardware tests. |

## Verified workflow evidence

- [PR #63 — x86-64 kernel baseline](https://github.com/ARARAT33/AWEOS/pull/63): on head `7a2aa278080dfbab73c65844dc3197b0aae855db`, kernel build, compressed-vmlinux BMI1/BMI2 scan, rootfs/ISO/disk-image build, and `/linux` integrity checks passed. BIOS boot then failed with PID 1 SIGILL at 0x56df50. UEFI was not reached.
- [PR #67 — userspace ISA trace](https://github.com/ARARAT33/AWEOS/pull/67): Userland Validation passed on head `4814dcde950a686e701795711bf96af6b2ff5591`, including the targeted QEMU trace-helper regression. The full image/boot diagnostic run is still pending.
- [PR #66 — AOSIN hardening and CLI integration](https://github.com/ARARAT33/AWEOS/pull/66): uninstall-scope regression passed before the later rootfs integration commits. The latest exact-head userland/image checks must be consulted before claiming the CLI is shipped successfully.

## Next engineering priorities

1. Map the BIOS userspace SIGILL at 0x56df50 to its ELF and rebuild only the offending userspace component for the x86-64 baseline.
2. Complete BIOS and UEFI boot tests and require the rootfs hand-off and AYUI first-frame markers independently.
3. Make AOSIN install staging and metadata publication transactional; add crash-recovery tests and collision-safe staging.
4. Add publisher signatures and trusted-key verification before allowing privileged package installation of untrusted content.
5. Complete AYUI pointer/touch, popup, panel, decoration and direct DRM/KMS paths with real QEMU/physical-device tests.
6. Implement device enrollment, key provisioning, peer verification, encrypted transport, discovery and offline recovery before advertising a network platform.
7. Keep installer/updater/WLIN source modules out of production claims until they are built, integrated, and tested against disposable virtual disks.
8. Create a separate ARM64 kernel/boot port plan; do not infer support from bootloader artifacts.
