#!/bin/sh
# AWEOS Package Manager (awepkg)
# Packages are gzip-compressed tar archives containing manifest.meta and an
# optional root/ payload. Package payload files are installed only into vacant,
# non-symlink paths below ROOT_DIR. Removal is hash-checked to protect local edits.
set -eu

fail() {
    echo "Error: $*" >&2
    exit 1
}

ROOT_DIR="${AWEPKG_ROOT:-/}"
case "$ROOT_DIR" in /*) ;; *) fail "AWEPKG_ROOT must be an absolute path" ;; esac
[ -d "$ROOT_DIR" ] || fail "root directory does not exist: $ROOT_DIR"
ROOT_DIR=$(CDPATH= cd -P "$ROOT_DIR" && pwd) || fail "cannot resolve root directory"

DB_DIR="${AWEPKG_DB_DIR:-${ROOT_DIR%/}/var/lib/awepkg}"
case "$DB_DIR" in /*) ;; *) fail "AWEPKG_DB_DIR must be an absolute path" ;; esac
mkdir -p "$DB_DIR" 2>/dev/null || fail "cannot create package database $DB_DIR"
[ -d "$DB_DIR" ] && [ ! -L "$DB_DIR" ] || fail "package database must be a real directory"

package_name_is_safe() {
    printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$'
}

require_safe_package_name() {
    package_name_is_safe "$1" || fail "invalid package name '$1'"
}

validate_relative_path() {
    relative="$1"
    case "$relative" in ""|/*) fail "package file path must be relative" ;; esac
    case "$relative" in *[!A-Za-z0-9._+/-]*) fail "unsupported characters in package path '$relative'" ;; esac

    rest="$relative"
    while :; do
        component="${rest%%/*}"
        case "$component" in ""|"."|"..") fail "unsafe package path '$relative'" ;; esac
        [ "$rest" = "$component" ] && break
        rest="${rest#*/}"
    done
}

# Walk every existing parent component and reject symlinks. The final path is
# required to be vacant during install and a regular file (or absent) on remove.
validate_rooted_target() {
    relative="$1"
    mode="$2"
    validate_relative_path "$relative"

    current="$ROOT_DIR"
    rest="$relative"
    while [ "${rest#*/}" != "$rest" ]; do
        component="${rest%%/*}"
        rest="${rest#*/}"
        current="${current%/}/$component"
        [ ! -L "$current" ] || fail "target path traverses a symlink: '$relative'"
        if [ -e "$current" ] && [ ! -d "$current" ]; then
            fail "target parent is not a directory: '$current'"
        fi
    done

    target="${current%/}/$rest"
    [ ! -L "$target" ] || fail "target is a symlink; refusing package operation: '$relative'"
    if [ "$mode" = install ]; then
        [ ! -e "$target" ] || fail "refusing to overwrite existing file: '$relative'"
    elif [ -e "$target" ] && [ ! -f "$target" ]; then
        fail "installed path is no longer a regular file: '$relative'"
    fi
}

validate_install_targets() {
    files_list="$1"
    while IFS= read -r relative; do
        [ -n "$relative" ] || continue
        validate_rooted_target "$relative" install
    done < "$files_list"
}

validate_archive_layout() {
    archive="$1"
    tar -tzf "$archive" >/dev/null 2>&1 || fail "failed to read package archive $archive"

    tar -tzf "$archive" | while IFS= read -r entry; do
        case "$entry" in
            manifest.meta|root/|root/*) ;;
            *) exit 1 ;;
        esac
        case "$entry" in
            /*|*'/../'*|../*|*'/..'|*'/./'*|./*) exit 1 ;;
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

CMD="${1:-help}"
ARG="${2:-}"

case "$CMD" in
    list)
        echo "========================================"
        echo "        AWEOS Installed Packages        "
        echo "========================================"
        FOUND=0
        for meta in "$DB_DIR"/*.meta; do
            if [ -f "$meta" ] && [ ! -L "$meta" ]; then
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
        [ -f "$META_FILE" ] && [ ! -L "$META_FILE" ] || fail "package '$ARG' is not installed"
        cat "$META_FILE"
        ;;

    install)
        [ -n "$ARG" ] && [ -f "$ARG" ] || fail "usage: awepkg install <package_file.awe>"
        validate_archive_layout "$ARG"

        TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/awepkg-install.XXXXXX") || fail "cannot create temporary directory"
        FILES_LIST_TMP="$TMP_DIR/files.list"
        FILES_TMP=""
        HASHES_TMP=""
        META_TMP=""
        trap 'rm -rf -- "$TMP_DIR"; [ -z "${FILES_TMP:-}" ] || rm -f -- "$FILES_TMP"; [ -z "${HASHES_TMP:-}" ] || rm -f -- "$HASHES_TMP"; [ -z "${META_TMP:-}" ] || rm -f -- "$META_TMP"' EXIT HUP INT TERM

        tar -xzf "$ARG" -C "$TMP_DIR" --no-same-owner --no-same-permissions || fail "failed to unpack package"
        [ -f "$TMP_DIR/manifest.meta" ] && [ ! -L "$TMP_DIR/manifest.meta" ] || fail "invalid package: manifest is not a regular file"

        PKG_NAME=$(read_manifest_value PKG_NAME "$TMP_DIR/manifest.meta")
        PKG_VER=$(read_manifest_value PKG_VER "$TMP_DIR/manifest.meta")
        require_safe_package_name "$PKG_NAME"

        for suffix in meta files sha256; do
            db_file="$DB_DIR/${PKG_NAME}.${suffix}"
            [ ! -e "$db_file" ] && [ ! -L "$db_file" ] || fail "package '$PKG_NAME' is already installed or has stale database files"
        done

        if [ -e "$TMP_DIR/root" ] || [ -L "$TMP_DIR/root" ]; then
            [ -d "$TMP_DIR/root" ] && [ ! -L "$TMP_DIR/root" ] || fail "package root payload must be a real directory"
            find "$TMP_DIR/root" -type l -print -quit | grep -q . && fail "package payload must not contain symlinks"
            find "$TMP_DIR/root" ! -type d ! -type f -print -quit | grep -q . && fail "package payload contains an unsupported file type"

            # The ownership database is line-delimited; reject newline-bearing
            # names before generating it so removal can never target a different path.
            newline_count=$(find "$TMP_DIR/root" -type f -print0 | LC_ALL=C tr -cd '\n' | wc -c)
            [ "$newline_count" -eq 0 ] || fail "package paths must not contain newline characters"
            (cd "$TMP_DIR/root" && find . -type f -printf '%P\n' | LC_ALL=C sort) > "$FILES_LIST_TMP"
        else
            : > "$FILES_LIST_TMP"
        fi

        validate_install_targets "$FILES_LIST_TMP"
        echo "Installing package '$PKG_NAME' version '$PKG_VER'..."
        if [ -d "$TMP_DIR/root" ]; then
            cp -a "$TMP_DIR/root/." "$ROOT_DIR/" || fail "failed to install package payload"
        fi

        FILES_TMP="$DB_DIR/.${PKG_NAME}.files.$$"
        HASHES_TMP="$DB_DIR/.${PKG_NAME}.sha256.$$"
        META_TMP="$DB_DIR/.${PKG_NAME}.meta.$$"
        cp "$FILES_LIST_TMP" "$FILES_TMP"
        : > "$HASHES_TMP"
        while IFS= read -r file; do
            [ -n "$file" ] || continue
            target="${ROOT_DIR%/}/$file"
            [ -f "$target" ] && [ ! -L "$target" ] || fail "installed payload file is missing or unsafe: '$file'"
            hash=$(sha256sum < "$target") || fail "cannot hash installed file '$file'"
            hash="${hash%% *}"
            [ "${#hash}" -eq 64 ] || fail "invalid SHA-256 result for '$file'"
            printf '%s\n' "$hash" >> "$HASHES_TMP"
        done < "$FILES_LIST_TMP"
        cp "$TMP_DIR/manifest.meta" "$META_TMP"

        mv "$FILES_TMP" "$DB_DIR/${PKG_NAME}.files" || fail "cannot commit package file list"
        mv "$HASHES_TMP" "$DB_DIR/${PKG_NAME}.sha256" || {
            rm -f -- "$DB_DIR/${PKG_NAME}.files"
            fail "cannot commit package hashes"
        }
        mv "$META_TMP" "$DB_DIR/${PKG_NAME}.meta" || {
            rm -f -- "$DB_DIR/${PKG_NAME}.files" "$DB_DIR/${PKG_NAME}.sha256"
            fail "cannot commit package metadata"
        }
        trap - EXIT HUP INT TERM
        rm -rf -- "$TMP_DIR"
        echo "Successfully installed $PKG_NAME v$PKG_VER."
        ;;

    remove)
        [ -n "$ARG" ] || fail "usage: awepkg remove <package_name>"
        require_safe_package_name "$ARG"
        [ "$ARG" != "base-system" ] || fail "base-system is protected and cannot be removed"

        META_FILE="$DB_DIR/${ARG}.meta"
        FILES_LIST="$DB_DIR/${ARG}.files"
        HASHES_FILE="$DB_DIR/${ARG}.sha256"
        [ -f "$META_FILE" ] && [ ! -L "$META_FILE" ] || fail "package '$ARG' is not installed"
        [ -f "$FILES_LIST" ] && [ ! -L "$FILES_LIST" ] || fail "package '$ARG' has no safe file ownership list"
        [ -f "$HASHES_FILE" ] && [ ! -L "$HASHES_FILE" ] || fail "package '$ARG' has no integrity hashes; refusing removal"

        file_count=$(wc -l < "$FILES_LIST")
        hash_count=$(wc -l < "$HASHES_FILE")
        [ "$file_count" -eq "$hash_count" ] || fail "package '$ARG' ownership and hash records do not match"

        echo "Removing package '$ARG'..."
        # Validate every path and hash before deleting anything. Locally edited
        # or replaced files are left untouched and keep the package registered.
        exec 3< "$FILES_LIST"
        exec 4< "$HASHES_FILE"
        while IFS= read -r file <&3; do
            IFS= read -r expected_hash <&4 || fail "missing integrity hash for '$file'"
            validate_rooted_target "$file" remove
            target="${ROOT_DIR%/}/$file"
            if [ -e "$target" ]; then
                actual_hash=$(sha256sum < "$target") || fail "cannot hash installed file '$file'"
                actual_hash="${actual_hash%% *}"
                [ "$actual_hash" = "$expected_hash" ] || fail "file '$file' was modified; refusing to delete user data"
            fi
        done
        exec 3<&-
        exec 4<&-

        while IFS= read -r file; do
            [ -n "$file" ] || continue
            validate_rooted_target "$file" remove
            target="${ROOT_DIR%/}/$file"
            [ ! -e "$target" ] || rm -f -- "$target" || fail "cannot remove installed file '$file'"
        done < "$FILES_LIST"

        rm -f -- "$FILES_LIST" "$HASHES_FILE" "$META_FILE"
        echo "Successfully removed $ARG."
        ;;

    help|--help|-h)
        echo "AWEOS Package Manager (awepkg) v1.2.0"
        echo "Usage: awepkg {list|info|install|remove|help} [target]"
        ;;

    *) fail "unknown command '$CMD' (run: awepkg help)" ;;
esac
