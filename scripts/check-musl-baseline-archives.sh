#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <musl-lib-dir> <x86-64-isa-checker> <archive-checker>" >&2
    exit 2
fi

lib_dir="$1"
isa_checker="$2"
archive_checker="$3"

[ -d "$lib_dir" ] || { echo "ERROR: musl library directory is missing: $lib_dir" >&2; exit 2; }
[ -f "$isa_checker" ] || { echo "ERROR: ISA checker is missing: $isa_checker" >&2; exit 2; }
[ -f "$archive_checker" ] || { echo "ERROR: archive checker is missing: $archive_checker" >&2; exit 2; }

for tool in ar awk; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required musl archive inspection tool is missing: $tool" >&2
        exit 2
    }
done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/aweos-musl-archives.XXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT

shopt -s nullglob
archives=("$lib_dir"/*.a)
if [ "${#archives[@]}" -eq 0 ]; then
    echo "ERROR: no static musl archives found in $lib_dir." >&2
    exit 1
fi

# musl intentionally ships these compatibility archives empty: their APIs
# are provided by libc.a. Only these exact names may be empty; every other
# archive must contain members and pass the ordinary ISA scanner.
verified=0
empty_compat=0
libc_verified=0
for archive in "${archives[@]}"; do
    [ -s "$archive" ] || {
        echo "ERROR: musl archive is missing or zero bytes: $archive" >&2
        exit 1
    }

    members_file="$work_dir/$(basename -- "$archive").members"
    if ! ar t "$archive" >"$members_file"; then
        echo "ERROR: could not list musl archive members: $archive" >&2
        exit 1
    fi
    member_count="$(awk 'NF { count++ } END { print count + 0 }' "$members_file")"

    if [ "$member_count" -eq 0 ]; then
        case "$(basename -- "$archive")" in
            libm.a|librt.a|libpthread.a|libcrypt.a|libutil.a|libxnet.a|libresolv.a|libdl.a)
                echo "PASS: $(basename -- "$archive") is an intentionally empty musl compatibility archive; implementation is in libc.a."
                empty_compat=$((empty_compat + 1))
                continue
                ;;
            *)
                echo "ERROR: unexpected empty musl archive is not on the compatibility allowlist: $archive" >&2
                exit 1
                ;;
        esac
    fi

    if ! bash "$archive_checker" "$archive" "$isa_checker"; then
        echo "ERROR: musl archive failed x86-64 baseline verification: $archive" >&2
        exit 1
    fi
    verified=$((verified + 1))
    if [ "$(basename -- "$archive")" = "libc.a" ]; then
        libc_verified=1
    fi
done

if [ "$libc_verified" -ne 1 ]; then
    echo "ERROR: musl libc.a is missing or contains no members; the primary C library was not verified." >&2
    exit 1
fi

echo "PASS: verified $verified non-empty musl archives and accepted $empty_compat allowlisted empty compatibility archives."
