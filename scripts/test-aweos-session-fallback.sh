#!/usr/bin/env bash
# Verify primary -> framebuffer fallback -> recovery ordering and PID 1 safety.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="${repo_root}/scripts/aweos-session.sh"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-session-test.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT

cat > "$tmp_root/session-fails" <<'MOCK'
#!/bin/sh
exit 42
MOCK
cat > "$tmp_root/session-exits" <<'MOCK'
#!/bin/sh
exit 0
MOCK
cat > "$tmp_root/fallback-runs" <<'MOCK'
#!/bin/sh
echo "AWEOS AYUI FRAMEBUFFER READY: device=/dev/fb0 width=800 height=600 bpp=32"
sleep 10
MOCK
cat > "$tmp_root/fallback-fails" <<'MOCK'
#!/bin/sh
exit 43
MOCK
cat > "$tmp_root/recovery" <<'MOCK'
#!/bin/sh
[ "$1" = cttyhack ] || exit 91
[ "$2" = /bin/sh ] || exit 92
count_file="$RECOVERY_COUNT_FILE"
count=0
[ ! -f "$count_file" ] || count="$(cat "$count_file")"
printf '%s\n' "$((count + 1))" > "$count_file"
echo "RECOVERY_STUB_EXECUTED"
sleep 0.1
MOCK
chmod 0755 "$tmp_root/session-fails" "$tmp_root/session-exits" "$tmp_root/fallback-runs" "$tmp_root/fallback-fails" "$tmp_root/recovery"

run_until_recovery() {
    local session="$1" label="$2" fallback="${3:-}"
    local count_file="$tmp_root/${label}.count"
    set +e
    output="$(RECOVERY_COUNT_FILE="$count_file" timeout 2s bash "$helper" "$session" "$tmp_root/recovery" "$fallback" 2>&1)"
    rc=$?
    set -e
    [ "$rc" -eq 124 ] || { echo "ERROR: supervisor exited instead of staying alive (status $rc)" >&2; exit 1; }
    grep -q 'AWEOS RECOVERY SHELL READY' <<< "$output"
    grep -q 'RECOVERY_STUB_EXECUTED' <<< "$output"
    [ "$(cat "$count_file")" -ge 2 ] || { echo "ERROR: recovery shell was not restarted after exit" >&2; exit 1; }
}

# Legacy path: without a fallback, a failed or normally exiting session recovers.
run_until_recovery "$tmp_root/session-fails" failed-session
run_until_recovery "$tmp_root/session-exits" normal-session
run_until_recovery "$tmp_root/missing-session" missing-session

# A failed Winit session must enter the framebuffer backend before recovery.
set +e
output="$(timeout 2s bash "$helper" "$tmp_root/session-fails" "$tmp_root/recovery" "$tmp_root/fallback-runs" 2>&1)"
rc=$?
set -e
[ "$rc" -eq 124 ] || { echo "ERROR: framebuffer fallback exited unexpectedly (status $rc)" >&2; exit 1; }
grep -q 'starting framebuffer fallback' <<< "$output"
grep -q 'AWEOS AYUI FRAMEBUFFER READY' <<< "$output"
if grep -q 'AWEOS RECOVERY SHELL READY' <<< "$output"; then
    echo "ERROR: recovery started while the framebuffer fallback remained alive." >&2
    exit 1
fi

# If the framebuffer backend also fails, recovery must take over.
run_until_recovery "$tmp_root/session-fails" failed-with-fallback "$tmp_root/fallback-fails"

# PID 1 remains alive if no recovery shell is available.
set +e
output="$(timeout 1s bash "$helper" "$tmp_root/session-fails" "$tmp_root/missing-recovery" "$tmp_root/fallback-fails" 2>&1)"
rc=$?
set -e
[ "$rc" -eq 124 ] || { echo "ERROR: PID 1 exited when recovery shell was unavailable (status $rc)" >&2; exit 1; }
grep -q 'keeping PID 1 alive' <<< "$output"

echo "PASS: AYUI tries Winit, then framebuffer fallback, then recovery; PID 1 remains alive if all backends fail."
