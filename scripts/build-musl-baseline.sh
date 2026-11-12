#!/usr/bin/env bash
# Build a pinned musl libc from source under the enforced x86-64-v1 policy.
#
# The distribution musl-tools packages on current runners are built for newer
# x86-64 microarchitecture levels (AVX/BMI/MOVBE, i.e. x86-64-v3). Those
# prebuilt archives are linked verbatim into the static BusyBox bootstrap
# binary and violate AWEOS's qemu64/x86-64 baseline contract. This script
# downloads a SHA-256-pinned musl release, compiles it through the same
# cc-x86_64-baseline.sh policy wrapper used for BusyBox, and installs it under
# the build tools directory so the bootstrap link consumes baseline-only
# libc and crt objects.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
source "$SCRIPT_DIR/lib/build-safety.sh"

BUILD_DIR="$(aweos_prepare_build_dir "${1:-build}" "$REPO_ROOT")"
VERSION="1.2.5"
ARCHIVE="musl-${VERSION}.tar.gz"
URL="https://musl.libc.org/releases/${ARCHIVE}"
# Pinned upstream tarball digest, cross-checked against the Buildroot musl
# recipe and the musl-cross-make hash records for the same release.
SHA256="a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4"

HOSTCC="${HOSTCC:-cc}"

TOOLS_DIR="$BUILD_DIR/tools"
MUSL_PREFIX="$TOOLS_DIR/musl"
MARKER="$MUSL_PREFIX/.aweos-musl-baseline"

# Reuse a previously completed baseline musl build in the same build tree.
if [ -f "$MARKER" ] && [ -x "$MUSL_PREFIX/bin/musl-gcc" ] &&
    [ -s "$MUSL_PREFIX/lib/libc.a" ] &&
    grep -qx "${VERSION} ${SHA256}" "$MARKER" 2>/dev/null; then
    echo "PASS: cached baseline musl $VERSION at $MUSL_PREFIX is reused for the bootstrap link."
    exit 0
fi

for tool in curl sha256sum tar make; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: $tool is required to build the baseline musl." >&2
        exit 2
    }
done
command -v "$HOSTCC" >/dev/null 2>&1 || {
    echo "ERROR: host C compiler $HOSTCC is required to build the baseline musl." >&2
    exit 2
}

rm -rf -- "$MUSL_PREFIX"
WORK_DIR="$(mktemp -d "$BUILD_DIR/.musl-build.XXXXXX")"
cleanup() { rm -rf -- "$WORK_DIR"; }
trap cleanup EXIT

# AWEOS_MUSL_TEST_TARBALL / AWEOS_MUSL_TEST_SHA256 are a regression-test hook
# used by scripts/test-musl-baseline-build.sh to exercise the archive
# verification with a synthetic tree. Production builds never set them and
# always download the pinned upstream archive and verify the pinned digest.
if [ -n "${AWEOS_MUSL_TEST_TARBALL:-}" ]; then
    [ -n "${AWEOS_MUSL_TEST_SHA256:-}" ] || {
        echo "ERROR: AWEOS_MUSL_TEST_SHA256 must accompany AWEOS_MUSL_TEST_TARBALL." >&2
        exit 2
    }
    TARBALL="$AWEOS_MUSL_TEST_TARBALL"
    EXPECTED_SHA256="$AWEOS_MUSL_TEST_SHA256"
else
    TARBALL="$WORK_DIR/$ARCHIVE"
    EXPECTED_SHA256="$SHA256"
    echo "Downloading pinned musl $VERSION source..."
    curl --fail --location --retry 3 --retry-all-errors --proto '=https' --tlsv1.2 \
        "$URL" -o "$TARBALL"
fi

printf '%s  %s\n' "$EXPECTED_SHA256" "$TARBALL" | sha256sum --check --status || {
    echo "ERROR: musl source archive SHA-256 mismatch." >&2
    exit 1
}

tar -xzf "$TARBALL" -C "$WORK_DIR" --no-same-owner --no-same-permissions
SOURCE_DIR="$WORK_DIR/musl-$VERSION"
[ -d "$SOURCE_DIR" ] || {
    echo "ERROR: musl source directory is missing after extraction." >&2
    exit 1
}

# Compile musl itself through the baseline policy wrapper. The wrapper appends
# the x86-64-v1 restrictions after every option musl's build system supplies,
# so libc.a, libm.a, and the crt objects contain baseline instructions only.
echo "Configuring pinned musl $VERSION with the enforced x86-64 baseline policy..."
export AWEOS_MUSL_CC="$HOSTCC"
(
    cd "$SOURCE_DIR"
    CC="bash $SCRIPT_DIR/cc-x86_64-baseline.sh" \
        ./configure --prefix="$MUSL_PREFIX"
)

jobs="${AWEOS_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2')}"
case "$jobs" in
    ''|*[!0-9]*) jobs=2 ;;
esac
[ "$jobs" -gt 0 ] || jobs=2

echo "Building baseline musl $VERSION..."
make -C "$SOURCE_DIR" -j"$jobs"
make -C "$SOURCE_DIR" install

# musl bakes the configure-time CC into the generated musl-gcc wrapper as
# the REALGCC default. We compile musl through the baseline policy wrapper,
# but the installed musl-gcc must drive the plain host compiler: with the
# policy wrapper baked in, musl-gcc tries to exec the whole
# "bash .../cc-x86_64-baseline.sh" string as a single file and every
# compilation through it fails. Rewrite the baked default to the host
# compiler and fail closed if the wrapper is still referenced afterwards.
# The sed pattern consumes the closing brace of the REALGCC expansion, so
# the replacement must re-emit it; dropping it leaves a syntactically
# invalid wrapper (an unclosed default expansion).
if grep -q 'cc-x86_64-baseline.sh' "$MUSL_PREFIX/bin/musl-gcc" 2>/dev/null; then
    sed -i "s|REALGCC:-[^}]*}|REALGCC:-${HOSTCC}}|" "$MUSL_PREFIX/bin/musl-gcc"
    if grep -q 'cc-x86_64-baseline.sh' "$MUSL_PREFIX/bin/musl-gcc" 2>/dev/null; then
        echo "ERROR: the installed musl-gcc wrapper still references the baseline policy wrapper; refusing to publish an unusable toolchain." >&2
        exit 1
    fi
fi

# Fail closed on a syntactically broken wrapper before publishing it.
if ! sh -n "$MUSL_PREFIX/bin/musl-gcc" 2>/dev/null; then
    echo "ERROR: the installed musl-gcc wrapper is not valid shell; refusing to publish an unusable toolchain." >&2
    exit 1
fi

[ -x "$MUSL_PREFIX/bin/musl-gcc" ] || {
    echo "ERROR: the baseline musl install did not provide the musl-gcc wrapper." >&2
    exit 1
}
[ -s "$MUSL_PREFIX/lib/libc.a" ] || {
    echo "ERROR: the baseline musl install did not provide libc.a." >&2
    exit 1
}
[ -f "$MUSL_PREFIX/include/stdio.h" ] || {
    echo "ERROR: the baseline musl install did not provide its libc headers." >&2
    exit 1
}

printf '%s %s\n' "$VERSION" "$SHA256" > "$MARKER"
echo "PASS: baseline musl $VERSION installed at $MUSL_PREFIX."
