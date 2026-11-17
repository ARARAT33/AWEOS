# AWEOS AI Development Log â 2026-11-14

Run log for this scheduled autonomous development cycle. To be merged into
`docs/AI-DEVELOPMENT-LOG.md` when the stacked PR chain is reconciled.

## Starting point (from the previous run)

- PR #50 branch head `3782aa2` fixed the musl-gcc REALGCC sed rewrite; CI on
  that head had not finished at the end of the previous run.
- Branch heads `568a695`, `f173d63`, `5032776`, `6aea17b`, `6269a28`,
  `a1d71e4` (2026-11-13) fixed the synthetic-Makefile dollar escaping in the
  musl fixture regression; the userland job passed.

## Inspection

- PR #50 head is now `a1d71e4`; the fresh full-image run
  [#43371033696](https://github.com/ARARAT33/AWEOS/actions/runs/43371033696)
  failed in `Build AWEOS images` (exit 2) with:
  `ERROR: musl-gcc UAPI probe for <linux/kd.h> failed: In file included from
  linux/include/uapi/linux/kd.h:4, ...`. The userland job passed.
- **This is progress, not a regression:** the qemu64 ISA gate was never
  reached before; the failure now happens earlier, at the UAPI probe, and it
  is the first full-image run that uses the from-source baseline musl-gcc.
- Root cause (verified against the vendored kernel source): the probe and the
  BusyBox compile consumed the **raw** `linux/include/uapi` headers. Those are
  kernel-internal: `linux/kd.h` keeps `__user` annotations and includes
  `<linux/compiler.h>`, which does not exist under `include/uapi`, and
  `<linux/posix_types.h>` requires the generated `asm/posix_types.h`. The
  from-source musl-gcc wrapper compiles with `-nostdinc`, so the distro
  `/usr/include` fallbacks cannot rescue the include chain the way they
  accidentally did with the previous distro musl-gcc path. Raw kernel uapi
  headers are only userspace-consumable after `make headers_install`.

## Implemented (PR #50 branch `boot/busybox-cc-flags-last-20261109`)

- New `scripts/lib/install-uapi-headers.sh`: `aweos_install_uapi_headers`
  runs `make -C linux O=<build>/linux-uapi-build ARCH=x86_64 headers_install
  INSTALL_HDR_PATH=<build>/tools/uapi` (all outputs stay in the build
  directory; `/linux` remains untouched), verifies `linux/kd.h` and
  `asm/posix_types.h` exist, and publishes a userspace-safe
  `linux/compiler.h` stub (matching the linux-libc-dev stub) because
  exported headers such as `<linux/kd.h>` still include it and it is not
  under `include/uapi`.
- `scripts/build-busybox-baseline.sh`: the UAPI probe and the BusyBox
  `CC` flags now use the sanitized prefix (`build/tools/uapi/include`)
  first; the raw `linux/include/uapi` and `arch/x86/include/uapi` include
  paths were removed. Distro include dirs remain as trailing fallbacks.
  The install is idempotent via a marker file.
- New regression `scripts/test-busybox-uapi-headers.sh`: asserts the
  production script installs sanitized headers and no longer consumes raw
  kernel uapi paths; runs the real `make headers_install` from the vendored
  tree; asserts `__user` was stripped from the sanitized `linux/kd.h`; and
  compiles the `<linux/kd.h>` probe with `-nostdinc` against the sanitized
  prefix alone. Wired into `make test-shell`.
- Workflow: the image-build failure summary now prints the UAPI probe error
  and the headers_install log tail; both files are added to the failure
  artifact upload.

## Validation

- `bash -n` syntax checks pass for all changed and new scripts.
- The real end-to-end proof must come from fresh GitHub Actions runs on the
  new head (userland `make test-shell`, including the new UAPI regression,
  and the full image build up to the ISA gate, ISO assembly, and the
  BIOS/UEFI/direct-kernel boot matrix). **No pass is claimed.**

## Remaining issues and next priorities

1. Read the fresh userland and full-image results on the new head. If the
   ISA gate is reached, decide from the attribution report whether any
   linked input is still dirty (candidate: distro `libgcc.a`; fix would be a
   from-source baseline libgcc, never scanner weakening).
2. If ISO assembly completes, require the BIOS, UEFI, and direct-kernel
   QEMU results before any boot-support claim.
3. Diagnose PR #51's master-based full-image failure (exit 2, run
   [#42759726735](https://github.com/ARARAT33/AWEOS/actions/runs/42759726735))
   if it is not the same UAPI root cause.
4. PRs #52/#53 are other agents' work: review only, do not modify.
5. Keep PR #50 draft and the stacked chain unmerged until a reconciled head
   passes the complete boot matrix; merge this dated log into the main log
   at reconciliation.
