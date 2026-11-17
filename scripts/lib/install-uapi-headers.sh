#!/usr/bin/env bash
# Install sanitized Linux UAPI headers from the vendored kernel tree.
#
# The raw include/uapi headers in the kernel source are kernel-internal:
# they keep __user annotations and include <linux/compiler.h>, which does
# not exist under include/uapi at all. `make headers_install` produces the
# canonical userspace-safe export (generated asm/posix_types.h, stripped
# annotations) into a build-directory prefix, leaving /linux untouched.
# The exported set still references <linux/compiler.h> from headers such
# as <linux/kd.h>, so a userspace-safe stub matching the distribution
# linux-libc-dev package is published next to it. The prefix is then
# self-contained and usable under musl-gcc's -nostdinc.
#
# Usage:
#   aweos_install_uapi_headers <linux_dir> <o_dir> <prefix> <log_path>
#
# Returns non-zero (with the log tail on stderr) when headers_install fails.

aweos_install_uapi_headers() {
    local linux_dir="$1" o_dir="$2" prefix="$3" log_path="$4"

    command -v make >/dev/null 2>&1 || {
        echo "ERROR: make is required to install the sanitized UAPI headers." >&2
        return 2
    }
    [ -f "$linux_dir/Makefile" ] || {
        echo "ERROR: the vendored kernel tree is missing: $linux_dir" >&2
        return 2
    }

    rm -rf -- "$prefix" "$o_dir"
    mkdir -p -- "$prefix"

    if ! make -C "$linux_dir" O="$o_dir" ARCH=x86_64 headers_install \
            INSTALL_HDR_PATH="$prefix" >"$log_path" 2>&1; then
        echo "ERROR: 'make headers_install' failed for the vendored kernel tree ($linux_dir)." >&2
        tail -n 20 "$log_path" 2>/dev/null | sed 's/^/ERROR: headers_install: /' >&2 || true
        return 1
    fi

    [ -f "$prefix/include/linux/kd.h" ] || {
        echo "ERROR: sanitized UAPI install did not provide include/linux/kd.h." >&2
        return 1
    }
    [ -f "$prefix/include/asm/posix_types.h" ] || {
        echo "ERROR: sanitized UAPI install did not provide asm/posix_types.h." >&2
        return 1
    }

    # headers_install exports only include/uapi, so <linux/compiler.h> is
    # absent even though exported headers such as <linux/kd.h> include it.
    # Publish the same userspace-safe stub the distribution linux-libc-dev
    # package provides so the prefix is self-contained under -nostdinc.
    if [ ! -f "$prefix/include/linux/compiler.h" ]; then
        cat > "$prefix/include/linux/compiler.h" <<'AWEOS_COMPILER_STUB'
/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
#ifndef _UAPI_LINUX_COMPILER_H
#define _UAPI_LINUX_COMPILER_H
/* Userspace-safe stub for exported kernel headers that include
 * <linux/compiler.h>. The kernel-internal compiler attributes are not
 * meaningful in userspace; this matches the linux-libc-dev stub behavior. */
#ifndef __user
#define __user
#endif
#ifndef __kernel
#define __kernel
#endif
#ifndef __force
#define __force
#endif
#ifndef __iomem
#define __iomem
#endif
#ifndef __chk_user_ptr
#define __chk_user_ptr(x) (void)0
#endif
#endif /* _UAPI_LINUX_COMPILER_H */
AWEOS_COMPILER_STUB
    fi

    return 0
}
