#!/bin/bash
set -uo pipefail
# ============================================================================
# HYPRLAND-EVENT-MONITOR.SH
# Dynamic CPU Affinity Engine — Real-time Window Focus Monitor
# ----------------------------------------------------------------------------
# Doc cau hinh tu calarch.conf
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../calarch.conf"
source "$SCRIPT_DIR/config-load.sh"
calarch_load_config "$CONFIG_FILE"

PID_FILE="/tmp/hyprland-event-monitor.pid"

if ! (set -o noclobber; echo $$ > "$PID_FILE") 2>/dev/null; then
    echo "Hyprland Event Monitor already running (PID $(cat "$PID_FILE" 2>/dev/null))"
    exit 1
fi
trap 'rm -f "$PID_FILE"' EXIT TERM INT

ACTIVE_CORES="${AFFINITY_ACTIVE_CORES:-0,1}"
BG_CORES="${AFFINITY_BG_CORES:-2,3}"
ACTIVE_SCHED="${AFFINITY_ACTIVE_SCHED:-rr}"
ACTIVE_PRIORITY="${AFFINITY_ACTIVE_PRIORITY:-50}"
ACTIVE_IONICE="${AFFINITY_ACTIVE_IONICE:-0}"
BG_IONICE="${AFFINITY_BG_IONICE:-5}"

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
        # SCHED_RR can root (CAP_SYS_NICE); neu khong du quyen → fallback SCHED_OTHER
        chrt -"${ACTIVE_SCHED:-r}" -p "${ACTIVE_PRIORITY:-50}" "$pid" 2>/dev/null || \
            chrt -o -p 0 "$pid" 2>/dev/null || true
        ionice -c 2 -n "${ACTIVE_IONICE:-0}" -p "$pid" 2>/dev/null || true
    else
        chrt -o -p 0 "$pid" 2>/dev/null || true
        ionice -c 2 -n "${BG_IONICE:-5}" -p "$pid" 2>/dev/null || true
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

# Kiem tra phu thuoc
for _cmd in jq nc hyprctl taskset chrt ionice; do
    command -v "$_cmd" &>/dev/null || { echo "ERROR: $_cmd not found"; exit 1; }
done

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
