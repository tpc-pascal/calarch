#!/bin/bash
# ============================================================================
# SUPER-MODE.SH — Daemon tu dong chuyen HOT/COOL
# COOL: idle, browse, code, video → tiet kiem pin + mat
# HOT: compile, build, render, VM → boost full
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../calarch.conf"
source "$SCRIPT_DIR/config-load.sh"
calarch_load_config "$CONFIG_FILE"

PID_FILE="/tmp/super-mode.pid"
LOG_FILE="/tmp/super-mode.log"

COOL_THRESH="${SUPER_COOL_THRESHOLD:-30}"
HOT_THRESH="${SUPER_HOT_THRESHOLD:-70}"
HOT_DEBOUNCE="${SUPER_HOT_DEBOUNCE:-5}"
COOL_DEBOUNCE="${SUPER_COOL_DEBOUNCE:-10}"
COOL_GOV="${SUPER_COOL_GOVERNOR:-powersave}"
HOT_GOV="${SUPER_HOT_GOVERNOR:-schedutil}"

eco_path="/sys/devices/platform/panasonic/eco_mode"
cool_active=false
hot_timer=0
cool_timer=0

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }

# Ghi file he thong: dung sudo -n (khong treo doi mat khau khi chay daemon user)
write_sys() {
    local val="$1" path="$2"
    if [ "$(id -u)" = "0" ]; then
        echo "$val" > "$path" 2>/dev/null || true
    else
        echo "$val" | sudo -n tee "$path" >/dev/null 2>&1 || true
    fi
}

set_cool() {
    if $cool_active; then return; fi
    echo -e "\033[0;34m>>> [COOL] Saving power...\033[0m"
    log "COOL mode"
    write_sys "$COOL_GOV" /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
    write_sys 1 "$eco_path"
    cool_active=true
}

set_hot() {
    if ! $cool_active; then return; fi
    echo -e "\033[0;31m>>> [HOT] Full performance...\033[0m"
    log "HOT mode"
    write_sys "$HOT_GOV" /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
    write_sys 0 "$eco_path"
    cool_active=false
}

cleanup() {
    log "Daemon stopping, restoring defaults..."
    set_hot
    rm -f "$PID_FILE"
    exit 0
}

is_compiling() {
    local procs=(gcc g++ cc clang rustc cargo make cmake ninja go build npm node dotnet java javac ghc)
    for p in "${procs[@]}"; do
        pgrep -x "$p" &>/dev/null && return 0
    done
    # Check common build patterns
    pgrep -f "cargo build" &>/dev/null && return 0
    pgrep -f "make -j" &>/dev/null && return 0
    pgrep -f "npm run build" &>/dev/null && return 0
    pgrep -f "ninja" &>/dev/null && return 0
    return 1
}

main() {
    # PID file + single instance (atomic via noclobber)
    if ! (set -o noclobber; echo $$ > "$PID_FILE") 2>/dev/null; then
        echo "Super Mode Daemon already running (PID $(cat "$PID_FILE" 2>/dev/null))"
        exit 1
    fi
    trap cleanup EXIT TERM INT

    log "Daemon started (PID $$)"
    echo -e "\033[0;35mSuper Mode Daemon started (PID $$)\033[0m"
    echo -e "\033[0;90m  HOT >${HOT_THRESH}% load (${HOT_DEBOUNCE}s) OR compiler process"
    echo -e "  COOL <${COOL_THRESH}% load (${COOL_DEBOUNCE}s)\033[0m"

    # Dinh nghia trang thai ban dau theo governor hien tai (tranh ghi thua)
    local cur_gov
    cur_gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "")
    if [ "$cur_gov" = "$COOL_GOV" ]; then
        cool_active=true
    else
        cool_active=false
    fi

    while true; do
        local load
        load=$(awk '/cpu /{printf "%d",($2+$4)*100/($2+$4+$5)}' /proc/stat 2>/dev/null || echo 0)

        if is_compiling; then
            hot_timer=$((hot_timer + 2))
            cool_timer=0
        elif [ "$load" -gt "$HOT_THRESH" ]; then
            hot_timer=$((hot_timer + 2))
            cool_timer=0
        elif [ "$load" -lt "$COOL_THRESH" ]; then
            cool_timer=$((cool_timer + 2))
            hot_timer=0
        else
            hot_timer=0
            cool_timer=0
        fi

        if [ "$hot_timer" -ge "$HOT_DEBOUNCE" ]; then
            set_hot
            hot_timer=0
        fi
        if [ "$cool_timer" -ge "$COOL_DEBOUNCE" ]; then
            set_cool
            cool_timer=0
        fi

        sleep 2
    done
}

main "$@"
