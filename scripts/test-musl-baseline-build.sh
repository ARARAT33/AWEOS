#!/usr/bin/env bash
# Regression for scripts/build-musl-baseline.sh: required-tool gating,
# archive checksum verification, completed-install verification, and
# idempotent reuse of a finished baseline musl build. No network access,
# no real toolchain, and no real musl sources are needed: the build is
# exercised through the AWEOS_MUSL_TEST_TARBALL test hook with a synthetic
# musl source tree.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aweos-musl-baseline-test.XXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

MUSL_SCRIPT="$REPO_ROOT/scripts/build-musl-baseline.sh"
BUILD_DIR="$TEMP_ROOT/build"
FAKE_SRC="$TEMP_ROOT/musl-1.2.5"
TARBALL="$TEMP_ROOT/musl-1.2.5.tar.gz"
mkdir -p "$BUILD_DIR" "$FAKE_SRC"

cat > "$FAKE_SRC/configure" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
prefix=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix=*) prefix="${1#--prefix=}" ;;
        *) echo "ERROR: unexpected configure argument: $1" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$prefix" ] || { echo "ERROR: --prefix is required" >&2; exit 2; }
printf 'PREFIX = %s\n' "$prefix" > config.mak
EOF
chmod 0755 "$FAKE_SRC/configure"

cat > "$FAKE_SRC/Makefile" <<'EOF'
include config.mak

.PHONY: all install
all:
install:
	mkdir -p "$(PREFIX)/bin" "$(PREFIX)/lib" "$(PREFIX)/include"
	printf '#!/bin/sh\nexec "${REALGCC:-bash /nonexistent/cc-x86_64-baseline.sh}" "$@"\n' > "$(PREFIX)/bin/musl-gcc"
	chmod 0755 "$(PREFIX)/bin/musl-gcc"
	printf 'baseline synthetic libc\n' > "$(PREFIX)/lib/libc.a"
	printf '#include <stdio.h>\n' > "$(PREFIX)/include/stdio.h"
EOF

tar -czf "$TARBALL" -C "$TEMP_ROOT" musl-1.2.5
TEST_SHA256="$(sha256sum "$TARBALL" | awk '{print $1}')"
MISMATCH_SHA256="0000000000000000000000000000000000000000000000000000000000000000"

# 1. A missing required tool fails closed before any download.
FAKE_BIN="$TEMP_ROOT/fakebin"
mkdir -p "$FAKE_BIN"
for tool in bash env dirname basename sha256sum tar make mktemp rm grep mkdir chmod cp cat find ln realpath getconf cc awk sed touch sort head tail cut tr install; do
    command -v "$tool" >/dev/null 2>&1 || continue
    ln -s "$(command -v "$tool")" "$FAKE_BIN/$tool"
done
# curl is deliberately absent from FAKE_BIN.
if env -u AWEOS_MUSL_TEST_TARBALL -u AWEOS_MUSL_TEST_SHA256 \
    PATH="$FAKE_BIN" "$(command -v bash)" "$MUSL_SCRIPT" "$BUILD_DIR" \
    >"$TEMP_ROOT/missing-tool.out" 2>&1; then
    echo "ERROR: baseline musl build proceeded without a required tool." >&2
    exit 1
fi
grep -Fq 'curl is required to build the baseline musl' "$TEMP_ROOT/missing-tool.out"

# 2. A test tarball without its checksum fails closed.
if AWEOS_MUSL_TEST_TARBALL="$TARBALL" bash "$MUSL_SCRIPT" "$BUILD_DIR" \
    >"$TEMP_ROOT/missing-sha.out" 2>&1; then
    echo "ERROR: baseline musl build accepted a test tarball without a checksum." >&2
    exit 1
fi
grep -Fq 'AWEOS_MUSL_TEST_SHA256 must accompany AWEOS_MUSL_TEST_TARBALL' "$TEMP_ROOT/missing-sha.out"

# 3. A checksum mismatch fails closed.
if AWEOS_MUSL_TEST_TARBALL="$TARBALL" AWEOS_MUSL_TEST_SHA256="$MISMATCH_SHA256" \
    bash "$MUSL_SCRIPT" "$BUILD_DIR" >"$TEMP_ROOT/bad-sha.out" 2>&1; then
    echo "ERROR: baseline musl build accepted an unverified archive." >&2
    exit 1
fi
grep -Fq 'musl source archive SHA-256 mismatch' "$TEMP_ROOT/bad-sha.out"

# 4. A verified tarball builds and installs the baseline toolchain.
AWEOS_MUSL_TEST_TARBALL="$TARBALL" AWEOS_MUSL_TEST_SHA256="$TEST_SHA256" \
    bash "$MUSL_SCRIPT" "$BUILD_DIR" >"$TEMP_ROOT/build.out" 2>&1
grep -Fq 'PASS: baseline musl 1.2.5 installed' "$TEMP_ROOT/build.out"
MUSL_PREFIX="$BUILD_DIR/tools/musl"
[ -x "$MUSL_PREFIX/bin/musl-gcc" ]
# The installed wrapper must be valid shell: a rewrite that drops the closing
# brace of the REALGCC expansion would leave an unusable toolchain behind.
sh -n "$MUSL_PREFIX/bin/musl-gcc"
# The installed wrapper must no longer reference the configure-time policy
# wrapper; its REALGCC default must have been rewritten to the host compiler.
if grep -q 'cc-x86_64-baseline.sh' "$MUSL_PREFIX/bin/musl-gcc"; then
    echo "ERROR: the installed musl-gcc still references the baseline policy wrapper." >&2
    exit 1
fi
grep -Fq 'exec "${REALGCC:-cc}" "$@"' "$MUSL_PREFIX/bin/musl-gcc"
[ -s "$MUSL_PREFIX/lib/libc.a" ]
[ -f "$MUSL_PREFIX/include/stdio.h" ]
grep -qx '1.2.5 a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4' \
    "$MUSL_PREFIX/.aweos-musl-baseline"

# 5. A completed build is reused without re-downloading.
bash "$MUSL_SCRIPT" "$BUILD_DIR" >"$TEMP_ROOT/cache.out" 2>&1
grep -Fq 'PASS: cached baseline musl 1.2.5' "$TEMP_ROOT/cache.out"

echo "PASS: baseline musl build is pinned, verified, idempotent, and fail-closed."
