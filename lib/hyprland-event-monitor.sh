#!/bin/bash
set -uo pipefail
# ============================================================================
# HYPRLAND-EVENT-MONITOR.SH
# Dynamic CPU Affinity Engine — Real-time Window Focus Monitor
# ----------------------------------------------------------------------------
# Co che Scientific:
# Lang nghe socket event cua Hyprland, bat su kien "activewindow>>"
# de thuc thi dieu phoi CPU affinity, scheduling policy, va I/O priority.
# ============================================================================
# An toan: Chi xu ly khi co su kien thuc su, sleep 0.05s chong qua tai

# --- Cau hinh / Configuration ---
# Core danh cho ung dung dang Active / Active app cores
ACTIVE_CORES="0,1"
# Core danh cho ung dung nen / Background app cores
BG_CORES="2,3"

# --- Ham log tien trinh / Process logging ---
log_affinity() {
    local pid="$1"
    local action="$2"
    echo "[$(date '+%H:%M:%S')] PID $pid → $action" >> /tmp/hyprland-affinity.log
}

# --- Ham gan tai nguyen cho mot PID / Assign resources to a PID ---
assign_pid_resources() {
    local pid="$1"
    local cores="$2"
    local role="$3"

    # Kiem tra PID ton tai / Verify PID exists
    if ! kill -0 "$pid" 2>/dev/null; then
        return
    fi

    # taskset: gan CPU affinity mask
    taskset -pc "$cores" "$pid" 2>/dev/null

    if [ "$role" = "active" ]; then
        # SCHED_RR: preemptible real-time, round-robin, priority 50
        chrt -r -p 50 "$pid" 2>/dev/null
        # ionice: Best-effort class, priority 0 (cao nhat)
        ionice -c 2 -n 0 -p "$pid" 2>/dev/null
    else
        # SCHED_OTHER: timesharing default, priority 0
        chrt -o -p 0 "$pid" 2>/dev/null
        # ionice: Best-effort class, priority 5 (thap)
        ionice -c 2 -n 5 -p "$pid" 2>/dev/null
    fi

    log_affinity "$pid" "${role}: cores=${cores}"
}

# --- Ham quet tat ca PID cua so Hyprland ---
scan_and_assign_all() {
    local active_pid="$1"

    local all_pids
    all_pids=$(hyprctl clients -j 2>/dev/null | jq -r '.[].pid' 2>/dev/null | grep -v '^$' || true)

    for bg_pid in $all_pids; do
        if [ -n "$bg_pid" ] && [ "$bg_pid" != "$active_pid" ] && [ "$bg_pid" -gt 0 ] 2>/dev/null; then
            assign_pid_resources "$bg_pid" "$BG_CORES" "background"
        fi
    done
}

# --- Main Loop: Lang nghe socket su kien Hyprland ---
SOCKET_DIR="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}"
SOCKET_PATH="${SOCKET_DIR}/.socket2.sock"

echo "[$(date '+%H:%M:%S')] Hyprland Event Monitor started" > /tmp/hyprland-affinity.log
echo "[$(date '+%H:%M:%S')] Socket: ${SOCKET_PATH}" >> /tmp/hyprland-affinity.log
echo "[$(date '+%H:%M:%S')] Active cores: ${ACTIVE_CORES}, BG cores: ${BG_CORES}" >> /tmp/hyprland-affinity.log

if [ ! -S "$SOCKET_PATH" ]; then
    echo "ERROR: Hyprland socket not found at ${SOCKET_PATH}" >> /tmp/hyprland-affinity.log
    exit 1
fi

nc -U "$SOCKET_PATH" | while read -r event_line; do
    if [[ "$event_line" == "activewindow>>"* ]]; then
        event_data="${event_line#activewindow>>}"

        sleep 0.05

        active_pid=$(hyprctl activewindow -j 2>/dev/null | jq '.pid' 2>/dev/null || echo "0")

        if [ -n "$active_pid" ] && [ "$active_pid" -gt 0 ] 2>/dev/null; then
            assign_pid_resources "$active_pid" "$ACTIVE_CORES" "active"
            scan_and_assign_all "$active_pid"
        fi
    fi
done
