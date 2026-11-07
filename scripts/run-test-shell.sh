#!/usr/bin/env bash
# Central driver for the AWEOS shell/C regression suite (`make test-shell`).
# Runs every scripts/*.sh through bash -n, then executes the regression
# scripts in a fixed order under `bash -x`. Emits GitHub Actions `::error::`
# annotations naming the exact failing script plus the last trace lines so
# failures are attributable without raw log access.
set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

for script in scripts/*.sh; do
    if ! bash -n "$script"; then
        echo "::error::bash -n syntax check failed for $script" >&2
        exit 2
    fi
done

for test_script in \
    test-build-dir-safety.sh \
    test-build-disk-image-safety.sh \
    test-transaction-fail-closed.sh \
    test-storage-discovery.sh \
    test-build-iso-safety.sh \
    test-rootfs-runtime-validation.sh \
    test-ayui-framebuffer-build.sh \
    test-ayui-framebuffer-format.sh \
    test-aweos-session-fallback.sh \
    test-qemu-test-runner.sh \
    test-qemu-instrtrace-extract.sh \
    test-kernel-baseline-isa.sh \
    test-qemu64-baseline-isa.sh \
    test-initramfs-root-discovery.sh \
    test-awepkg.sh \
    test-aosin-fail-closed.sh; do
    echo "==> running scripts/$test_script"
    trace_log="$(mktemp "${TMPDIR:-/tmp}/aweos-testshell-trace.XXXXXX")"
    if bash -x "./scripts/$test_script" >"$trace_log" 2>&1; then
        rm -f -- "$trace_log"
    else
        status=$?
        last_trace="$(tail -n 10 "$trace_log" | cut -c1-240 | tr '\n' ';')"
        echo "::error::make test-shell failed at scripts/$test_script (exit $status). Last trace: $last_trace" >&2
        echo "----- begin failing trace (scripts/$test_script) -----"
        tail -n 40 "$trace_log"
        echo "----- end failing trace -----"
        rm -f -- "$trace_log"
        exit 2
    fi
done
