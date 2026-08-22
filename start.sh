#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CORE="$LIB_DIR/core.sh"
CONFIG_FILE="$SCRIPT_DIR/calarch.conf"

# shellcheck source=/dev/null
if [ -f "$CONFIG_FILE" ]; then
    source "$LIB_DIR/config-load.sh" 2>/dev/null || true
    calarch_load_config "$CONFIG_FILE" 2>/dev/null || true
fi

if ! command -v gum &>/dev/null; then
    echo -e ">>> gum not found. Installing..."
    if command -v pacman &>/dev/null; then
        sudo pacman -S gum --noconfirm 2>/dev/null || true
    fi
    if ! command -v gum &>/dev/null; then
        echo -e "[EE] Cannot install gum. Run: sudo pacman -S gum"
        exit 1
    fi
fi

if [ -f "$LIB_DIR/tui.sh" ]; then
    source "$LIB_DIR/tui.sh"
else
    echo -e "[!!] tui.sh not found — TUI unavailable, use CLI args"
fi

R='\e[0m'; B='\e[1m'
RED='\e[0;31m'; GR='\e[0;32m'; YEL='\e[1;33m'; CY='\e[0;36m'; MG='\e[0;35m'

log_i()  { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_w()  { echo -e "${YEL}[!!]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }

has() { command -v "$1" &>/dev/null; }

# Called by .bash_login godmode flow. Runs guided first-boot setup.
first_boot_mode() {
    bash "$LIB_DIR/godmode-setup.sh" "$@"
    exit 0
}

boot_guard() {
    bash "$CORE" boot_check 2>/dev/null || true
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
            "G"  "God-Mode Setup — yay, Hyprland, ZRAM, undervolt, thermal" \
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
                    log_w "Post-install can root. Tu dong leo thang..."
                    exec sudo bash "$0" --post-install
                fi
                local pmnt
                pmnt=$(gum input --placeholder "/mnt" --prompt "Mount point: " 2>/dev/null || echo "/mnt")
                [ -z "$pmnt" ] && pmnt="/mnt"
                bash "$LIB_DIR/post-install.sh" post-install "$pmnt"
                read -r -p "Enter de tiep..."
                ;;
            G|g) bash "$LIB_DIR/godmode-setup.sh" || log_w "godmode-setup.sh failed" ;;
            S|s) bash "$LIB_DIR/safety.sh" || log_w "safety.sh failed" ;;
            Q|q) clear; exit 0 ;;
        esac
    done
}

# --- CLI entry ---
case "${1:-}" in
    --version|-v)
        echo "calarch 1.0.16"
        exit 0
        ;;
    -m|--mode)
        case "${2:-}" in
            first-boot) shift 2; first_boot_mode "$@" ;;
            *) echo "Unknown mode: $2"; exit 1 ;;
        esac
        ;;
    --post-install)
        if [ "$(id -u)" -ne 0 ]; then
            exec sudo bash "$0" --post-install "${2:-}"
        fi
        bash "$LIB_DIR/post-install.sh" post-install "${2:-/mnt}"
        ;;
    --fix-partuuid)
        if [ "$(id -u)" -ne 0 ]; then
            exec sudo bash "$0" --fix-partuuid "${2:-/mnt}" "${3:-}"
        fi
        bash "$LIB_DIR/post-install.sh" fix-partuuid "${2:-/mnt}" "${3:-}"
        ;;
    --refind)
        if [ "$(id -u)" -ne 0 ]; then
            exec sudo bash "$0" --refind "${2:-/mnt}"
        fi
        bash "$LIB_DIR/post-install.sh" refind "${2:-/mnt}"
        ;;
    --help|-h)
        echo "Usage: bash start.sh [options]"
        echo "  (no args)           Unified TUI menu"
        echo "  --post-install [mnt] Chay post-install (can root)"
        echo "  --fix-partuuid [mnt] <id> Sua PARTUUID trong refind_linux.conf"
        echo "  --refind [mnt]       Sinh refind_linux.conf"
        echo "  --version|-v         Hien phien ban"
        exit 0
        ;;
    *)
        boot_guard
        if declare -F tui_menu &>/dev/null; then
            main_menu
        else
            log_e "TUI not available (missing tui.sh). Use CLI args: --help"
            exit 1
        fi
        ;;
esac
