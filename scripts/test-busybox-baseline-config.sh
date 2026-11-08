#!/usr/bin/env bash
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
grep -qx 'CONFIG_ROUTE=y' "$SOURCE_DIR/.config"

cp "$SOURCE_DIR/.config" "$TEMP_ROOT/first.config"
PATH="$FAKE_BIN:$PATH" bash "$REPO_ROOT/scripts/configure-busybox-baseline.sh" "$SOURCE_DIR"
cmp -s "$TEMP_ROOT/first.config" "$SOURCE_DIR/.config"

echo "PASS: BusyBox baseline configuration is safe, deterministic, and idempotent."
