#!/bin/sh
# AWEOS Package Manager (awepkg)
#
# Packages are gzip-compressed tar archives containing manifest.meta and an
# optional root/ payload.  Keep all writes rooted below ROOT_DIR so the same
# program can be exercised safely against a staging root during image builds.
set -eu

ROOT_DIR="${AWEPKG_ROOT:-/}"
DB_DIR="${AWEPKG_DB_DIR:-${ROOT_DIR%/}/var/lib/awepkg}"

fail() {
    echo "Error: $*" >&2
    exit 1
}

package_name_is_safe() {
    printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$'
}

require_safe_package_name() {
    package_name_is_safe "$1" || fail "invalid package name '$1'"
}

validate_archive_layout() {
    archive="$1"
    tar -tzf "$archive" >/dev/null 2>&1 || fail "failed to read package archive $archive"

    # Reject absolute paths, parent traversal and anything outside the small
    # package format.  The payload deliberately excludes symlinks and special
    # files: a package must not be able to redirect an install outside ROOT_DIR.
    tar -tzf "$archive" | while IFS= read -r entry; do
        case "$entry" in
            manifest.meta|root/|root/*) ;;
            *) exit 1 ;;
        esac
        case "$entry" in
            /*|*'/../'*|../*|*'/..') exit 1 ;;
        esac
    done || fail "package contains an unsafe path"

    manifest_count=$(tar -tzf "$archive" | grep -cx 'manifest.meta' || true)
    [ "$manifest_count" -eq 1 ] || fail "package must contain exactly one manifest.meta"
}

read_manifest_value() {
    key="$1"
    manifest="$2"
    value=$(awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); count++ } END { if (count != 1) exit 1 }' "$manifest") \
        || fail "manifest must contain exactly one ${key}= entry"
    [ -n "$value" ] || fail "manifest ${key} must not be empty"
    printf '%s\n' "$value"
}

mkdir -p "$DB_DIR" 2>/dev/null || fail "cannot create package database $DB_DIR"

CMD="${1:-help}"
ARG="${2:-}"

case "$CMD" in
    list)
        echo "========================================"
        echo "        AWEOS Installed Packages        "
        echo "========================================"
        FOUND=0
        for meta in "$DB_DIR"/*.meta; do
            if [ -f "$meta" ]; then
                PKG_NAME=$(read_manifest_value PKG_NAME "$meta")
                PKG_VER=$(read_manifest_value PKG_VER "$meta")
                PKG_DESC=$(awk -F= '$1 == "PKG_DESC" { print substr($0, 10); exit }' "$meta")
                printf "  %-15s %-10s - %s\n" "$PKG_NAME" "$PKG_VER" "${PKG_DESC:-No description}"
                FOUND=1
            fi
        done
        [ "$FOUND" -eq 1 ] || echo "No packages currently installed."
        echo "========================================"
        ;;

    info)
        [ -n "$ARG" ] || fail "usage: awepkg info <package_name>"
        require_safe_package_name "$ARG"
        META_FILE="$DB_DIR/${ARG}.meta"
        [ -f "$META_FILE" ] || fail "package '$ARG' is not installed"
        cat "$META_FILE"
        ;;

    install)
        [ -n "$ARG" ] && [ -f "$ARG" ] || fail "usage: awepkg install <package_file.awe>"
        validate_archive_layout "$ARG"

        TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/awepkg-install.XXXXXX") || fail "cannot create temporary directory"
        trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
        tar -xzf "$ARG" -C "$TMP_DIR" --no-same-owner --no-same-permissions || fail "failed to unpack package"
        [ -f "$TMP_DIR/manifest.meta" ] && [ ! -L "$TMP_DIR/manifest.meta" ] || fail "invalid package: manifest is not a regular file"

        PKG_NAME=$(read_manifest_value PKG_NAME "$TMP_DIR/manifest.meta")
        PKG_VER=$(read_manifest_value PKG_VER "$TMP_DIR/manifest.meta")
        require_safe_package_name "$PKG_NAME"

        if [ -d "$TMP_DIR/root" ]; then
            find "$TMP_DIR/root" -type l -print -quit | grep -q . && fail "package payload must not contain symlinks"
            find "$TMP_DIR/root" ! -type d ! -type f -print -quit | grep -q . && fail "package payload contains an unsupported file type"
        fi

        echo "Installing package '$PKG_NAME' version '$PKG_VER'..."
        FILES_TMP="$DB_DIR/.${PKG_NAME}.files.$$"
        META_TMP="$DB_DIR/.${PKG_NAME}.meta.$$"
        if [ -d "$TMP_DIR/root" ]; then
            (cd "$TMP_DIR/root" && find . -type f -printf '%P\n' | sort) > "$FILES_TMP"
            cp -a "$TMP_DIR/root/." "$ROOT_DIR/" || fail "failed to install package payload"
        else
            : > "$FILES_TMP"
        fi
        cp "$TMP_DIR/manifest.meta" "$META_TMP"
        mv -f "$FILES_TMP" "$DB_DIR/${PKG_NAME}.files"
        mv -f "$META_TMP" "$DB_DIR/${PKG_NAME}.meta"
        trap - EXIT HUP INT TERM
        rm -rf "$TMP_DIR"
        echo "Successfully installed $PKG_NAME v$PKG_VER."
        ;;

    remove)
        [ -n "$ARG" ] || fail "usage: awepkg remove <package_name>"
        require_safe_package_name "$ARG"
        [ "$ARG" != "base-system" ] || fail "base-system is protected and cannot be removed"
        META_FILE="$DB_DIR/${ARG}.meta"
        FILES_LIST="$DB_DIR/${ARG}.files"
        [ -f "$META_FILE" ] || fail "package '$ARG' is not installed"

        echo "Removing package '$ARG'..."
        if [ -f "$FILES_LIST" ]; then
            while IFS= read -r file; do
                [ -z "$file" ] && continue
                case "$file" in /*|*'/../'*|../*|*'/..') fail "unsafe file record for $ARG" ;; esac
                rm -f "${ROOT_DIR%/}/$file"
            done < "$FILES_LIST"
            rm -f "$FILES_LIST"
        fi
        rm -f "$META_FILE"
        echo "Successfully removed $ARG."
        ;;

    help|--help|-h)
        echo "AWEOS Package Manager (awepkg) v1.1.0"
        echo "Usage: awepkg {list|info|install|remove|help} [target]"
        ;;

    *) fail "unknown command '$CMD' (run: awepkg help)" ;;
esac
