#!/usr/bin/env bash
# Shared guard for AWEOS build output directories.
# Source this file; it deliberately does not change the caller's shell options.

AWEOS_BUILD_DIR_MARKER_CONTENT='AWEOS build directory v1'

aweos_resolve_build_dir() {
    local requested="${1:-}"
    local repo_root="${2:-}"
    local resolved linux_root

    if [[ -z "$requested" || -z "$repo_root" ]]; then
        echo "ERROR: build directory and repository root are required." >&2
        return 2
    fi
    command -v realpath >/dev/null 2>&1 || {
        echo "ERROR: realpath is required to validate the build directory." >&2
        return 1
    }

    repo_root="$(realpath -e -- "$repo_root")" || {
        echo "ERROR: cannot resolve repository root: $repo_root" >&2
        return 1
    }
    resolved="$(realpath -m -- "$requested")" || {
        echo "ERROR: cannot resolve build directory: $requested" >&2
        return 1
    }
    linux_root="$(realpath -m -- "$repo_root/linux")" || return 1

    if [[ "$resolved" == "/" || "$resolved" == "$repo_root" ]]; then
        echo "ERROR: refusing unsafe AWEOS build directory: $resolved" >&2
        return 1
    fi

    case "$resolved/" in
        "$linux_root/"*)
            echo "ERROR: build output must never be written inside the read-only /linux tree: $resolved" >&2
            return 1
            ;;
    esac

    case "$repo_root/" in
        "$resolved/"*)
            echo "ERROR: refusing a build directory that contains the repository: $resolved" >&2
            return 1
            ;;
    esac

    case "$resolved/" in
        "$repo_root/.git/"*|"$repo_root/.github/"*)
            echo "ERROR: refusing to use repository metadata or workflow files as build output: $resolved" >&2
            return 1
            ;;
    esac

    if [[ -L "$requested" ]]; then
        echo "ERROR: refusing a build directory supplied as a symlink: $requested" >&2
        return 1
    fi

    printf '%s\n' "$resolved"
}

aweos_prepare_build_dir() {
    local requested="${1:-}"
    local repo_root="${2:-}"
    local resolved marker existing marker_tmp

    resolved="$(aweos_resolve_build_dir "$requested" "$repo_root")" || return $?
    if [[ -e "$resolved" && ! -d "$resolved" ]]; then
        echo "ERROR: build directory exists but is not a directory: $resolved" >&2
        return 1
    fi
    mkdir -p -- "$resolved" || return 1

    marker="$resolved/.aweos-build-dir"
    if [[ -L "$marker" ]]; then
        echo "ERROR: refusing a symlinked build ownership marker: $marker" >&2
        return 1
    fi
    if [[ -e "$marker" ]]; then
        if [[ ! -f "$marker" || "$(cat -- "$marker")" != "$AWEOS_BUILD_DIR_MARKER_CONTENT" ]]; then
            echo "ERROR: invalid AWEOS build ownership marker: $marker" >&2
            return 1
        fi
    else
        existing="$(find "$resolved" -mindepth 1 -maxdepth 1 -print -quit)"
        if [[ -n "$existing" && "${AWEOS_ADOPT_BUILD_DIR:-0}" != "1" ]]; then
            echo "ERROR: refusing to adopt non-empty build directory '$resolved' implicitly." >&2
            echo "Inspect its contents, then set AWEOS_ADOPT_BUILD_DIR=1 once to mark it as AWEOS-owned." >&2
            return 1
        fi

        marker_tmp="$(mktemp "$resolved/.aweos-build-dir.tmp.XXXXXX")" || return 1
        printf '%s\n' "$AWEOS_BUILD_DIR_MARKER_CONTENT" > "$marker_tmp"
        chmod 0600 "$marker_tmp"
        if ! ln -- "$marker_tmp" "$marker" 2>/dev/null; then
            rm -f -- "$marker_tmp"
            if [[ ! -f "$marker" || "$(cat -- "$marker" 2>/dev/null || true)" != "$AWEOS_BUILD_DIR_MARKER_CONTENT" ]]; then
                echo "ERROR: could not create the AWEOS build ownership marker: $marker" >&2
                return 1
            fi
        else
            rm -f -- "$marker_tmp"
        fi
    fi

    printf '%s\n' "$resolved"
}

aweos_require_owned_build_dir() {
    local requested="${1:-}"
    local repo_root="${2:-}"
    local resolved marker

    resolved="$(aweos_resolve_build_dir "$requested" "$repo_root")" || return $?
    if [[ ! -d "$resolved" ]]; then
        echo "ERROR: AWEOS build directory does not exist: $resolved" >&2
        return 1
    fi

    marker="$resolved/.aweos-build-dir"
    if [[ -L "$marker" || ! -f "$marker" || "$(cat -- "$marker" 2>/dev/null || true)" != "$AWEOS_BUILD_DIR_MARKER_CONTENT" ]]; then
        echo "ERROR: refusing to clean an unmarked or untrusted directory: $resolved" >&2
        return 1
    fi

    printf '%s\n' "$resolved"
}

aweos_clean_build_dir() {
    local requested="${1:-}"
    local repo_root="${2:-}"
    local resolved

    resolved="$(aweos_require_owned_build_dir "$requested" "$repo_root")" || return $?
    rm -rf -- "$resolved"
    echo "Removed AWEOS-owned build directory: $resolved"
}
