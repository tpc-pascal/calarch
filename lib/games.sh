#!/bin/bash
# ============================================================================
# GAMES.SH — 3 game chinh: Minetest, AssaultCube, MegaGlest
# Tat ca tu Arch Linux official repo, tu dong cai lan dau chon
# ============================================================================

set -euo pipefail

R='\033[0m'; B='\033[1m'; D='\033[0;90m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'; MG='\033[0;35m'

log_i() { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/tui.sh"

declare -A GAMES=(
    ["minetest"]="Voxel sandbox, style Minecraft"
    ["assaultcube"]="FPS nhanh, style Counter-Strike"
    ["megaglest"]="3D RTS thoi gian that, style Age of Empires"
)

install_if_needed() {
    local pkg="$1"
    if ! pacman -Qi "$pkg" &>/dev/null; then
        log_i "Dang cai: $pkg..."
        sudo pacman -S --noconfirm "$pkg" 2>/dev/null || {
            log_e "Khong the cai $pkg"
            return 1
        }
        log_ok "Da cai $pkg"
    fi
}

main_menu() {
    while true; do
        local menu_items=()
        for pkg in "${!GAMES[@]}"; do
            local desc="${GAMES[$pkg]}"
            local installed=""
            pacman -Qi "$pkg" &>/dev/null && installed=" [CAI]"
            menu_items+=("$pkg" "${desc}${installed}")
        done
        menu_items+=("B" "Quay lai")

        local c
        c=$(tui_menu "GAMES" "3 game chinh, tu dong cai lan dau:" 14 56 4 \
            "${menu_items[@]}") || break
        [ "$c" = "B" ] && break

        if install_if_needed "$c"; then
            log_i "Khoi dong $c..."
            nohup "$c" >/dev/null 2>&1 &
            log_ok "$c dang chay (PID: $!)"
            sleep 1
        else
            log_e "Khong the cai game $c"
        fi
        read -r -p "Press Enter..."
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main_menu
fi
