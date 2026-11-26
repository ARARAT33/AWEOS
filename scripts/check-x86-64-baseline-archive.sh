#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <archive.a> <x86-64-isa-checker>" >&2
    exit 2
fi

archive="$1"
checker="$2"
[ -s "$archive" ] || { echo "ERROR: archive is missing or empty: $archive" >&2; exit 2; }
[ -f "$checker" ] || { echo "ERROR: ISA checker is missing: $checker" >&2; exit 2; }
for tool in ar awk; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required archive-scan tool is missing: $tool" >&2
        exit 2
    }
done

# Resolve the archive before changing into per-member extraction directories.
archive_dir="$(cd -- "$(dirname -- "$archive")" && pwd -P)"
archive="$archive_dir/$(basename -- "$archive")"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/aweos-archive-isa.XXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT
members_file="$work_dir/members.txt"
if ! ar t "$archive" >"$members_file"; then
    echo "ERROR: could not list archive members: $archive" >&2
    exit 1
fi

member_count="$(awk 'NF { count++ } END { print count + 0 }' "$members_file")"
if [ "$member_count" -eq 0 ]; then
    echo "ERROR: archive contains no members: $archive" >&2
    exit 1
fi

# Archive member basenames are not necessarily unique (for example, several
# musl objects are named clone.lo). Track each occurrence independently and
# use GNU ar's xN modifier so no duplicate member is silently skipped.
declare -A occurrence_by_name=()
scanned=0
while IFS= read -r member || [ -n "$member" ]; do
    [ -n "$member" ] || continue
    case "$member" in
        .|..|*/*)
            echo "ERROR: unsafe archive member path cannot be extracted: '$member' in $archive" >&2
            exit 1
            ;;
    esac

    occurrence=$(( ${occurrence_by_name["$member"]:-0} + 1 ))
    occurrence_by_name["$member"]="$occurrence"
    member_dir="$work_dir/member-$scanned"
    mkdir "$member_dir"

    if ! (cd "$member_dir" && ar xN "$occurrence" "$archive" "$member"); then
        echo "ERROR: could not extract archive member '$member' occurrence #$occurrence from $archive (GNU ar xN is required)" >&2
        exit 1
    fi

    object="$member_dir/$member"
    if [ ! -s "$object" ]; then
        echo "ERROR: archive member '$member' occurrence #$occurrence is missing or empty in $archive" >&2
        exit 1
    fi
    if ! bash "$checker" "$object" >"$work_dir/check.log" 2>&1; then
        echo "ERROR: baseline-unsafe or invalid archive member '$member' occurrence #$occurrence in $archive" >&2
        cat "$work_dir/check.log" >&2
        exit 1
    fi
    scanned=$((scanned + 1))
done <"$members_file"

if [ "$scanned" -ne "$member_count" ]; then
    echo "ERROR: archive scan count mismatch for $archive: listed=$member_count scanned=$scanned" >&2
    exit 1
fi

echo "PASS: verified all $scanned archive members in $archive against the x86-64 baseline."
