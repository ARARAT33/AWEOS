# AWEOS AI Development Log — 2026-11-12 run (PR #50 branch)

> Dated run log. At merge time, append this section to the main
> `docs/AI-DEVELOPMENT-LOG.md` (the main log on this branch is large and this
> run kept the commit minimal).

## 2026-11-12 — Fix the musl-gcc REALGCC rewrite dropping its closing brace

### Inspection

- PR #50 head advanced to `60c1d38` ("Rewrite the baked REALGCC default in the
  generated musl-gcc wrapper to the host compiler"), but the fresh userland
  workflow still failed in `make test-shell` at
  `scripts/test-musl-baseline-build.sh`: the trace ended at
  `grep -q 'REALGCC:-cc}' "$MUSL_PREFIX/bin/musl-gcc"`.
- Root cause (confirmed locally by replaying the exact sed): the rewrite
  `sed -i "s|REALGCC:-[^}]*}|REALGCC:-${HOSTCC}|"...` matches through the
  closing brace of the shell default expansion but the replacement did not
  re-emit it, so the installed wrapper became `${REALGCC:-cc` (unclosed
  expansion, invalid shell). The "still references the policy wrapper" check
  passed while the published toolchain was unusable; the test's
  `REALGCC:-cc}` grep then failed exactly as observed in CI.
- PR #51 and PR #52 (both master-based, owned by other runs/agents) were
  inspected but not modified. PR #53 stacks on the hybrid-ISO fix and was
  left untouched.

### Implemented

- `scripts/build-musl-baseline.sh`: the REALGCC rewrite now re-emits the
  closing brace (`REALGCC:-${HOSTCC}}`), and the script fails closed with
  `sh -n` if the installed musl-gcc wrapper is not valid shell before
  publishing the toolchain.
- `scripts/test-musl-baseline-build.sh`: the install-verification step now
  runs `sh -n` on the synthetic installed wrapper, so any future rewrite that
  produces an invalid wrapper fails the regression instead of the grep.
- The sed fix was verified locally against the exact synthetic wrapper text:
  the new expression produces `${REALGCC:-cc}` (valid, grep matches); the old
  expression reproduces the broken `${REALGCC:-cc` output seen in CI.

### Files changed

- `scripts/build-musl-baseline.sh`
- `scripts/test-musl-baseline-build.sh`
- `docs/AI-DEVELOPMENT-LOG-2026-11-12.md` (this file)

### Validation

- Local sed replay of both the fixed and the old expression on the exact
  synthetic wrapper text (old one reproduces the CI failure, new one passes).
- The full offline regression (`make test-shell`) and the fresh userland +
  full-image workflows must run on the new head; no pass is claimed until
  those runs complete.

### Unresolved issues and next priorities

1. Read the fresh userland and full-image workflow results on this head; if
   the ISA scan still fails, the attribution file should name the next dirty
   input (candidate: distro `libgcc.a`; fix = from-source baseline libgcc).
2. Diagnose PR #51's full-image "Build AWEOS images" exit-2 failure
   (independent, master-based).
3. Keep the stacked chain (#43-#50) unmerged until a reconciled head passes
   the BIOS/UEFI/direct-kernel boot matrix.
4. Merge this dated log section into `docs/AI-DEVELOPMENT-LOG.md` when the
   chain is reconciled.
