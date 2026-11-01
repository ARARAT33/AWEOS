#!/usr/bin/env bash
# Verify that a failed or normally exiting session cannot make PID 1 exit.
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
chmod 0755 "$tmp_root/session-fails" "$tmp_root/session-exits" "$tmp_root/recovery"

run_until_timeout() {
    local session="$1" label="$2"
    local count_file="$tmp_root/${label}.count"
    set +e
    output="$(RECOVERY_COUNT_FILE="$count_file" timeout 1s bash "$helper" "$session" "$tmp_root/recovery" 2>&1)"
    rc=$?
    set -e
    [ "$rc" -eq 124 ] || { echo "ERROR: recovery supervisor exited instead of staying alive (status $rc)" >&2; exit 1; }
    grep -q 'AWEOS RECOVERY SHELL READY' <<< "$output"
    grep -q 'RECOVERY_STUB_EXECUTED' <<< "$output"
    [ "$(cat "$count_file")" -ge 2 ] || { echo "ERROR: recovery shell was not restarted after exit" >&2; exit 1; }
}

run_until_timeout "$tmp_root/session-fails" failed-session
run_until_timeout "$tmp_root/session-exits" normal-session
run_until_timeout "$tmp_root/missing-session" missing-session

set +e
output="$(timeout 1s bash "$helper" "$tmp_root/session-fails" "$tmp_root/missing-recovery" 2>&1)"
rc=$?
set -e
[ "$rc" -eq 124 ] || { echo "ERROR: PID 1 exited when recovery shell was unavailable (status $rc)" >&2; exit 1; }
grep -q 'keeping PID 1 alive' <<< "$output"

echo "PASS: failed, missing, and normally exiting sessions restart the recovery console; PID 1 remains alive if the recovery shell is unavailable."
