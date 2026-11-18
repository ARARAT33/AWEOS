#!/usr/bin/env bash
# Fail-closed policy for automatically merging AWEOS branch integration PRs.
# Only source paths with an explicit, relevant GitHub Actions validation gate
# may be auto-merged. Workflow, documentation, kernel-source and unknown paths
# require manual review.
set -euo pipefail

fail() {
    printf 'BLOCKED: %s\n' "$*" >&2
    exit 1
}

if [[ $# -ne 2 ]]; then
    fail "usage: $0 <changed-files-list> <checks-json>"
fi

files_file="$1"
checks_file="$2"
[[ -f "$files_file" ]] || fail "changed-files list is missing"
[[ -f "$checks_file" ]] || fail "checks JSON is missing"
command -v jq >/dev/null 2>&1 || fail "jq is required to validate check results"
jq -e 'type == "array"' "$checks_file" >/dev/null 2>&1 || fail "checks JSON must be an array"

# Every changed path must be covered. A single uncovered path blocks the PR.
declare -A required_checks=()
seen_file=0
while IFS= read -r path || [[ -n "$path" ]]; do
    [[ -n "$path" ]] || continue
    seen_file=1

    case "$path" in
        .github/*|linux/*|docs/*|README*|*.md|*.yml|*.yaml|.gitignore|Cargo.lock)
            fail "manual review required for unverified path: $path"
            ;;
        AWEUI/*|APPS/*|scripts/*|Cargo.toml|Makefile)
            required_checks[userland]=1
            required_checks[build-and-boot-test]=1
            ;;
        src/core/*|src/installer/*|src/updater/*)
            required_checks[userland]=1
            required_checks[build-and-boot-test]=1
            required_checks[archive-regression]=1
            ;;
        Bootloader/*|limine.conf)
            required_checks[build-and-boot-test]=1
            ;;
        *)
            fail "no automated validation mapping for changed path: $path"
            ;;
    esac
done < "$files_file"

[[ "$seen_file" == "1" ]] || fail "PR contains no changed files; refusing automatic merge"

# Do not trust a green subset: every reported check must be completed successfully.
if ! jq -e 'length > 0 and all(.[]; .state == "SUCCESS")' "$checks_file" >/dev/null; then
    fail "one or more reported checks are missing, pending, or unsuccessful"
fi

for check_name in "${!required_checks[@]}"; do
    count="$(jq --arg name "$check_name" '[.[] | select(.name == $name and .state == "SUCCESS")] | length' "$checks_file")"
    [[ "$count" -gt 0 ]] || fail "required successful check is missing: $check_name"
done

printf 'PASS: changed paths are covered by successful checks: '
printf '%s ' "${!required_checks[@]}"
printf '\n'
