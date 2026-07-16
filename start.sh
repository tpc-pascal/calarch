#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CORE="$LIB_DIR/core.sh"
CONFIG_FILE="$SCRIPT_DIR/calarch.conf"

[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" 2>/dev/null || true
source "$LIB_DIR/tui.sh" 2>/dev/null || true

R='\e[0m'; B='\e[1m'
RED='\e[0;31m'; GR='\e[0;32m'; YEL='\e[1;33m'; CY='\e[0;36m'; MG='\e[0;35m'

log_i()  { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_w()  { echo -e "${YEL}[!!]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }

has() { command -v "$1" &>/dev/null; }

first_boot_mode() {
    if [ -f "$LIB_DIR/install.sh" ]; then
        bash "$LIB_DIR/install.sh"
    fi
    exit 0
}

boot_guard() {
    "$CORE" boot_check 2>/dev/null || true
    "$CORE" i_am_alive 2>/dev/null || true
}

# --- Unified TUI menu ---
main_menu() {
    while true; do
        local c
        c=$(tui_menu "CALARCH CONTROL CENTER" \
            "Chon chuc nang:" 18 56 10 \
            "1"  "System Monitor — CPU, temp, freq, eco, super mode" \
            "2"  "Settings Panel — Super Mode, Affinity, Eco, Services" \
            "3"  "Drive Manager — mount/unmount partitions" \
            "4"  "Wallpaper Changer — chafa preview, set wallpaper" \
            "5"  "Focus Mode — Pomodoro + site blocker" \
            "6"  "Notes — Obsidian vault manager" \
            "7"  "Games — minetest, assaultcube, megaglest" \
            "8"  "rEFInd Sync — dong bo kernel ra ESP" \
            "9"  "Profiles — luu/nap cau hinh" \
            "P"  "Post-Install Setup — chay sau khi cai Arch (1 lan)" \
            "S"  "Safety Engine — grace period, undo, history" \
            "Q"  "Thoat") || break
        [ -z "$c" ] && break
        case "$c" in
            1) bash "$LIB_DIR/system.sh" || log_w "system.sh failed" ;;
            2) bash "$LIB_DIR/settings.sh" || log_w "settings.sh failed" ;;
            3) bash "$LIB_DIR/mount.sh" || log_w "mount.sh failed" ;;
            4) bash "$LIB_DIR/wallpaper.sh" || log_w "wallpaper.sh failed" ;;
            5) bash "$LIB_DIR/focus.sh" || log_w "focus.sh failed" ;;
            6) bash "$LIB_DIR/notes.sh" || log_w "notes.sh failed" ;;
            7) bash "$LIB_DIR/games.sh" || log_w "games.sh failed" ;;
            8) bash "$LIB_DIR/refind-sync.sh" || log_w "refind-sync.sh failed" ;;
            9) bash "$LIB_DIR/profiles.sh" || log_w "profiles.sh failed" ;;
            P|p)
                if [ "$(id -u)" -ne 0 ]; then
                    log_w "Post-install can root. Chay lai: sudo bash start.sh"
                    read -r -p "Enter de tiep..."
                    continue
                fi
                bash "$LIB_DIR/post-install.sh" post-install /mnt
                read -r -p "Enter de tiep..."
                ;;
            S|s) bash "$LIB_DIR/safety.sh" || log_w "safety.sh failed" ;;
            Q|q) clear; exit 0 ;;
        esac
    done
}

# --- CLI entry ---
case "${1:-}" in
    -m|--mode)
        case "${2:-}" in
            first-boot) first_boot_mode ;;
            *) echo "Unknown mode: $2"; exit 1 ;;
        esac
        ;;
    --post-install)
        sudo bash "$LIB_DIR/post-install.sh" post-install "${2:-/mnt}"
        ;;
    --fix-partuuid)
        sudo bash "$LIB_DIR/post-install.sh" fix-partuuid "${2:-/mnt}" "${3:-}"
        ;;
    --refind)
        sudo bash "$LIB_DIR/post-install.sh" refind "${2:-/mnt}"
        ;;
    --help|-h)
        echo "Usage: bash start.sh [options]"
        echo "  (no args)           Unified TUI menu"
        echo "  --post-install [mnt] Chay post-install (can root)"
        echo "  --fix-partuuid [mnt] <id> Sua PARTUUID trong refind_linux.conf"
        echo "  --refind [mnt]       Sinh refind_linux.conf"
        echo "  -m first-boot        Che do first-boot setup"
        ;;
    *)
        boot_guard
        main_menu
        ;;
esac
