#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE="$SCRIPT_DIR/core.sh"
PROFILE_DIR="$SCRIPT_DIR/../profiles"
source "$SCRIPT_DIR/tui.sh"

has() { command -v "$1" &>/dev/null; }

profiles_list() {
    shopt -s nullglob
    local files=("$PROFILE_DIR"/*.conf)
    shopt -u nullglob
    [ ${#files[@]} -eq 0 ] && { echo "(none)"; return; }
    for f in "${files[@]}"; do
        basename "$f" .conf
    done
}

profiles_menu() {
    while true; do
        local c
        c=$(tui_menu "PROFILES" "Quan ly cau hinh:" 14 50 4 \
            "list"    "Xem danh sach profiles" \
            "save"    "Luu cau hinh hien tai" \
            "load"    "Nap profile" \
            "back"    "Quay lai") || break
        case "$c" in
            list)
                echo -e "\n\e[1;36m=== Profiles ===\e[0m"
                profiles_list
                read -r -p "Enter de tiep..."
                ;;
            save)
                read -r -p "Nhap ten profile: " name
                [ -n "$name" ] && bash "$CORE" profile save "$name" 2>/dev/null && echo "OK" || echo "Fail"
                read -r -p "Enter de tiep..."
                ;;
            load)
                local prof items=()
                shopt -s nullglob
                for f in "$PROFILE_DIR"/*.conf; do items+=("$(basename "$f" .conf)" "$(basename "$f" .conf)"); done
                shopt -u nullglob
                [ ${#items[@]} -eq 0 ] && { tui_msg "PROFILES" "Khong co profile nao" 6 30; continue; }
                prof=$(tui_menu "LOAD PROFILE" "Chon profile:" 14 50 4 "${items[@]}") || continue
                [ -n "$prof" ] && bash "$CORE" profile load "$prof" 2>/dev/null && echo "OK" || echo "Fail"
                read -r -p "Enter de tiep..."
                ;;
            back) break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    profiles_menu
fi
