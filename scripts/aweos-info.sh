#!/bin/sh
# AWEOS System Information & Diagnostic Tool

CMD="${1:-info}"

get_uptime() {
    if [ -f /proc/uptime ]; then
        UPSEC=$(awk '{print int($1)}' /proc/uptime)
        MINS=$((UPSEC / 60))
        SECS=$((UPSEC % 60))
        echo "${MINS}m ${SECS}s"
    else
        echo "unknown"
    fi
}

get_mem() {
    if [ -f /proc/meminfo ]; then
        TOTAL=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
        FREE=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
        if [ -n "$TOTAL" ] && [ -n "$FREE" ]; then
            TOTAL_MB=$((TOTAL / 1024))
            FREE_MB=$((FREE / 1024))
            USED_MB=$((TOTAL_MB - FREE_MB))
            echo "${USED_MB}MB / ${TOTAL_MB}MB"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

get_cpu() {
    if [ -f /proc/cpuinfo ]; then
        grep -m1 "model name" /proc/cpuinfo | awk -F': ' '{print $2}' || echo "x86_64 Processor"
    else
        echo "x86_64 Processor"
    fi
}

case "$CMD" in
    info)
        echo "========================================"
        echo "       AWEOS System Information        "
        echo "========================================"
        echo "OS Name:       AWEOS Terminal Linux"
        echo "Version:       1.0.0"
        echo "Architecture:  $(uname -m 2>/dev/null || echo x86_64)"
        echo "Kernel:        $(uname -r 2>/dev/null || echo unknown)"
        echo "Hostname:      $(hostname 2>/dev/null || echo aweos)"
        echo "Uptime:        $(get_uptime)"
        echo "Memory:        $(get_mem)"
        echo "CPU:           $(get_cpu)"
        echo "Root FS:       $(df -h / 2>/dev/null | awk 'NR==2 {print $1 " (" $4 " free)"}')"
        echo "Init System:   AWEOS Init v1.0.0"
        echo "========================================"
        ;;

    status)
        echo "AWEOS System Status: Operational"
        echo "Process Count: $(ps | wc -l)"
        echo "Uptime:        $(get_uptime)"
        echo "Memory Usage:  $(get_mem)"
        ;;

    diagnostics)
        /usr/bin/aweos-diagnostics
        ;;

    *)
        echo "Usage: aweos {info|status|diagnostics|help}"
        ;;
esac
