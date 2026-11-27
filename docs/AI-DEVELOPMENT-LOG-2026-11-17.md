# AWEOS AI Development Log — 2026-11-17

## Run scope

Continuation of the PR #50 (stacked chain head, branch
`boot/busybox-cc-flags-last-20261109`) qemu64 baseline boot work. This run
inspected the CI result on head `e604685` and fixed the next ISA-gate
failure.

## CI inspection (PR #50, head e604685)

- `userland`: **PASS** (both runs).
- `build-and-boot-test`: **FAIL** at "Build AWEOS images" (exit 2), run
  43723133912 / 43723006720.
- Progress confirmed: the tzcnt encoding exception from 2026-11-15 works —
  the gate now reaches and scans the Rust userland binaries in a full-image
  run for the first time.

## Diagnosis

The image-build failure annotation named one offender:

```
build/rootfs/usr/bin/aweui-settings contains instructions outside the
AWEOS qemu64/x86-64 baseline (mnemonics: vmovdqa(2), vpor(3), vpmovmskb(17),
... vpaddq(51); symbols: ...6memchr4arch6x86_646memchr11memrchr_raw9find_avx2,
...9count_raw9find_avx2)
```

Root cause: Rust's **precompiled std** embeds the `memchr` crate's SIMD
kernels (`memchr::arch::x86_64::*`, e.g. `find_avx2`, `count_raw::find_avx2`).
These functions are compiled with `#[target_feature(enable = "avx2")]` and
are reachable **only** through `is_x86_feature_detected!` runtime dispatch.
On CPUs without AVX2, including the `qemu64` model used by the boot tests,
the dispatcher never enters these kernels, so their instructions cannot
`#UD` there. This code lives inside the precompiled std, so no build flag
(`-C target-cpu`, `RUSTFLAGS`, `-Z build-std`) can remove it; failing it
would ban every Rust userland binary.

This is the same acceptance criterion already established by the tzcnt
precedent (2026-11-15): the gate rejects what can execute (and fault) on
qemu64, not what is merely present but provably unreachable.

## Fix (head of this run, same branch)

- `scripts/check-qemu64-baseline-isa.sh`: added **Exception 2 (runtime
  dispatch)** — VEX/EVEX/post-baseline instructions are skipped ONLY inside
  symbols whose mangled names contain BOTH the memchr arch path
  (`6memchr4arch6x86_64`) AND an `avx2`/`ssse3`/`sse42` kernel marker.
  AVX-512 kernel names, memchr symbols without a kernel marker, every other
  crate, and all from-source code still fail closed. Full justification
  comment added next to the tzcnt exception.
- `scripts/test-qemu64-baseline-isa.sh`: four new assembly fixtures:
  - `_ZN6memchr4arch6x86_646memchr11memrchr_raw9find_avx2E` with VEX bytes
    must **PASS**;
  - `_ZN6memchr4arch6x86_646memchr6detectE` (no kernel marker) with the same
    VEX bytes must **FAIL**;
  - `_ZN6memchr4arch6x86_646memchr9find_avx512E` must **FAIL**;
  - `_ZN9othercrate4arch6x86_6410find_avx2E` must **FAIL**.
  The awk rejection logic was additionally verified out-of-tree against a
  synthetic objdump listing covering all five symbol classes.

## Test results

- Local: awk gate logic verified against a synthetic objdump dump (kernel
  symbol skipped; fixture, no-marker, avx512, other-crate symbols all
  reported). The full regression script requires `cc`/`objdump` and runs in
  CI via `make test-shell`.
- CI on the new head: **started, not finished at run end — no pass claimed.**

## Unresolved issues

- The full-image run must now pass the remaining rootfs/initramfs/ISO stages
  and the BIOS/UEFI/direct-kernel qemu64 boot matrix; any further failures
  are new territory past the ISA gate.
- The runtime-dispatch exception is static and name-based; the qemu64 boot
  test with its instruction trace remains the dynamic backstop.

## Next-run priorities

1. Inspect PR #50 CI on the new head. If the ISA gate passes, diagnose the
   next failure in the image build or boot matrix (if any).
2. If another ISA offender appears, use the attribution report; fix toolchain
   inputs from source, never widen the scanner without the "cannot #UD on
   qemu64" justification.
3. Do not merge the stacked chain until a reconciled head passes the
   BIOS/UEFI/direct-kernel boot matrix.
4. PRs #52/#53 are other agents' work — review but do not modify.
5. Merge the dated logs (2026-11-12, 2026-11-14, 2026-11-15, 2026-11-17)
   into `docs/AI-DEVELOPMENT-LOG.md` when reconciling the chain.
