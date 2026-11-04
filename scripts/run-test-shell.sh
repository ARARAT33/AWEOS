#!/usr/bin/env bash
# Central driver for the AWEOS shell/C regression suite (`make test-shell`).
# Runs every scripts/*.sh through bash -n, then executes the regression
# scripts in a fixed order. Emits a GitHub Actions `::error::` annotation
# naming the exact script that failed so CI failures are attributable
# without raw log access.
set -euo pipefail

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
    test-initramfs-root-discovery.sh \
    test-awepkg.sh \
    test-aosin-fail-closed.sh; do
    echo "==> running scripts/$test_script"
    if ! bash "./scripts/$test_script"; then
        echo "::error::make test-shell failed at scripts/$test_script" >&2
        exit 2
    fi
done
