#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AWEPKG="${REPO_ROOT}/scripts/awepkg.sh"
# awepkg is invoked through `sh` in both passes so the suite does not depend
# on the checked-out file mode; build-rootfs.sh installs it with mode 0755.
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/awepkg-test.XXXXXX")"
trap 'rm -rf -- "${TMP_DIR}"' EXIT

ROOT_DIR="${TMP_DIR}/root"
DB_DIR="${ROOT_DIR}/var/lib/awepkg"
mkdir -p "$ROOT_DIR"

# Help must not create a root or package database as a side effect.
help_output=$(AWEPKG_ROOT="$TMP_DIR/not-created" AWEPKG_DB_DIR="$TMP_DIR/no-db" sh "$AWEPKG" help)
printf '%s\n' "$help_output" | grep -qx 'AWEOS Package Manager (awepkg) v1.3.0'
test ! -e "$TMP_DIR/not-created"
test ! -e "$TMP_DIR/no-db"

# The database must remain under the canonical package root and must not
# follow symlinked parent components outside it.
if AWEPKG_ROOT="$ROOT_DIR" AWEPKG_DB_DIR="$TMP_DIR/outside-db" sh "$AWEPKG" list; then
    echo "ERROR: package database outside AWEPKG_ROOT was accepted" >&2
    exit 1
fi
test ! -e "$TMP_DIR/outside-db"
mkdir -p "$TMP_DIR/outside-db"
ln -s "$TMP_DIR/outside-db" "$ROOT_DIR/escape-db"
if AWEPKG_ROOT="$ROOT_DIR" AWEPKG_DB_DIR="$ROOT_DIR/escape-db/awepkg" sh "$AWEPKG" list; then
    echo "ERROR: symlinked package database parent was accepted" >&2
    exit 1
fi
test ! -e "$TMP_DIR/outside-db/awepkg"

run_pkg() {
    if [ "${AWEPKG_TEST_BUSYBOX:-0}" = "1" ]; then
        AWEPKG_ROOT="$ROOT_DIR" AWEPKG_DB_DIR="$DB_DIR" busybox sh "$AWEPKG" "$@"
    else
        AWEPKG_ROOT="$ROOT_DIR" AWEPKG_DB_DIR="$DB_DIR" sh "$AWEPKG" "$@"
    fi
}
run_dev_pkg() {
    if [ "${AWEPKG_TEST_BUSYBOX:-0}" = "1" ]; then
        AWEPKG_ALLOW_UNSIGNED=1 AWEPKG_ROOT="$ROOT_DIR" AWEPKG_DB_DIR="$DB_DIR" busybox sh "$AWEPKG" "$@"
    else
        AWEPKG_ALLOW_UNSIGNED=1 AWEPKG_ROOT="$ROOT_DIR" AWEPKG_DB_DIR="$DB_DIR" sh "$AWEPKG" "$@"
    fi
}
expect_failure() { if run_pkg "$@"; then echo "unexpected package-manager success: $*" >&2; exit 1; fi; }
expect_dev_failure() { if run_dev_pkg "$@"; then echo "unexpected development package-manager success: $*" >&2; exit 1; fi; }
make_package() {
    package_name="$1"
    payload_path="$2"
    payload_text="$3"
    package_dir="$TMP_DIR/packages/$package_name"
    mkdir -p "$package_dir/root/$(dirname "$payload_path")"
    cat > "$package_dir/manifest.meta" <<EOF
PKG_NAME=$package_name
PKG_VER=1.0.0
PKG_DESC=Package manager integration test
EOF
    printf '%s\n' "$payload_text" > "$package_dir/root/$payload_path"
    tar -czf "$TMP_DIR/$package_name.awe" -C "$package_dir" manifest.meta root
}

make_package demo-package usr/share/demo/message.txt "installed by awepkg"
expect_failure install "$TMP_DIR/demo-package.awe"
test ! -e "$ROOT_DIR/usr/share/demo/message.txt"
test ! -e "$DB_DIR/demo-package.meta"
run_dev_pkg install "$TMP_DIR/demo-package.awe"
test -f "$ROOT_DIR/usr/share/demo/message.txt"
test "$(cat "$ROOT_DIR/usr/share/demo/message.txt")" = "installed by awepkg"
run_pkg info demo-package | grep -qx 'PKG_NAME=demo-package'

# Reinstalling the same package must not overwrite its payload or metadata.
expect_dev_failure install "$TMP_DIR/demo-package.awe"
test "$(cat "$ROOT_DIR/usr/share/demo/message.txt")" = "installed by awepkg"

# Removal must preserve a file that the user changed after package installation.
printf 'user edit\n' > "$ROOT_DIR/usr/share/demo/message.txt"
expect_failure remove demo-package
test "$(cat "$ROOT_DIR/usr/share/demo/message.txt")" = "user edit"
test -f "$DB_DIR/demo-package.meta"
printf 'installed by awepkg\n' > "$ROOT_DIR/usr/share/demo/message.txt"
run_pkg remove demo-package
test ! -e "$ROOT_DIR/usr/share/demo/message.txt"
test ! -e "$DB_DIR/demo-package.meta"

# An existing system file is never overwritten by a package install.
mkdir -p "$ROOT_DIR/usr/share/demo"
printf 'pre-existing system data\n' > "$ROOT_DIR/usr/share/demo/message.txt"
make_package collision-package usr/share/demo/message.txt "must not replace"
expect_dev_failure install "$TMP_DIR/collision-package.awe"
test "$(cat "$ROOT_DIR/usr/share/demo/message.txt")" = "pre-existing system data"
test ! -e "$DB_DIR/collision-package.meta"

# A package must not write into the package manager's own database.
make_package db-collision-package var/lib/awepkg/db-collision-package.meta "must not replace package metadata"
expect_dev_failure install "$TMP_DIR/db-collision-package.awe"
test ! -e "$DB_DIR/db-collision-package.meta"
test ! -e "$DB_DIR/db-collision-package.files"
test ! -e "$DB_DIR/db-collision-package.sha256"

# A symlinked parent must not redirect package payload writes outside ROOT_DIR.
mkdir -p "$TMP_DIR/outside"
ln -s "$TMP_DIR/outside" "$ROOT_DIR/escape"
make_package symlink-parent escape/pwned.txt "must not escape root"
expect_dev_failure install "$TMP_DIR/symlink-parent.awe"
test ! -e "$TMP_DIR/outside/pwned.txt"
test ! -e "$DB_DIR/symlink-parent.meta"

# Hard links are rejected before extraction; they can alias data outside a package.
hardlink_dir="$TMP_DIR/hardlink"
mkdir -p "$hardlink_dir/root/usr/share/demo"
cat > "$hardlink_dir/manifest.meta" <<'EOF'
PKG_NAME=hardlink-package
PKG_VER=1.0.0
PKG_DESC=Hard-link rejection test
EOF
printf 'hard-linked payload\n' > "$hardlink_dir/root/usr/share/demo/original"
ln "$hardlink_dir/root/usr/share/demo/original" "$hardlink_dir/root/usr/share/demo/linked"
tar -czf "$TMP_DIR/hardlink.awe" -C "$hardlink_dir" manifest.meta root
expect_dev_failure install "$TMP_DIR/hardlink.awe"
test ! -e "$DB_DIR/hardlink-package.meta"
test ! -e "$ROOT_DIR/usr/share/demo/original"

# Package payload symlinks and the protected base package are rejected.
unsafe_dir="$TMP_DIR/unsafe"
mkdir -p "$unsafe_dir/root"
cat > "$unsafe_dir/manifest.meta" <<'EOF'
PKG_NAME=unsafe-package
PKG_VER=1.0.0
PKG_DESC=Unsafe symlink test
EOF
ln -s /etc/passwd "$unsafe_dir/root/escape"
tar -czf "$TMP_DIR/unsafe.awe" -C "$unsafe_dir" manifest.meta root
expect_dev_failure install "$TMP_DIR/unsafe.awe"
expect_failure remove base-system

# Package-provided privileged and writable mode bits are normalized.
mode_dir="$TMP_DIR/mode-package"
mkdir -p "$mode_dir/root/usr/bin" "$mode_dir/root/usr/share/mode"
cat > "$mode_dir/manifest.meta" <<'EOF'
PKG_NAME=mode-package
PKG_VER=1.0.0
PKG_DESC=Permission normalization test
EOF
printf '#!/bin/sh\nexit 0\n' > "$mode_dir/root/usr/bin/privileged"
printf 'data\n' > "$mode_dir/root/usr/share/mode/data.txt"
chmod 4777 "$mode_dir/root/usr/bin/privileged"
chmod 0666 "$mode_dir/root/usr/share/mode/data.txt"
tar -czf "$TMP_DIR/mode-package.awe" -C "$mode_dir" manifest.meta root
run_dev_pkg install "$TMP_DIR/mode-package.awe"
test "$(stat -c '%a' "$ROOT_DIR/usr/bin/privileged")" = 755
test "$(stat -c '%a' "$ROOT_DIR/usr/share/mode/data.txt")" = 644
run_pkg remove mode-package

# Inject a deterministic mid-transaction failure after two files have been
# published: the pre-existing z-blocked parent directory is made non-writable,
# which deterministically fails the staging mktemp for the third file in
# unprivileged runs; the PATH-fronted mock ln additionally fails the atomic
# publish step in environments that honor PATH lookups (GNU host tools, root
# runs). Either mechanism must abort the transaction and trigger rollback;
# the test fails loudly if the install unexpectedly succeeds, independent of
# how a BusyBox build resolves applets.
rollback_dir="$TMP_DIR/rollback-package"
mkdir -p "$rollback_dir/root/b-created" "$rollback_dir/root/z-blocked" "$ROOT_DIR/z-blocked"
cat > "$rollback_dir/manifest.meta" <<'EOF'
PKG_NAME=rollback-package
PKG_VER=1.0.0
PKG_DESC=Interrupted install rollback test
EOF
printf 'first file\n' > "$rollback_dir/root/a-first.txt"
printf 'second file\n' > "$rollback_dir/root/b-created/second.txt"
printf 'third file\n' > "$rollback_dir/root/z-blocked/third.txt"
tar -czf "$TMP_DIR/rollback-package.awe" -C "$rollback_dir" manifest.meta root
real_ln="$(command -v ln)"
mock_bin="$TMP_DIR/mock-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/ln" <<'MOCK_LN'
#!/bin/sh
last=""
for argument do last="$argument"; done
case "$last" in */z-blocked/third.txt) exit 1 ;; esac
exec "$AWEPKG_REAL_LN" "$@"
MOCK_LN
chmod 0755 "$mock_bin/ln"
chmod 0555 "$ROOT_DIR/z-blocked"
if PATH="$mock_bin:$PATH" AWEPKG_REAL_LN="$real_ln" run_dev_pkg install "$TMP_DIR/rollback-package.awe"; then
    echo "ERROR: injected mid-install failure unexpectedly succeeded" >&2
    exit 1
fi
chmod 0755 "$ROOT_DIR/z-blocked"
test ! -e "$ROOT_DIR/a-first.txt"
test ! -e "$ROOT_DIR/b-created/second.txt"
test ! -e "$ROOT_DIR/b-created"
test ! -e "$ROOT_DIR/z-blocked/third.txt"
test -z "$(find "$ROOT_DIR/z-blocked" -name '.awepkg.*' -print -quit)"
test ! -e "$DB_DIR/rollback-package.meta"
test ! -e "$DB_DIR/rollback-package.files"
test ! -e "$DB_DIR/rollback-package.sha256"

echo "awepkg safety integration tests passed"

# Repeat with BusyBox ash and BusyBox applets, matching the target rootfs.
if [ "${AWEPKG_TEST_BUSYBOX:-0}" != "1" ] && command -v busybox >/dev/null 2>&1; then
    (
        busybox_dir="$(mktemp -d "${TMPDIR:-/tmp}/awepkg-busybox.XXXXXX")"
        trap 'rm -rf -- "$busybox_dir"' EXIT
        busybox --install -s "$busybox_dir"
        AWEPKG_TEST_BUSYBOX=1 PATH="$busybox_dir:$PATH" bash "$0"
    )
fi
