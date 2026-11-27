#!/usr/bin/env bash
# BusyBox baseline configuration and required-applet regressions.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aweos-busybox-config-test.XXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

SOURCE_DIR="$TEMP_ROOT/busybox"
FAKE_BIN="$TEMP_ROOT/bin"
mkdir -p "$SOURCE_DIR" "$FAKE_BIN"

cat > "$SOURCE_DIR/.config" <<'EOF'
# CONFIG_STATIC is not set
CONFIG_TC=y
CONFIG_FEATURE_TC_INGRESS=y
CONFIG_SHA1_HWACCEL=y
CONFIG_SHA256_HWACCEL=y
CONFIG_ROUTE=y
EOF

# The helper only needs the BusyBox Kconfig oldconfig target. A stub keeps this
# unit test independent from a downloaded BusyBox tree and host compiler.
cat > "$FAKE_BIN/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "-C" && "${3:-}" == "oldconfig" && -d "${2:-}" ]]
EOF
chmod 0755 "$FAKE_BIN/make"

PATH="$FAKE_BIN:$PATH" bash "$REPO_ROOT/scripts/configure-busybox-baseline.sh" "$SOURCE_DIR"
grep -qx 'CONFIG_STATIC=y' "$SOURCE_DIR/.config"
grep -qx '# CONFIG_TC is not set' "$SOURCE_DIR/.config"
grep -qx '# CONFIG_FEATURE_TC_INGRESS is not set' "$SOURCE_DIR/.config"
grep -qx '# CONFIG_SHA1_HWACCEL is not set' "$SOURCE_DIR/.config"
grep -qx '# CONFIG_SHA256_HWACCEL is not set' "$SOURCE_DIR/.config"
grep -qx 'CONFIG_ROUTE=y' "$SOURCE_DIR/.config"

cp "$SOURCE_DIR/.config" "$TEMP_ROOT/first.config"
PATH="$FAKE_BIN:$PATH" bash "$REPO_ROOT/scripts/configure-busybox-baseline.sh" "$SOURCE_DIR"
cmp -s "$TEMP_ROOT/first.config" "$SOURCE_DIR/.config"

echo "PASS: BusyBox baseline configuration is safe, deterministic, and idempotent."

# The build must verify the binary's actual --list output. A previous inline
# check accidentally searched each required applet against itself and could
# never detect a missing BusyBox command.
FAKE_BUSYBOX="$TEMP_ROOT/fake-busybox"
APPLET_LIST="$TEMP_ROOT/applets.txt"
cat > "$FAKE_BUSYBOX" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "--list" ]] || exit 64
[[ "${AWEOS_TEST_BUSYBOX_FAIL:-0}" != "1" ]] || exit 23
cat "${AWEOS_TEST_BUSYBOX_APPLETS:?}"
EOF
chmod 0755 "$FAKE_BUSYBOX"

printf 'cat\nsh\nmount\n' > "$APPLET_LIST"
AWEOS_TEST_BUSYBOX_APPLETS="$APPLET_LIST" \
    bash "$REPO_ROOT/scripts/check-busybox-applets.sh" "$FAKE_BUSYBOX" cat sh mount

printf 'cat\nsh\n' > "$APPLET_LIST"
if AWEOS_TEST_BUSYBOX_APPLETS="$APPLET_LIST" \
    bash "$REPO_ROOT/scripts/check-busybox-applets.sh" "$FAKE_BUSYBOX" cat mount \
        >"$TEMP_ROOT/missing-applet.out" 2>&1; then
    echo "ERROR: BusyBox applet validation accepted a missing applet." >&2
    exit 1
fi
grep -Fq 'missing required applet: mount' "$TEMP_ROOT/missing-applet.out"

if AWEOS_TEST_BUSYBOX_APPLETS="$APPLET_LIST" AWEOS_TEST_BUSYBOX_FAIL=1 \
    bash "$REPO_ROOT/scripts/check-busybox-applets.sh" "$FAKE_BUSYBOX" cat \
        >"$TEMP_ROOT/failed-list.out" 2>&1; then
    echo "ERROR: BusyBox applet validation accepted a failed --list command." >&2
    exit 1
fi
grep -Fq 'could not list applets' "$TEMP_ROOT/failed-list.out"
