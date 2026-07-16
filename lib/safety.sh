#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE="$SCRIPT_DIR/core.sh"

safety_menu() {
    while true; do
        local c
        c=$(tui_menu "SAFETY ENGINE" "Quan ly an toan:" 14 50 4 \
            "status"  "Xem trang thai safety" \
            "undo"    "Hoan tac thay doi cuoi" \
            "history" "Xem lich su thay doi" \
            "back"    "Quay lai") || break
        case "$c" in
            status)
                echo -e "\n\e[1;36m=== Safety Status ===\e[0m"
                "$CORE" boot_check 2>/dev/null || true
                echo ""
                echo "Grace dir: $(ls /tmp/calarch-grace/ 2>/dev/null | head -5 || echo 'none')"
                read -r -p "Enter de tiep..."
                ;;
            undo)
                "$CORE" undo 2>/dev/null && echo "OK" || echo "Nothing to undo"
                read -r -p "Enter de tiep..."
                ;;
            history)
                "$CORE" log 10 2>/dev/null || echo "(empty)"
                read -r -p "Enter de tiep..."
                ;;
            back) break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    safety_menu
fi
