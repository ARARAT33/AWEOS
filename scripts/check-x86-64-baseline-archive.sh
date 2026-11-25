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
for tool in ar sort uniq awk; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required archive-scan tool is missing: $tool" >&2
        exit 2
    }
done

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

duplicates="$(LC_ALL=C sort "$members_file" | uniq -d)"
if [ -n "$duplicates" ]; then
    echo "ERROR: duplicate archive member names cannot be verified unambiguously in $archive:" >&2
    printf '%s\n' "$duplicates" >&2
    exit 1
fi

scanned=0
while IFS= read -r member || [ -n "$member" ]; do
    [ -n "$member" ] || continue
    object="$work_dir/member-$scanned.elf"
    if ! ar p "$archive" "$member" >"$object"; then
        echo "ERROR: could not extract archive member '$member' from $archive" >&2
        exit 1
    fi
    if [ ! -s "$object" ]; then
        echo "ERROR: archive member '$member' is empty in $archive" >&2
        exit 1
    fi
    if ! bash "$checker" "$object" >"$work_dir/check.log" 2>&1; then
        echo "ERROR: baseline-unsafe or invalid archive member '$member' in $archive" >&2
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
