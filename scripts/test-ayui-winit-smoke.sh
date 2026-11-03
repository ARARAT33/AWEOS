#!/usr/bin/env bash
# Exercise the real AYUI Winit/Wayland compositor under a virtual X11 display.
# This validates nested compositor startup, not native DRM/KMS support.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${1:-target/release/aweui}"
if [[ "$binary" != /* ]]; then
    binary="$repo_root/$binary"
fi
[[ -x "$binary" ]] || { echo "ERROR: AYUI binary is missing or not executable: $binary" >&2; exit 1; }
command -v xvfb-run >/dev/null || { echo "ERROR: xvfb-run is required for the AYUI smoke test" >&2; exit 1; }
command -v timeout >/dev/null || { echo "ERROR: timeout is required for the AYUI smoke test" >&2; exit 1; }

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/aweos-ayui-xvfb.XXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT
runtime_dir="$tmp_root/runtime"
mkdir -m 0700 "$runtime_dir"

export XDG_RUNTIME_DIR="$runtime_dir"
export LIBGL_ALWAYS_SOFTWARE=1
export WINIT_UNIX_BACKEND=x11
log_file="$tmp_root/ayui-xvfb.log"

set +e
timeout --signal=TERM --kill-after=2s 8s \
    xvfb-run -a -s "-screen 0 1280x800x24 +extension GLX" \
    "$binary" >"$log_file" 2>&1
status=$?
set -e

if [[ "$status" -ne 124 ]]; then
    echo "ERROR: AYUI exited before the smoke-test timeout (status $status)." >&2
    tail -n 100 "$log_file" >&2 || true
    exit 1
fi

if ! grep -Eq 'AWEOS AYUI COMPOSITOR READY: backend=winit socket=wayland-[0-9]+' "$log_file"; then
    echo "ERROR: AYUI did not bind its Wayland socket and render the first frame under Xvfb." >&2
    tail -n 100 "$log_file" >&2 || true
    exit 1
fi

grep -E 'AWEOS AYUI COMPOSITOR READY|AYUI services online' "$log_file" | tail -n 5
echo "PASS: AYUI initialized Winit, bound a Wayland socket, and rendered its first frame under Xvfb."
