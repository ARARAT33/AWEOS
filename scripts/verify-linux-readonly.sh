#!/bin/bash
set -euo pipefail

LINUX_DIR="linux"

if [ ! -d "${LINUX_DIR}" ]; then
    echo "ERROR: ${LINUX_DIR} directory does not exist!" >&2
    exit 1
fi

if [ ! -f "${LINUX_DIR}/Makefile" ]; then
    echo "ERROR: ${LINUX_DIR}/Makefile does not exist!" >&2
    exit 1
fi

# Check git status for linux directory
MODIFIED_FILES=$(git status --porcelain -- "${LINUX_DIR}")
if [ -n "${MODIFIED_FILES}" ]; then
    echo "ERROR: /linux source directory has been modified!" >&2
    echo "${MODIFIED_FILES}" >&2
    exit 1
fi

echo "/linux: UNMODIFIED (Read-only integrity check PASSED)"
