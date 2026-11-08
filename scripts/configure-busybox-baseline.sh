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
        sed -i "s/^${symbol}=.*/$replacement/" "$CONFIG"
    elif grep -qx "# ${symbol} is not set" "$CONFIG"; then
        if [[ "$value" == y ]]; then
            sed -i "s/^# ${symbol} is not set$/$replacement/" "$CONFIG"
        fi
    else
        printf '
%s
' "$replacement" >> "$CONFIG"
    fi
}

# AWEOS needs the core networking applets but does not use BusyBox's optional
# tc command. Its legacy CBQ parser no longer builds against Linux UAPI
# headers >= 6.8 (TCA_CBQ_* / tc_cbq_* were removed). Buildroot disabled this
# applet for the same upstream compatibility reason.
set_bool_config CONFIG_STATIC y
set_bool_config CONFIG_TC n
set_bool_config CONFIG_FEATURE_TC_INGRESS n

# BusyBox's default configuration enables hardware-accelerated SHA1/SHA256
# (CONFIG_SHA1_HWACCEL / CONFIG_SHA256_HWACCEL, both default y). On x86 those
# implementations are hand-written assembly sources
# (libbb/hash_sha1_hwaccel_x86-64.S, libbb/hash_sha256_hwaccel_x86-64.S) that
# use SHA-NI and SSSE3/SSE4.1 instructions (pshufb, palignr, pinsrd,
# sha256rnds2, ...). Compiler flags such as -march=x86-64 cannot restrict
# hand-written assembly, and BusyBox adds those objects to lib-y on x86-64
# unconditionally, so the default build links post-baseline instructions into
# the bootstrap binary and the qemu64 ISA scan correctly rejects it. They are
# dispatched at runtime through CPUID, but the AWEOS bootstrap contract
# requires a static x86-64-v1 baseline ELF with no post-baseline instructions
# at all, so the hardware-accelerated hashing paths must be disabled.
# The portable generic SHA1/SHA256 implementations remain enabled; the
# required applet set (sha256sum, sha1sum, crypt, etc.) is unchanged.
set_bool_config CONFIG_SHA1_HWACCEL n
set_bool_config CONFIG_SHA256_HWACCEL n

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
grep -qx '# CONFIG_SHA1_HWACCEL is not set' "$CONFIG" || {
    echo "ERROR: BusyBox SHA1 hardware acceleration is still enabled; the bootstrap binary must stay on the x86-64 baseline." >&2
    exit 1
}
grep -qx '# CONFIG_SHA256_HWACCEL is not set' "$CONFIG" || {
    echo "ERROR: BusyBox SHA256 hardware acceleration is still enabled; the bootstrap binary must stay on the x86-64 baseline." >&2
    exit 1
}

echo "PASS: BusyBox static baseline configured; unsupported tc applet and SHA hardware acceleration disabled."
