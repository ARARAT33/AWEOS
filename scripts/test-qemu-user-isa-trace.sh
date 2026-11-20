#!/usr/bin/env bash
# Regression tests for the targeted QEMU userspace-ISA trace helper.
set -euo pipefail

repo_root="$(cd "$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
helper="$repo_root/scripts/trace-qemu-user-isa-fault.sh"
tmp="$(mktemp -d "\${TMPDIR:-/tmp}/aweos-qemu-isa-trace.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/fake-qemu" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$AWEOS_FAKE_QEMU_ARGS"
previous=""
for arg in "$@"; do
    if [ "$previous" = "-D" ]; then
        printf 'fake QEMU instruction trace\n' >"$arg"
    fi
    previous="$arg"
done
exit 124
FAKE
chmod +x "$tmp/fake-qemu"

printf '[    1.5] RIP: 0033:0x56df50\n' >"$tmp/serial.log"
AWEOS_FAKE_QEMU_ARGS="$tmp/args" bash "$helper" "$tmp/serial.log" "$tmp/trace.log" "$tmp/fake-qemu" -machine q35

grep -Fxq 'int,in_asm' "$tmp/args"
grep -Fxq '0x56de50-0x56e050' "$tmp/args"
grep -q 'fake QEMU instruction trace' "$tmp/trace.log"

printf 'no user-mode exception marker\n' >"$tmp/no-rip.log"
if AWEOS_FAKE_QEMU_ARGS="$tmp/should-not-run" bash "$helper" "$tmp/no-rip.log" "$tmp/no-rip.trace" "$tmp/fake-qemu" >/dev/null 2>&1; then
    echo "ERROR: trace helper accepted a serial log without a userspace RIP." >&2
    exit 1
fi
if [ -e "$tmp/should-not-run" ]; then
    echo "ERROR: QEMU was started without a userspace RIP." >&2
    exit 1
fi

echo "PASS: targeted QEMU userspace ISA trace uses a bounded address filter and fails closed without a RIP."
