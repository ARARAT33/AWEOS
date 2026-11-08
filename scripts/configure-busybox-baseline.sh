#!/usr/bin/env bash
# Apply the supported BusyBox configuration for AWEOS's x86-64 bootstrap.
set -euo pipefail

SOURCE_DIR="${1:-}"
if [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR" ]]; then
    echo "ERROR: a BusyBox source directory is required." >&2
    exit 2
fi
CONFIG="$SOURCE_DIR/.config"
if [[ ! -f "$CONFIG" ]]; then
    echo "ERROR: BusyBox configuration is missing: $CONFIG" >&2
    exit 2
fi

set_bool_config() {
    local symbol="$1"
    local value="$2"
    local replacement

    [[ "$symbol" =~ ^[A-Z0-9_]+$ ]] || {
        echo "ERROR: invalid BusyBox configuration symbol: $symbol" >&2
        return 2
    }

    case "$value" in
        y) replacement="${symbol}=y" ;;
        n) replacement="# ${symbol} is not set" ;;
        *)
            echo "ERROR: unsupported BusyBox boolean value for $symbol: $value" >&2
            return 2
            ;;
    esac

    if grep -q "^${symbol}=" "$CONFIG"; then
        sed -i "s/^${symbol}=.*/${replacement}/" "$CONFIG"
    elif grep -qx "# ${symbol} is not set" "$CONFIG"; then
        if [[ "$value" == y ]]; then
            sed -i "s/^# ${symbol} is not set$/${replacement}/" "$CONFIG"
        fi
    else
        printf '\n%s\n' "$replacement" >> "$CONFIG"
    fi
}

# AWEOS needs the core networking applets but does not use BusyBox's optional
# tc command. Its legacy CBQ parser no longer builds against Linux UAPI
# headers >= 6.8 (TCA_CBQ_* / tc_cbq_* were removed). Buildroot disabled this
# applet for the same upstream compatibility reason.
set_bool_config CONFIG_STATIC y
set_bool_config CONFIG_TC n
set_bool_config CONFIG_FEATURE_TC_INGRESS n

# Regenerate BusyBox's derived configuration headers before compiling.
make -C "$SOURCE_DIR" oldconfig </dev/null

grep -qx 'CONFIG_STATIC=y' "$CONFIG" || {
    echo "ERROR: BusyBox static linking is not enabled after oldconfig." >&2
    exit 1
}
grep -qx '# CONFIG_TC is not set' "$CONFIG" || {
    echo "ERROR: incompatible BusyBox tc applet is still enabled." >&2
    exit 1
}
grep -qx '# CONFIG_FEATURE_TC_INGRESS is not set' "$CONFIG" || {
    echo "ERROR: BusyBox tc ingress support is still enabled." >&2
    exit 1
}

echo "PASS: BusyBox static baseline configured; unsupported tc applet disabled."
