#!/bin/bash
# ============================================================================
# WALLPAPER.SH — Wallpaper changer + chafa preview
# Ho tro hyprpaper, swaybg, feh + preview thumbnail trong terminal
# ============================================================================
set -euo pipefail

R='\033[0m'; B='\033[1m'; D='\033[0;90m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'; MG='\033[0;35m'

log_i() { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_w()  { echo -e "${YEL}[!!]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/tui.sh"
CORE="$SCRIPT_DIR/core.sh"
CONFIG_FILE="$SCRIPT_DIR/../calarch.conf"
source "$SCRIPT_DIR/config-load.sh"
calarch_load_config "$CONFIG_FILE"

WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/Pictures/wallpapers}"
WALLPAPER_ENGINE="${WALLPAPER_ENGINE:-hyprpaper}"
MONITOR="${WALLPAPER_MONITOR:-}"

CUSTOM_SRC_WIN="$SCRIPT_DIR/../pascal_wallpaper_win.jpg"
CUSTOM_SRC_PHONE="$SCRIPT_DIR/../pascal_wallpaper_phone.png"
CUSTOM_SRC_PSP="$SCRIPT_DIR/../pascal_wallpaper_psp.png"
CUSTOM_SRC_ARCH="$SCRIPT_DIR/../arch_linux_wallpaper.png"

SWAYBG_PID=""

check_deps() {
    local missing=()
    case "$WALLPAPER_ENGINE" in
        hyprpaper) command -v hyprpaper &>/dev/null || missing+=("hyprpaper") ;;
        swaybg)    command -v swaybg &>/dev/null || missing+=("swaybg") ;;
        feh)       command -v feh &>/dev/null || missing+=("feh") ;;
    esac
    if ! command -v chafa &>/dev/null; then
        log_i "Chafa chua cai. Preview thumbnail se khong kha dung."
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        if [ "$(id -u)" -eq 0 ]; then
            pacman -S --noconfirm "${missing[@]}" 2>/dev/null || return 1
        elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
            sudo pacman -S --noconfirm "${missing[@]}" 2>/dev/null || return 1
        else
            log_w "Can not auto-install. Run: sudo pacman -S ${missing[*]}"
        fi
    fi
    mkdir -p "$WALLPAPER_DIR" 2>/dev/null || true
}

detect_session() {
    if [ -n "$WAYLAND_DISPLAY" ]; then
        echo "wayland"
    elif [ -n "$DISPLAY" ]; then
        echo "x11"
    else
        echo "headless"
    fi
}

detect_monitor() {
    if [ -z "$MONITOR" ]; then
        if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && command -v hyprctl &>/dev/null; then
            MONITOR=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name // ""' 2>/dev/null) || MONITOR=""
        fi
        if [ -z "$MONITOR" ] && [ -n "$DISPLAY" ] && command -v xrandr &>/dev/null; then
            MONITOR=$(xrandr 2>/dev/null | grep ' connected' | head -1 | awk '{print $1}') || MONITOR=""
        fi
    fi
    [ -z "$MONITOR" ] && MONITOR="eDP-1"
}

list_wallpapers() {
    local exts=("*.jpg" "*.jpeg" "*.png" "*.bmp" "*.gif" "*.webp")
    local files=()
    shopt -s nullglob
    for ext in "${exts[@]}"; do
        for f in "$WALLPAPER_DIR"/$ext; do
            [ -f "$f" ] && files+=("$f")
        done
    done
    shopt -u nullglob
    printf '%s\n' "${files[@]}"
}

get_file_info() {
    local file="$1"
    local name size dims
    name=$(basename "$file")
    size=$(du -h "$file" 2>/dev/null | cut -f1)
    if command -v identify &>/dev/null; then
        dims=$(identify -format "%wx%h" "$file" 2>/dev/null || echo "?x?")
    else
        dims="?x?"
    fi
    echo "${name}|${size}|${dims}|${file}"
}

preview_with_chafa() {
    local file="$1"
    if ! command -v chafa &>/dev/null; then
        tui_msg "PREVIEW" "Chafa chua cai dat.\nCai: sudo pacman -S chafa" 7 45
        return
    fi
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        tui_msg "PREVIEW" "Preview yeu cau terminal." 6 40
        return
    fi
    clear
    local dims
    if command -v identify &>/dev/null; then
        dims=$(identify -format '%wx%h' "$file" 2>/dev/null || echo '?')
    else
        dims="?"
    fi
    echo -e "${CY}=== PREVIEW: $(basename "$file") ===${R}"
    echo -e "${D}Kich thuoc: ${dims} | Dung luong: $(du -h "$file" 2>/dev/null | cut -f1)${R}"
    echo ""

    local cols="${COLUMNS:-80}"
    local lines="${LINES:-24}"
    local preview_h=$((lines - 6))
    [ "$preview_h" -lt 10 ] && preview_h=10
    local preview_w=$((cols - 4))
    [ "$preview_w" -lt 40 ] && preview_w=40

    chafa --stretch "$file" \
        --size "${preview_w}x${preview_h}" \
        --symbols all \
        --color-space rgb \
        2>/dev/null || {
        log_e "Khong the preview file nay"
        read -r -p "Press Enter..."
        return
    }
    echo ""
    echo -e "${D}Press Enter de quay lai, hoac: (A)pply / (R)andom / Enter=back${R}"
    IFS= read -r action || true
    case "${action,,}" in
        a|apply) set_wallpaper "$file" ;;
        r|random) apply_random ;;
        *) ;;
    esac
}

set_wallpaper_hyprpaper() {
    local file="$1"
    if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        log_e "Khong phat hien Hyprland session."
        return 1
    fi
    local abs_file
    abs_file=$(realpath "$file" 2>/dev/null || readlink -f "$file" 2>/dev/null || echo "$file")
    detect_monitor
    hyprctl hyprpaper wallpaper "${MONITOR},${abs_file}" 2>/dev/null || {
        hyprctl hyprpaper preload "${abs_file}" 2>/dev/null || true
        sleep 0.5
        hyprctl hyprpaper wallpaper "${MONITOR},${abs_file}" 2>/dev/null || {
            log_e "Hyprpaper set wallpaper that bai."
            return 1
        }
    }
}

set_wallpaper_swaybg() {
    local file="$1"
    if [ -z "${WAYLAND_DISPLAY:-}" ]; then
        log_e "Khong co Wayland display."
        return 1
    fi
    if [ -n "$SWAYBG_PID" ] && kill -0 "$SWAYBG_PID" 2>/dev/null; then
        kill "$SWAYBG_PID" 2>/dev/null || true
    fi
    nohup swaybg -i "$file" -m fill >/dev/null 2>&1 &
    SWAYBG_PID=$!
}

set_wallpaper_feh() {
    local file="$1"
    if [ -z "${DISPLAY:-}" ]; then
        log_e "Khong co X11 display."
        return 1
    fi
    feh --bg-fill "$file" 2>/dev/null || {
        log_e "Feh set wallpaper that bai."
        return 1
    }
}

set_wallpaper() {
    local file="$1"
    if [ ! -f "$file" ]; then
        log_e "File khong ton tai: $file"
        read -r -p "Press Enter..."
        return
    fi

    local ok=false
    case "$WALLPAPER_ENGINE" in
        hyprpaper) set_wallpaper_hyprpaper "$file" && ok=true ;;
        swaybg)    set_wallpaper_swaybg "$file" && ok=true ;;
        feh)       set_wallpaper_feh "$file" && ok=true ;;
        *)
            log_w "Engine ${WALLPAPER_ENGINE} khong ho tro, auto-detect..."
            local sess detected_engine
            sess=$(detect_session)
            detected_engine=""
            case "$sess" in
                wayland)
                    if set_wallpaper_hyprpaper "$file"; then
                        ok=true; detected_engine="hyprpaper"
                    elif set_wallpaper_swaybg "$file"; then
                        ok=true; detected_engine="swaybg"
                    fi
                    ;;
                x11)
                    if set_wallpaper_feh "$file"; then
                        ok=true; detected_engine="feh"
                    fi
                    ;;
                *)
                    log_e "Khong phat hien display session."
                    read -r -p "Press Enter..."
                    return
                    ;;
            esac
            if $ok && [ -n "$detected_engine" ] && [ -f "$CONFIG_FILE" ]; then
                WALLPAPER_ENGINE="$detected_engine"
                "$CORE" set WALLPAPER_ENGINE "$detected_engine" 2>/dev/null || true
            fi
            ;;
    esac

    if $ok; then
        log_ok "Wallpaper da set: $(basename "$file")"
        notify-send -t 3000 "Wallpaper" "Da doi sang: $(basename "$file")" 2>/dev/null || true
        tui_msg "WALLPAPER" "Da set: $(basename "$file")" 6 50
    else
        log_e "Set wallpaper that bai."
        read -r -p "Press Enter..."
    fi
}

apply_random() {
    local files=()
    while IFS= read -r f; do files+=("$f"); done < <(list_wallpapers)
    if [ ${#files[@]} -eq 0 ]; then
        tui_msg "RANDOM" "Khong co wallpaper nao trong:\n${WALLPAPER_DIR}" 7 55
        return
    fi
    local idx=$((RANDOM % ${#files[@]}))
    local pick="${files[$idx]}"
    set_wallpaper "$pick"
}

import_custom() {
    local count=0

    if [ -f "$CUSTOM_SRC_WIN" ]; then
        cp "$CUSTOM_SRC_WIN" "$WALLPAPER_DIR/arch-rei-wallpaper.jpg" 2>/dev/null && { count=$((count+1)); log_ok "Da copy arch-rei-wallpaper.jpg"; }
    fi
    if [ -f "$CUSTOM_SRC_PHONE" ]; then
        cp "$CUSTOM_SRC_PHONE" "$WALLPAPER_DIR/rei-phone.png" 2>/dev/null && { count=$((count+1)); }
    fi
    if [ -f "$CUSTOM_SRC_PSP" ]; then
        cp "$CUSTOM_SRC_PSP" "$WALLPAPER_DIR/rei-psp.png" 2>/dev/null && { count=$((count+1)); }
    fi
    if [ -f "$CUSTOM_SRC_ARCH" ]; then
        cp "$CUSTOM_SRC_ARCH" "$WALLPAPER_DIR/rei-arch.png" 2>/dev/null && { count=$((count+1)); }
    fi

    if [ "$count" -gt 0 ]; then
        tui_msg "IMPORT" "Da import ${count} wallpaper(s) vao:\n${WALLPAPER_DIR}" 8 55
    else
        tui_msg "IMPORT" "Khong tim thay file custom wallpaper.\nDat trong thu muc calarch/ (pascal_*)." 8 60
    fi
}

main_menu() {
    check_deps
    while true; do
        local wallpaper_count
        wallpaper_count=$(list_wallpapers | wc -l)

        local c
        c=$(tui_menu "WALLPAPER" "Wallpaper Manager (${wallpaper_count} files trong ${WALLPAPER_DIR}):" 16 64 7 \
            "[1]" "Xem danh sach + chon wallpaper" \
            "[2]" "Random wallpaper" \
            "[3]" "Import custom wallpaper (pascal_*)" \
            "[4]" "Doi engine (hyprpaper/swaybg/feh)" \
            "[5]" "Mo thu muc wallpaper" \
            "[6]" "Refresh danh sach" \
            "[B]" "Quay lai") || break
        case "$c" in
            "[1]")
                local files=()
                while IFS= read -r f; do files+=("$f"); done < <(list_wallpapers)
                if [ ${#files[@]} -eq 0 ]; then
                    tui_msg "WALLPAPER" "Khong co file nao trong:\n${WALLPAPER_DIR}" 7 55
                    continue
                fi
                local items=()
                for f in "${files[@]}"; do
                    local info
                    info=$(get_file_info "$f")
                    IFS='|' read -r name size dims path <<< "$info"
                    items+=("$f" "${name}  ${dims}  ${size}")
                done
                local sel
                sel=$(tui_menu "WALLPAPERS" "Chon wallpaper (Enter=preview):" 18 72 12 "${items[@]}") || continue
                preview_with_chafa "$sel"
                ;;
            "[2]") apply_random ;;
            "[3]") import_custom ;;
            "[4]")
                local eng
                eng=$(tui_menu "ENGINE" "Chon wallpaper engine:" 12 40 3 \
                    "hyprpaper" "Hyprland native (default)" \
                    "swaybg"    "Sway/Wayland" \
                    "feh"       "X11 (legacy)") || continue
                if [ -n "$eng" ]; then
                    WALLPAPER_ENGINE="$eng"
                    "$CORE" set WALLPAPER_ENGINE "$eng" 2>/dev/null || true
                    tui_msg "ENGINE" "Engine changed to: ${eng}" 6 40
                fi
                ;;
            "[5]")
                if command -v thunar &>/dev/null; then
                    nohup thunar "$WALLPAPER_DIR" >/dev/null 2>&1 &
                else
                    xdg-open "$WALLPAPER_DIR" 2>/dev/null || true
                fi
                ;;
            "[6]") true ;;
            "[B]") break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main_menu
fi
