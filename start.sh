#!/bin/bash
# ============================================================================
# START.SH — TUI Control Center for Arch Linux + Panasonic CF-XZ6
# ----------------------------------------------------------------------------
# Main menu: Settings, Games, Exit
# Tu dong dung dialog (preferred) hoac whiptail (fallback)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# --- Paths ---
INSTALL_SH="$LIB_DIR/install.sh"
GAMES_SH="$LIB_DIR/games.sh"
SETTINGS_SH="$LIB_DIR/settings.sh"

# --- Source TUI ---
source "$LIB_DIR/tui.sh"

# --- Colors (cho stdout) ---
R='\033[0m'; B='\033[1m'; D='\033[0;90m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'; MG='\033[0;35m'

log_i() { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_w()  { echo -e "${YEL}[!!]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }

# --- Helpers ---
check_root() { [ "$EUID" -eq 0 ] && { echo -e "${RED}Khong chay bang root!${R}"; exit 1; }; }
has() { command -v "$1" &>/dev/null; }

cpu_temp() {
    local t=0
    [ -f /sys/class/thermal/thermal_zone0/temp ] && t=$(cat /sys/class/thermal/thermal_zone0/temp) && t=$((t/1000))
    echo "$t"
}

dashboard() {
    local temp=$(cpu_temp)
    local eco=$(cat /sys/devices/platform/panasonic/eco_mode 2>/dev/null || echo "?")
    local super=$(pgrep -f "super-mode.sh" &>/dev/null && echo "ON" || echo "OFF")
    local ollama=$(systemctl is-active ollama &>/dev/null && echo "ON" || echo "OFF")
    echo "CPU: ${temp}C | Eco: ${eco} | Super: ${super} | AI: ${ollama}"
}

# --- Menus ---
menu_settings() {
    if [ -f "$SETTINGS_SH" ]; then
        bash "$SETTINGS_SH"
    else
        tui_msg "Error" "Missing $SETTINGS_SH" 8 44
    fi
}

menu_games() {
    if [ -f "$GAMES_SH" ]; then
        bash "$GAMES_SH"
    else
        tui_msg "Error" "Missing $GAMES_SH" 8 44
    fi
}

# --- Main menu ---
main_menu() {
    while true; do
        tui_backtitle "ARCCAL Dashboard | $(dashboard)"
        local c
        c=$(tui_menu "ARCCAL — Control Center" "Chon chuc nang:" 14 58 3 \
            1 "Settings  — 3 nhom: System / Services / Apps" \
            2 "Games     — minetest, assaultcube, megaglest" \
            3 "Exit") || true
        [ -z "$c" ] && { tui_msg "ARCCAL" "Goodbye!" 7 32; clear; exit 0; }
        case "$c" in
            1) menu_settings ;;
            2) menu_games ;;
            3) tui_msg "ARCCAL" "Goodbye!" 7 32; clear; exit 0 ;;
        esac
    done
}

# --- First-boot (khong dung TUI) ---
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "first-boot" ]; then
    log_i "First-boot mode"
    [ -f "$INSTALL_SH" ] && bash "$INSTALL_SH"
    exit 0
fi

# --- Safety check ---
check_root
if ! tui_detect; then
    echo -e "${RED}ERROR: Can dialog hoac whiptail${R}"
    echo "  sudo pacman -S dialog"
    exit 1
fi
has pacman || { log_e "Not Arch Linux"; exit 1; }

# --- Start ---
main_menu
