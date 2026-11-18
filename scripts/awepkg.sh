#!/bin/sh
# AWEOS Package Manager (awepkg)
# Only read-only metadata queries are enabled until a signed, transactional
# package installation/removal backend is implemented.
set -eu

DB_DIR="${AWEOS_AWEPKG_DB_DIR:-/var/lib/awepkg}"
CMD="${1:-help}"
ARG="${2:-}"

valid_package_name() {
    case "$1" in
        ''|.*|*[!A-Za-z0-9+._-]*) return 1 ;;
        *) return 0 ;;
    esac
}

case "$CMD" in
    list)
        echo "========================================"
        echo "        AWEOS Installed Packages        "
        echo "========================================"
        FOUND=0
        for meta in "$DB_DIR"/*.meta; do
            if [ -f "$meta" ] && [ ! -L "$meta" ]; then
                PKG_NAME=$(grep "^PKG_NAME=" "$meta" | cut -d'=' -f2 || true)
                PKG_VER=$(grep "^PKG_VER=" "$meta" | cut -d'=' -f2 || true)
                PKG_DESC=$(grep "^PKG_DESC=" "$meta" | cut -d'=' -f2 || true)
                printf "  %-15s %-10s - %s\n" "$PKG_NAME" "$PKG_VER" "$PKG_DESC"
                FOUND=1
            fi
        done
        if [ "$FOUND" -eq 0 ]; then
            echo "No packages currently registered."
        fi
        echo "========================================"
        ;;

    info)
        if ! valid_package_name "$ARG"; then
            echo "ERROR: invalid package name." >&2
            exit 2
        fi
        META_FILE="$DB_DIR/$ARG.meta"
        if [ -f "$META_FILE" ] && [ ! -L "$META_FILE" ]; then
            cat "$META_FILE"
        else
            echo "ERROR: package '$ARG' is not registered." >&2
            exit 1
        fi
        ;;

    install)
        if [ -z "$ARG" ]; then
            echo "Usage: awepkg install <package_file>" >&2
            exit 2
        fi
        echo "ERROR: package installation is disabled. A signed format, safe archive-path validation, atomic staging and rollback are not implemented; no files were extracted or copied." >&2
        exit 1
        ;;

    remove)
        if ! valid_package_name "$ARG"; then
            echo "ERROR: invalid package name." >&2
            exit 2
        fi
        echo "ERROR: package removal is disabled. A verified ownership manifest and transactional uninstall backend are not implemented; no files or metadata were deleted." >&2
        exit 1
        ;;

    *)
        echo "AWEOS Package Manager (awepkg)"
        echo "Read-only commands: list, info <package_name>"
        echo "install/remove are disabled until package trust and rollback are implemented."
        ;;
esac
