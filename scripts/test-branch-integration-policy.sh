#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT="$SCRIPT_DIR/branch-integration-policy.sh"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aweos-branch-policy.XXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

expect_pass() {
    local label="$1"
    if ! bash "$SCRIPT" "$TEMP_ROOT/files" "$TEMP_ROOT/checks.json" >"$TEMP_ROOT/out" 2>&1; then
        echo "ERROR: expected policy pass for $label" >&2
        cat "$TEMP_ROOT/out" >&2
        exit 1
    fi
}
expect_block() {
    local label="$1"
    if bash "$SCRIPT" "$TEMP_ROOT/files" "$TEMP_ROOT/checks.json" >"$TEMP_ROOT/out" 2>&1; then
        echo "ERROR: expected policy block for $label" >&2
        exit 1
    fi
}

# Standard userland paths require both userland and full image/boot checks.
printf '%s\n' 'AWEUI/src/ipc.rs' 'scripts/test-policy.sh' 'Makefile' > "$TEMP_ROOT/files"
cat > "$TEMP_ROOT/checks.json" <<'JSON'
[
  {"name":"userland","state":"SUCCESS"},
  {"name":"userland","state":"SUCCESS"},
  {"name":"build-and-boot-test","state":"SUCCESS"}
]
JSON
expect_pass 'userland and build checks'

# A green subset must not pass when one required workflow is absent.
cat > "$TEMP_ROOT/checks.json" <<'JSON'
[{"name":"userland","state":"SUCCESS"}]
JSON
expect_block 'missing build check'
grep -Fq 'required successful check is missing: build-and-boot-test' "$TEMP_ROOT/out"

# Duplicate runs are all authoritative; a pending or failed duplicate blocks.
cat > "$TEMP_ROOT/checks.json" <<'JSON'
[
  {"name":"userland","state":"SUCCESS"},
  {"name":"userland","state":"PENDING"},
  {"name":"build-and-boot-test","state":"SUCCESS"}
]
JSON
expect_block 'pending duplicate check'

cat > "$TEMP_ROOT/checks.json" <<'JSON'
[
  {"name":"userland","state":"SUCCESS"},
  {"name":"build-and-boot-test","state":"FAILURE"}
]
JSON
expect_block 'failed check'

# Bootloader-only changes require the image/boot workflow.
printf '%s\n' 'Bootloader/x86_64/BOOTX64.EFI' > "$TEMP_ROOT/files"
cat > "$TEMP_ROOT/checks.json" <<'JSON'
[{"name":"build-and-boot-test","state":"SUCCESS"}]
JSON
expect_pass 'bootloader validation'

# C core/installer/updater changes additionally require the preservation suite.
printf '%s\n' 'src/core/transaction.c' > "$TEMP_ROOT/files"
cat > "$TEMP_ROOT/checks.json" <<'JSON'
[
  {"name":"userland","state":"SUCCESS"},
  {"name":"build-and-boot-test","state":"SUCCESS"},
  {"name":"archive-regression","state":"SUCCESS"}
]
JSON
expect_pass 'core preservation validation'

# Workflow, documentation, kernel source and unknown paths are manual-review only.
printf '%s\n' '.github/workflows/branch-integration.yml' > "$TEMP_ROOT/files"
expect_block 'workflow change'
printf '%s\n' 'docs/AI-DEVELOPMENT-LOG.md' > "$TEMP_ROOT/files"
expect_block 'documentation change'
printf '%s\n' 'linux/kernel/sched/core.c' > "$TEMP_ROOT/files"
expect_block 'vendored kernel change'
printf '%s\n' 'assets/unknown.bin' > "$TEMP_ROOT/files"
expect_block 'unknown path'
: > "$TEMP_ROOT/files"
expect_block 'empty diff'

echo "PASS: branch integration policy requires path-specific CI coverage and blocks unverified changes."
