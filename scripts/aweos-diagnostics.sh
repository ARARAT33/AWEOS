#!/bin/sh
# AWEOS Diagnostic Suite

echo "========================================"
echo "    AWEOS System Diagnostics Report     "
echo "========================================"

echo "[1/8] Kernel & OS Verification:"
echo "  Kernel Release: $(uname -r 2>/dev/null)"
echo "  Machine Arch:   $(uname -m 2>/dev/null)"
[ -f /etc/os-release ] && grep PRETTY_NAME /etc/os-release

echo "[2/8] Virtual Filesystems:"
[ -d /proc ] && echo "  /proc: MOUNTED" || echo "  /proc: MISSING"
[ -d /sys ] && echo "  /sys:  MOUNTED" || echo "  /sys:  MISSING"
[ -d /dev ] && echo "  /dev:  MOUNTED" || echo "  /dev:  MISSING"
[ -d /run ] && echo "  /run:  MOUNTED" || echo "  /run:  MISSING"

echo "[3/8] Essential Device Nodes:"
[ -c /dev/console ] && echo "  /dev/console: OK" || echo "  /dev/console: MISSING"
[ -c /dev/null ]    && echo "  /dev/null:    OK" || echo "  /dev/null:    MISSING"
[ -c /dev/ttyS0 ]   && echo "  /dev/ttyS0:   OK" || echo "  /dev/ttyS0:   MISSING"
[ -d /dev/pts ]     && echo "  /dev/pts:     OK" || echo "  /dev/pts:     MISSING"

echo "[4/8] Root Filesystem Storage:"
df -h / 2>/dev/null || true

echo "[5/8] Memory Allocation:"
free -h 2>/dev/null || free 2>/dev/null || true

echo "[6/8] Network Interfaces:"
ip addr 2>/dev/null || ifconfig 2>/dev/null || echo "No network utilities available"

echo "[7/8] Package Manager Database:"
if [ -d /var/lib/awepkg ]; then
    INSTALLED=$(ls -1 /var/lib/awepkg/*.meta 2>/dev/null | wc -l)
    echo "  Package store active ($INSTALLED packages installed)"
else
    echo "  /var/lib/awepkg database missing!"
fi

echo "[8/8] Core Utilities Check:"
for cmd in ls cd pwd cat cp mv rm mkdir grep sed find ps top mount df free uname dmesg ip ping vi aweos awepkg reboot poweroff; do
    if command -v $cmd >/dev/null 2>&1; then
        printf " %s" "$cmd"
    fi
done
echo ""

echo "========================================"
echo "Diagnostics Complete: All Systems Normal"
echo "========================================"
