# AWEOS AI development run log — 2026-11-27

## What was done
- Inspected PR #50 CI on head 973a010 (run 45838695529, 2026-11-26):
  - userland PASS.
  - "Build AWEOS images" (make image) SUCCEEDED for the first time in a full-image run:
    the ISA gate now passes with Exceptions 1-3 (tzcnt, runtime-dispatched memchr, sha2)
    and the image builds end to end.
  - The failure moved downstream, exactly as predicted in the 2026-11-26 log:
    "Boot-test BIOS, UEFI and direct kernel" (make test-qemu, step 14) FAILED
    ("Process completed with exit code 2").
  - The instrtrace-summary artifact was 235 bytes ("No tagged qemu64 instruction-trace
    debug logs were produced"), so the retry was skipped: the guest most likely reached
    the "AWEOS RECOVERY SHELL READY" console, i.e. a userspace/session failure, not an
    early CPU fault. This is an inference; the serial logs are only download-only
    artifacts and cannot be read through the available GitHub connector.
- CI observability fix (this run's code change, branch boot/busybox-cc-flags-last-20261109):
  - .github/workflows/build-aweos-x86_64.yml gained a new step
    "Summarize boot-test serial output for diagnosis" that, on boot-test failure,
    writes per-mode serial tails (BIOS/UEFI/direct-kernel) plus boot-marker and FAIL
    greps into build/boot-test-failure-summary.txt and $GITHUB_STEP_SUMMARY, and emits
    a ::error annotation with the first FAIL line. The summary file was also added to
    the AWEOS-QEMU-diagnostics artifact list. This makes the failure point readable
    from the check-run API/PR summary without artifact download.

## Real test results
- No new code paths were added to the OS itself; the workflow change is validated by CI.
- CI on the new head was not finished at run end. No pass claimed.

## Unresolved
- The actual first failing boot mode and its serial tail (available after this CI run
  via the new step summary).
- Root cause of the boot-test failure (suspected userspace/session fallback to the
  recovery shell under qemu64).

## Next-run priorities
1. Read the new "Summarize boot-test serial output" step summary on the latest PR #50
   head (check-run API, output.summary) and identify the failing boot mode + marker.
2. If the recovery shell is reached, attribute the session/AYUI failure from the serial
   log and fix it in the init/session path.
3. If another ISA offender reappears, use the attribution report; never weaken the
   scanner without the "cannot #UD on qemu64" justification.
4. Keep the stacked chain unmerged until a reconciled head passes the full boot matrix;
   merge dated logs (2026-11-12..2026-11-27) into docs/AI-DEVELOPMENT-LOG.md at
   reconciliation.
