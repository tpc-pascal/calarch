#!/bin/bash
# ============================================================================
# SUPER-MODE.SH — Daemon tu dong chuyen HOT/COOL
# COOL: idle, browse, code, video → tiet kiem pin + mat
# HOT: compile, build, render, VM → boost full
# ============================================================================

set -euo pipefail

PID_FILE="/tmp/super-mode.pid"
LOG_FILE="/tmp/super-mode.log"

COOL_THRESH=30   # Xuong COOL khi load < 30%
HOT_THRESH=70    # Len HOT khi load > 70%
HOT_DEBOUNCE=5   # Giay load >70% lien tuc de len HOT
COOL_DEBOUNCE=10 # Giay load <30% lien tuc de xuong COOL

eco_path="/sys/devices/platform/panasonic/eco_mode"
cool_active=false
hot_timer=0
cool_timer=0

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }

set_cool() {
    if $cool_active; then return; fi
    echo -e "\033[0;34m>>> [COOL] Saving power...\033[0m"
    log "COOL mode"
    echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true
    echo 1 | sudo tee "$eco_path" >/dev/null 2>&1 || true
    cool_active=true
}

set_hot() {
    if ! $cool_active; then return; fi
    echo -e "\033[0;31m>>> [HOT] Full performance...\033[0m"
    log "HOT mode"
    echo schedutil | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true
    echo 0 | sudo tee "$eco_path" >/dev/null 2>&1 || true
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
    # PID file + single instance
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "Super Mode Daemon already running (PID $(cat "$PID_FILE"))"
        exit 1
    fi
    echo $$ > "$PID_FILE"
    trap cleanup EXIT TERM INT

    log "Daemon started (PID $$)"
    echo -e "\033[0;35mSuper Mode Daemon started (PID $$)\033[0m"
    echo -e "\033[0;90m  HOT >${HOT_THRESH}% load (${HOT_DEBOUNCE}s) OR compiler process"
    echo -e "  COOL <${COOL_THRESH}% load (${COOL_DEBOUNCE}s)\033[0m"

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

main
