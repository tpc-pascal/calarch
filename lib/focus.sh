#!/bin/bash
# ============================================================================
# FOCUS.SH — Focus Tools: Pomodoro, Website Blocker, Focus Mode
# ============================================================================
# Chay: bash lib/focus.sh

set -euo pipefail

R='\033[0m'; B='\033[1m'; D='\033[0;90m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'; MG='\033[0;35m'

log_i() { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_w()  { echo -e "${YEL}[!!]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/tui.sh"
CONFIG_FILE="$SCRIPT_DIR/../calarch.conf"
source "$SCRIPT_DIR/config-load.sh"
calarch_load_config "$CONFIG_FILE"

HOSTS_BACKUP="/var/lib/calarch/hosts.backup"
HOSTS_BACKUP_LEGACY="/tmp/hosts.focus.backup"
BLOCK_MARK_BEGIN="# --- calarch-blocker: begin ---"
BLOCK_MARK_END="# --- calarch-blocker: end ---"

# Build blocklist from config (comma-separated -> array)
BLOCKLIST_SRC="${BLOCKER_SITES:-facebook.com,twitter.com,x.com,instagram.com,reddit.com,tiktok.com,youtube.com,netflix.com}"
BLOCKLIST=()
IFS=',' read -ra SITES <<< "$BLOCKLIST_SRC"
for s in "${SITES[@]}"; do
  s=$(echo "$s" | xargs)  # trim
  [ -n "$s" ] || continue
  BLOCKLIST+=("$s" "www.$s")
done

# --- Pomodoro Timer ---
pomodoro_timer() {
    local work_min="${1:-${POMODORO_WORK_MINUTES:-25}}"
    local break_min="${2:-${POMODORO_BREAK_MINUTES:-5}}"
    local cycles="${3:-${POMODORO_CYCLES:-4}}"

    echo -e "${MG}=== POMODORO ===${R}"
    echo -e "Work: ${work_min}ph | Break: ${break_min}ph | Cycles: ${cycles}"
    echo ""

    for ((c=1; c<=cycles; c++)); do
        echo -e "${CY}--- Cycle $c/$cycles: WORK ($work_min phut) ---${R}"
        for ((m=work_min; m>0; m--)); do
            printf "\r${B}%02d:00${R} remaining... " "$m"
            sleep 60
        done
        echo ""
        notify-send -t 5000 "Pomodoro" "Cycle $c/$cycles: Nghi? ($'\u2728')" 2>/dev/null || true
        echo -e "${GR}Nghi $break_min phut...${R}"

        if [ $c -lt $cycles ]; then
            for ((m=break_min; m>0; m--)); do
                printf "\r${D}Break: %02d:00${R}" "$m"
                sleep 60
            done
            echo ""
            notify-send -t 5000 "Pomodoro" "Cycle $c/$cycles: Bat dau lam viec!" 2>/dev/null || true
        fi
    done
    echo -e "${GR}${B}Hoan thanh $cycles cycles!${R}"
    notify-send -t 8000 "Pomodoro" "Da hoan thanh $cycles cycles!" 2>/dev/null || true
}

# --- Website Blocker ---
# Blocked state = marker section trong /etc/hosts (khong phu thuoc /tmp)
# Backup persistent = /var/lib/calarch/hosts.backup (khoi mat state khi reboot)
blocker_active() {
    [ -f /etc/hosts ] || return 1
    grep -qF "$BLOCK_MARK_BEGIN" /etc/hosts 2>/dev/null
}

_blocker_backup() {
    [ -f "$HOSTS_BACKUP" ] && { echo "$HOSTS_BACKUP"; return; }
    [ -f "$HOSTS_BACKUP_LEGACY" ] && { echo "$HOSTS_BACKUP_LEGACY"; return; }
    return 1
}

strip_block_section() {
    [ -f /etc/hosts ] || return 0
    grep -qF "$BLOCK_MARK_BEGIN" /etc/hosts 2>/dev/null || return 0
    local tmp
    tmp=$(mktemp) || return 1
    awk -v b="$BLOCK_MARK_BEGIN" -v e="$BLOCK_MARK_END" '
        BEGIN { skip=0 }
        index($0, b) == 1 { skip=1; next }
        index($0, e) == 1 { skip=0; next }
        !skip { print }
    ' /etc/hosts > "$tmp"
    # install -m 644: giu mode /etc/hosts (cp tu mktemp se tao 0600)
    sudo install -m 644 "$tmp" /etc/hosts 2>/dev/null
    local rc=$?
    rm -f "$tmp"
    return "$rc"
}

block_websites() {
    [ -f /etc/hosts ] || { log_e "/etc/hosts khong ton tai"; return 1; }
    if blocker_active; then
        log_w "Websites da bi chan tu truoc"
        return 0
    fi

    # Backup lan dau khi hosts con sach (persistent, khong bi mat khi reboot)
    if ! _blocker_backup >/dev/null; then
        sudo mkdir -p /var/lib/calarch 2>/dev/null || true
        sudo cp /etc/hosts "$HOSTS_BACKUP" 2>/dev/null || {
            log_e "Khong the tao backup /etc/hosts — huy chan web"
            return 1
        }
    fi

    # Idempotent: bo section cu truoc khi ghi lai
    strip_block_section || log_w "Khong the strip section cu trong /etc/hosts"

    local tmp
    tmp=$(mktemp) || return 1
    cp /etc/hosts "$tmp" 2>/dev/null || true
    echo "$BLOCK_MARK_BEGIN" >> "$tmp"
    for site in "${BLOCKLIST[@]}"; do
        if ! grep -qF " $site" "$tmp" 2>/dev/null; then
            echo "127.0.0.1 $site" >> "$tmp"
            echo "::1 $site" >> "$tmp"
        fi
    done
    echo "$BLOCK_MARK_END" >> "$tmp"
    if sudo install -m 644 "$tmp" /etc/hosts 2>/dev/null; then
        rm -f "$tmp"
        log_ok "Websites DA CHAN (blocked)"
    else
        rm -f "$tmp"
        log_e "Khong the ghi /etc/hosts"
        return 1
    fi
}

unblock_websites() {
    local bak
    if bak=$(_blocker_backup); then
        sudo install -m 644 "$bak" /etc/hosts 2>/dev/null || log_e "Khong the restore /etc/hosts tu backup"
        sudo rm -f "$bak" 2>/dev/null || true
    else
        strip_block_section || log_w "Khong the strip section trong /etc/hosts"
    fi
    if ! blocker_active; then
        log_ok "Websites DA MO (unblocked)"
    else
        log_w "Chua the unblock hoan toan /etc/hosts"
    fi
}

website_blocker() {
    if blocker_active; then
        unblock_websites
    else
        block_websites
    fi
    read -r -p "Press Enter..."
}

blocker_status() {
    if blocker_active; then
        echo -e "${GR}Trang thai: DANG CHAN${R}"
    else
        echo -e "${D}Trang thai: BINH THUONG${R}"
    fi
}

# --- Focus Mode (Pomodoro + Blocker) ---
focus_mode() {
    echo -e "${MG}=== FOCUS MODE ===${R}"
    echo ""

    if ! blocker_active; then
        log_i "Dang chan web gay mat tap trung..."
        website_blocker  # This blocks and prompts
        log_ok "Web da bi chan"
    else
        log_i "Web da bi chan tu truoc"
    fi

    # Toggle Do Not Disturb via notify-send
    notify-send -t 3000 "Focus Mode" "Da BAT che do tap trung. Pomodoro sap bat dau..." 2>/dev/null || true

    # Tat tam thoi notification (Hyprland)
    if command -v hyprctl &>/dev/null; then
        hyprctl --batch "keyword decoration:drop_shadow 0; keyword misc:disable_autoreload 1" 2>/dev/null || true
    fi

    # --- Ultrafocus: Tat notification system-wide ---
    if command -v gsettings &>/dev/null; then
        gsettings set org.gnome.desktop.notifications show-banners false 2>/dev/null || true
    fi
    if command -v notify-send &>/dev/null; then
        pkill -f "dunst" 2>/dev/null || true
    fi

    echo ""
    log_i "Bat dau Pomodoro..."
    pomodoro_timer "${POMODORO_WORK_MINUTES:-25}" "${POMODORO_BREAK_MINUTES:-5}" "${POMODORO_CYCLES:-4}"

    # Khi xong: hoi co mo block khong
    echo ""
    read -r -p "Mo lai web bi chan? (y/N): " choice
    case "${choice,,}" in
        y|yes)
            website_blocker
            log_ok "Web da duoc mo lai"
            ;;
        *)
            log_i "Web van dang bi chan. Mo bang menu Focus."
            ;;
    esac

    # Khoi phuc Hyprland settings
    if command -v hyprctl &>/dev/null; then
        hyprctl --batch "keyword decoration:drop_shadow 1; keyword misc:disable_autoreload 0" 2>/dev/null || true
    fi
    if command -v gsettings &>/dev/null; then
        gsettings set org.gnome.desktop.notifications show-banners true 2>/dev/null || true
    fi
    if command -v dunst &>/dev/null; then
        nohup dunst >/dev/null 2>&1 &
    fi

    notify-send -t 5000 "Focus Mode" "Focus Mode Complete!" 2>/dev/null || true
}

# --- Ultrafocus: Terminal-Only Mode ---
terminal_only() {
    echo -e "${MG}=== TERMINAL-ONLY MODE ===${R}"
    echo ""
    log_i "Dang chuyen sang che do terminal-only..."

    if command -v hyprctl &>/dev/null; then
        # Tat tat ca cua so GUI tru terminal (kitty)
        hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class != "kitty" and .class != "Alacritty" and .class != "foot") | .pid' 2>/dev/null | while read -r pid; do
            [ -n "$pid" ] && [ "$pid" -gt 0 ] && kill -9 "$pid" 2>/dev/null || true
        done
        log_ok "GUI windows closed (except terminal)"
    fi

    # Khoi dong terminal fullscreen
    if command -v kitty &>/dev/null; then
        nohup kitty --start-as=fullscreen >/dev/null 2>&1 &
    fi

    log_ok "Terminal-only mode active"
    read -r -p "Press Enter..."
}

# --- Menu ---
main_menu() {
    while true; do
        local c
        c=$(tui_menu "FOCUS" "Chon chuc nang:" 14 50 5 \
            "[1]" "Pomodoro Timer (25/5/4 cycles)" \
            "[2]" "Toggle Website Blocker" \
            "[3]" "Focus Mode (Pomodoro + Blocker)" \
            "[4]" "Terminal-Only Mode (kill GUI)" \
            "[B]" "Quay lai") || break

        case "$c" in
            "[1]") pomodoro_timer ;;
            "[2]") website_blocker ;;
            "[3]") focus_mode ;;
            "[4]") terminal_only ;;
            "[B]") break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main_menu
fi
