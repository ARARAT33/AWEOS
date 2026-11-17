# AWEOS AI Development Log — 2026-11-15

> Dated run log; merge into `docs/AI-DEVELOPMENT-LOG.md` when the stacked
> PR chain is reconciled into master.

## Context

Continued from the 2026-11-14 run (PR #50 branch
`boot/busybox-cc-flags-last-20261109`, head `8734005`): the sanitized-UAPI
fix reached the ISA gate for the first time in a full-image run.

## Diagnosis

CI on `8734005` (runs 43607827158 / 43607836951):

- `userland`: **success**.
- `build-and-boot-test`: **failure** at "Build AWEOS images", exit code 2.
- The UAPI fix worked: the build progressed past the musl-gcc UAPI probe and
  the BusyBox baseline gate, and the qemu64 ISA scanner now runs over the
  packaged rootfs binaries.
- The attribution report named exactly one offender:
  `build/rootfs/usr/bin/aweui-text-editor`, mnemonic `tzcnt` (30 hits),
  symbols inside Rust std backtrace machinery
  (`core::cell::once::OnceCell ... LazyFunctions ... borrow`,
  `addr2line`/`gimli`).

Root cause: `tzcnt` was on the scanner's rejected list, but its encoding
(`F3 0F BC`, "rep bsf") is the BSF opcode with a rep prefix. On CPUs
without BMI1 — including the qemu64 model used by the boot tests — the rep
prefix is ignored and the instruction executes as BSF, so it cannot #UD
there. LLVM emits this encoding for `count_trailing_zeros` even on the
x86-64-v1 baseline, including Rust's precompiled std, and pairs it with an
explicit zero-input check whenever the zero result is defined. This is a
scanner over-reach, not a real qemu64 incompatibility, and it cannot be
fixed with build flags because the code lives in precompiled std.

## Changes

- `scripts/check-qemu64-baseline-isa.sh`: removed `tzcnt` from the rejected
  mnemonic set with a full justification comment. This is the only
  encoding-level exception; `lzcnt` and every other mnemonic still fail
  closed. The scanner was not weakened in intent: its purpose is to reject
  instructions that #UD or use VEX/EVEX on baseline CPUs, and tzcnt's
  encoding does neither.
- `scripts/test-qemu64-baseline-isa.sh`: the tzcnt fixture is now asserted
  to PASS (documented as rep-bsf encoding), a new lzcnt fixture asserts
  lzcnt is still rejected, and the final PASS message was updated.

## Test results

- Local execution of the repo's test suite is not possible in this
  environment (no Linux toolchain/QEMU); validation relies on CI.
- CI was triggered by the new push; results were not available at run end —
  **no pass claimed**.

## Unresolved / next run priorities

1. Inspect PR #50 CI on the new head. If the ISA gate passes, the next
   failures (if any) will be in the BIOS/UEFI/direct-kernel boot matrix.
2. If another ISA offender appears, use the attribution report; candidates
   are real post-baseline instructions requiring from-source baseline
   toolchain fixes, never scanner weakening.
3. PRs #52/#53 are other agents' work — review but do not modify.
4. Keep the stacked chain unmerged until a reconciled head passes the
   BIOS/UEFI/direct-kernel boot matrix; then merge the dated 2026-11-12,
   2026-11-14 and this log into `docs/AI-DEVELOPMENT-LOG.md`.
