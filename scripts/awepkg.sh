#!/bin/sh
# Safe compatibility wrapper for the native AOSIN package manager.
# The legacy tar-based .awe installer is intentionally disabled: it copied
# untrusted paths into / and trusted a mutable removal list.
set -eu

DB_DIR="${AWEOS_AWEPKG_DB_DIR:-/var/lib/awepkg}"
CMD="${1:-help}"
ARG="${2:-}"
INSTALL_ROOT="${AWEOS_INSTALL_ROOT:-/}"

valid_package_name() {
    case "$1" in
        ""|.|..|*[!A-Za-z0-9._+-]*) return 1 ;;
        *) return 0 ;;
    esac
}

show_help() {
    echo "AWEOS package manager compatibility wrapper"
    echo "Usage: awepkg {list|info|install|remove|help} [package]"
    echo "Install/remove use the native AOSIN v2 CLI; legacy .awe tar installs are disabled."
}

case "$CMD" in
    list)
        found=0
        for meta in "$DB_DIR"/*.meta; do
            [ -f "$meta" ] || continue
            if grep -q '^PKG_NAME=' "$meta"; then
                name="$(sed -n 's/^PKG_NAME=//p' "$meta" | sed -n '1p')"
                version="$(sed -n 's/^PKG_VER=//p' "$meta" | sed -n '1p')"
            else
                name="$(sed -n '1p' "$meta")"
                version="$(sed -n '2p' "$meta")"
            fi
            [ -n "$name" ] || continue
            printf '%-24s %s\n' "$name" "${version:-unknown}"
            found=1
        done
        [ "$found" -eq 1 ] || echo "No packages currently installed."
        ;;
    info)
        valid_package_name "$ARG" || { echo "Error: invalid package name." >&2; exit 2; }
        META_FILE="$DB_DIR/$ARG.meta"
        [ -f "$META_FILE" ] || { echo "Error: package '$ARG' is not installed." >&2; exit 1; }
        cat "$META_FILE"
        ;;
    install)
        [ -n "$ARG" ] && [ -f "$ARG" ] || { echo "Usage: awepkg install <package.asp>" >&2; exit 2; }
        command -v aosin >/dev/null 2>&1 || {
            echo "Error: native aosin CLI is unavailable; legacy tar installation is disabled." >&2
            exit 2
        }
        exec aosin install "$ARG" "$INSTALL_ROOT"
        ;;
    remove)
        valid_package_name "$ARG" || { echo "Error: invalid package name." >&2; exit 2; }
        command -v aosin >/dev/null 2>&1 || {
            echo "Error: native aosin CLI is unavailable; legacy removal is disabled." >&2
            exit 2
        }
        exec aosin remove "$ARG" "$INSTALL_ROOT"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help >&2
        exit 2
        ;;
esac
