#!/bin/sh
# AWEOS Package Manager (awepkg)

DB_DIR="/var/lib/awepkg"
mkdir -p "$DB_DIR" 2>/dev/null || true

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
                PKG_NAME=$(grep "^PKG_NAME=" "$meta" | cut -d'=' -f2)
                PKG_VER=$(grep "^PKG_VER=" "$meta" | cut -d'=' -f2)
                PKG_DESC=$(grep "^PKG_DESC=" "$meta" | cut -d'=' -f2)
                printf "  %-15s %-10s - %s\n" "$PKG_NAME" "$PKG_VER" "$PKG_DESC"
                FOUND=1
            fi
        done
        if [ "$FOUND" -eq 0 ]; then
            echo "No packages currently installed."
        fi
        echo "========================================"
        ;;

    info)
        if [ -z "$ARG" ]; then
            echo "Usage: awepkg info <package_name>"
            exit 1
        fi
        META_FILE="$DB_DIR/${ARG}.meta"
        if [ -f "$META_FILE" ]; then
            cat "$META_FILE"
        else
            echo "Error: Package '$ARG' is not installed."
            exit 1
        fi
        ;;

    install)
        if [ -z "$ARG" ] || [ ! -f "$ARG" ]; then
            echo "Usage: awepkg install <package_file.awe>"
            exit 1
        fi

        TMP_DIR="/tmp/awepkg_install_$$"
        mkdir -p "$TMP_DIR"

        if ! tar -xzf "$ARG" -C "$TMP_DIR" 2>/dev/null; then
            echo "Error: Failed to unpack package $ARG"
            rm -rf "$TMP_DIR"
            exit 1
        fi

        if [ ! -f "$TMP_DIR/manifest.meta" ]; then
            echo "Error: Invalid .awe package: missing manifest.meta"
            rm -rf "$TMP_DIR"
            exit 1
        fi

        PKG_NAME=$(grep "^PKG_NAME=" "$TMP_DIR/manifest.meta" | cut -d'=' -f2)
        PKG_VER=$(grep "^PKG_VER=" "$TMP_DIR/manifest.meta" | cut -d'=' -f2)

        echo "Installing package '$PKG_NAME' version '$PKG_VER'..."

        # Copy payload files to system root /
        if [ -d "$TMP_DIR/root" ]; then
            ( cd "$TMP_DIR/root" && find . -type f ) > "$DB_DIR/${PKG_NAME}.files"
            cp -rf "$TMP_DIR/root/"* / 2>/dev/null || true
        fi

        cp "$TMP_DIR/manifest.meta" "$DB_DIR/${PKG_NAME}.meta"
        rm -rf "$TMP_DIR"
        echo "Successfully installed $PKG_NAME v$PKG_VER."
        ;;

    remove)
        if [ -z "$ARG" ]; then
            echo "Usage: awepkg remove <package_name>"
            exit 1
        fi

        META_FILE="$DB_DIR/${ARG}.meta"
        FILES_LIST="$DB_DIR/${ARG}.files"

        if [ ! -f "$META_FILE" ]; then
            echo "Error: Package '$ARG' is not installed."
            exit 1
        fi

        echo "Removing package '$ARG'..."

        if [ -f "$FILES_LIST" ]; then
            while read -r file; do
                [ -n "$file" ] && rm -f "/$file" 2>/dev/null || true
            done < "$FILES_LIST"
            rm -f "$FILES_LIST"
        fi

        rm -f "$META_FILE"
        echo "Successfully removed package '$ARG'."
        ;;

    *)
        echo "AWEOS Package Manager (awepkg) v1.0.0"
        echo "Usage: awepkg {list|info|install|remove|help} [target]"
        ;;
esac
