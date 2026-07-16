#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE="$SCRIPT_DIR/core.sh"

has() { command -v "$1" &>/dev/null; }

super_on()     { pgrep -f "super-mode.sh" &>/dev/null; }
eco_on()       { [ -f /sys/devices/platform/panasonic/eco_mode ] && [ "$(cat /sys/devices/platform/panasonic/eco_mode)" = "1" ]; }

system_info() {
    local cpu_load cpu_temp cpu_freq gov eco_state super_state
    cpu_load=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "?")
    if has sensors; then
        cpu_temp=$(sensors 2>/dev/null | grep -i "core 0" | awk '{print $3}' | sed 's/+//' | head -1 || echo "?")
    else
        cpu_temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1 | awk '{printf "%.0f°C", $1/1000}' || echo "?")
    fi
    cpu_freq=$(awk '{print $1/1000}' /proc/cpuinfo 2>/dev/null | grep -v "0" | head -1 | awk '{printf "%.2fGHz", $1}' || echo "?")
    gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "?")
    eco_state=$(eco_on && echo "ON" || echo "OFF")
    super_state=$(super_on && echo "ACTIVE" || echo "IDLE")

    echo "CPU: ${cpu_load} | Temp: ${cpu_temp} | Freq: ${cpu_freq}"
    echo "Governor: ${gov} | Eco: ${eco_state} | Super: ${super_state}"
}

system_dashboard() {
    while true; do
        clear
        echo -e "\e[1;36m╔══════════════════════════════════════╗\e[0m"
        echo -e "\e[1;36m║        SYSTEM MONITOR                ║\e[0m"
        echo -e "\e[1;36m╚══════════════════════════════════════╝\e[0m"
        echo ""
        system_info
        echo ""
        echo "  [R] Refresh  [Q] Back"
        read -r -t 3 key || true
        case "${key,,}" in
            q) break ;;
            r) continue ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    system_dashboard
fi
