#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE="$SCRIPT_DIR/core.sh"
source "$SCRIPT_DIR/tui.sh"

# Dung chung logic state voi core.sh (per-user ~/.local/state/calarch)
state_base() {
    local sh
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        sh=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || echo "$HOME")
        [ -z "$sh" ] && sh="$HOME"
    else
        sh="$HOME"
    fi
    echo "${XDG_STATE_HOME:-$sh/.local/state}/calarch"
}

safety_menu() {
    while true; do
        local c
        c=$(tui_menu "SAFETY ENGINE" "Quan ly an toan:" 14 50 4 \
            "status"  "Xem trang thai safety" \
            "undo"    "Hoan tac thay doi cuoi" \
            "history" "Xem lich su thay doi" \
            "back"    "Quay lai") || break
        local st
        st=$(state_base)
        case "$c" in
            status)
                echo -e "\n\e[1;36m=== Safety Status ===\e[0m"
                echo -e "Grace dir: \e[0;90m${st}/grace\e[0m"
                local g
                g=$(bash "$CORE" grace_status 2>/dev/null || true)
                echo -e "Grace pending: \e[1;33m${g:-none}\e[0m"
                read -r -p "Enter de tiep..."
                ;;
            undo)
                if [ -s "$st/history/history.log" ]; then
                    bash "$CORE" undo 2>/dev/null || true
                    echo "OK"
                else
                    echo "Nothing to undo"
                fi
                read -r -p "Enter de tiep..."
                ;;
            history)
                bash "$CORE" log 10 2>/dev/null || echo "(empty)"
                read -r -p "Enter de tiep..."
                ;;
            back) break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    safety_menu
fi
