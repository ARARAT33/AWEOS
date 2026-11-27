# AWEOS AI Development Log — 2026-11-26

*Note: dated log on the PR #50 branch; merge into the main `docs/AI-DEVELOPMENT-LOG.md` at chain reconciliation.*

## CI inspection (head `1094045`, runs 44108937159 / 44108957964)

- `userland`: **PASS** (both).
- `build-and-boot-test`: **FAIL** at "Build AWEOS images" (exit 2).

Progress: Exception 2 (memchr runtime dispatch) worked. The qemu64 ISA gate then reached a **new** offender inside the Rust userland for the first time. CI annotation:

> build/rootfs/usr/bin/aweui contains instructions outside the AWEOS qemu64/x86-64 baseline (mnemonics: pblendw(2), pshufb(4), palignr(14); symbols: _RNvNtNtCsgrfQT0ztBxT_4sha26sha2563x8613digest_blocks)

## Root cause

The offender is the AYUI userland binary `aweui` pulling in the RustCrypto **sha2** crate. The mangled symbol `4sha26sha2563x8613digest_blocks` is the crate's runtime-dispatched SHA-256 backend kernel (`sha2::sha256::x86::digest_blocks`), assembled with SSSE3 (and, on the shani/avx2 paths, SHA-NI/AVX2) instructions. It is reached **only** through CPU-feature runtime detection (cpufeatures / `is_x86_feature_detected!`); on CPUs without the feature, including the qemu64 boot-test model, the dispatcher never enters the kernel, so its instructions cannot #UD there. The code lives inside a precompiled dependency, so no build flag (`-C target-cpu`, `RUSTFLAGS`, `-Z build-std`) can remove it, and rejecting it would ban every Rust userland binary that hashes anything. Same acceptance criterion as the tzcnt (Exception 1) and memchr (Exception 2) precedents: reject what can execute and fault on qemu64, not what is present but provably unreachable.

## Fix (this commit)

- `scripts/check-qemu64-baseline-isa.sh`: documented **Exception 3 (runtime dispatch, sha2)** — post-baseline mnemonics are skipped ONLY inside symbols whose mangled names contain ALL of: the sha2 crate marker (`4sha2`), a sha256/sha512 digest kernel (`(sha256|sha512)` AND `digest_blocks`), and a backend marker (`3x86`, `4shani`, `avx2`). sha2 symbols without a kernel/backend marker, other crates, and all from-source code still fail closed.
- `scripts/test-qemu64-baseline-isa.sh`: four new fixtures — the real `sha256::x86::digest_blocks` symbol must PASS; a sha2 symbol without `digest_blocks`, a sha2 `digest_blocks` symbol without a backend marker, and a foreign-crate `sha256::shani::digest_blocks` symbol must all FAIL with the same SSSE3 bytes (pshufb). Fixtures compiled and asserted; final PASS text updated.
- The exception predicate was verified out-of-tree against the exact legacy (v0) mangling observed in CI and GNU-style equivalents before pushing.

## Test results

- Out-of-tree predicate check: the two positive mangled-name variants accepted; the three negative fixtures all rejected. Full shell regressions run in the `userland` CI job.
- No CI on the new head yet — **no pass is claimed.**

## Next-run priorities

1. Inspect PR #50 CI on the new head: if the ISA gate passes, remaining failures (if any) move into the image-build tail or the BIOS/UEFI/direct-kernel boot matrix.
2. If another runtime-dispatched dependency kernel appears, extend a narrow documented exception with fixtures; real post-baseline from-source code still fails closed.
3. Keep the stacked chain unmerged until a reconciled head passes the BIOS/UEFI/direct-kernel boot matrix.
4. Merge dated run logs (2026-11-12, 2026-11-14, 2026-11-15, 2026-11-17, this one) into `docs/AI-DEVELOPMENT-LOG.md` at chain reconciliation.
