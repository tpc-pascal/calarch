#!/bin/bash
# ============================================================================
# LAUNCHER.SH — Rofi Ultrafocus Launcher
# Application menu, web search, clipboard, calculator
# ============================================================================
set -euo pipefail

R='\033[0m'; B='\033[1m'; D='\033[0;90m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'; MG='\033[0;35m'

log_i() { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/tui.sh"
CONFIG_FILE="$SCRIPT_DIR/../calarch.conf"
source "$SCRIPT_DIR/config-load.sh"
calarch_load_config "$CONFIG_FILE"

ROFI_CONF_DIR="$HOME/.config/rofi"
ROFI_THEME="$ROFI_CONF_DIR/ultrafocus.rasi"
ROFI_CONFIG="$ROFI_CONF_DIR/config.rasi"

install_rofi() {
    if command -v rofi &>/dev/null; then
        log_ok "Rofi da cai"
        return 0
    fi
    log_i "Dang cai rofi..."
    sudo pacman -S --noconfirm rofi 2>/dev/null && log_ok "Da cai rofi" || {
        log_e "Khong the cai rofi"
        return 1
    }
}

setup_theme() {
    mkdir -p "$ROFI_CONF_DIR"
    cat > "$ROFI_THEME" << 'THEME_EOF'
* {
    font: "JetBrains Mono Nerd Font 12";
    background: #1e1e2e;
    background-alt: #2e2e3e;
    foreground: #cdd6f4;
    selected: #89b4fa;
    active: #a6e3a1;
    urgent: #f38ba8;
    textbox: #cdd6f4;
}
window {
    transparency: "real";
    location: center;
    anchor: center;
    fullscreen: false;
    width: 600px;
    x-offset: 0px;
    y-offset: 0px;
    enabled: true;
    border-radius: 8px;
    border: 1px solid #313244;
    background-color: @background;
}
mainbox {
    enabled: true;
    spacing: 8px;
    padding: 12px;
    background-color: transparent;
    children: [ "inputbar", "listview" ];
}
inputbar {
    enabled: true;
    spacing: 4px;
    padding: 8px;
    background-color: @background-alt;
    border-radius: 6px;
    children: [ "textbox-prompt-colon", "entry" ];
}
textbox-prompt-colon {
    enabled: true;
    expand: false;
    str: ">";
    text-color: @selected;
}
entry {
    enabled: true;
    text-color: @foreground;
    cursor: "default";
    placeholder: "Search...";
    placeholder-color: @textbox;
}
listview {
    enabled: true;
    columns: 1;
    lines: 8;
    cycle: true;
    dynamic: true;
    scrollbar: true;
    spacing: 4px;
    padding: 4px 0px;
    background-color: transparent;
}
element {
    enabled: true;
    spacing: 8px;
    padding: 8px;
    border-radius: 4px;
    background-color: transparent;
    text-color: @foreground;
}
element selected {
    enabled: true;
    background-color: @selected;
    text-color: #1e1e2e;
}
element-icon {
    size: 24px;
}
element-text {
    text-color: inherit;
    vertical-align: 0.5;
    horizontal-align: 0.0;
}
THEME_EOF

    cat > "$ROFI_CONFIG" << 'CONFIG_EOF'
configuration {
    modi: "drun,run,window,combi";
    combi-modi: "drun,run";
    show-icons: true;
    icon-theme: "Papirus";
    display-drun: "Apps";
    display-run: "Run";
    display-window: "Window";
    display-combi: "All";
    terminal: "kitty";
    drun-display-format: "{name}";
    window-format: "{w} · {c} · {t}";
    font: "JetBrains Mono Nerd Font 12";
}
@theme "ultrafocus"
CONFIG_EOF
    log_ok "Rofi theme configured: ultrafocus"
}

setup_keybinds() {
    local hypr_conf="$HOME/.config/hypr/hyprland.conf"
    if [ -f "$hypr_conf" ]; then
        if ! grep -q "SUPER, Space, exec.*rofi" "$hypr_conf" 2>/dev/null; then
            cat >> "$hypr_conf" << 'BIND_EOF'

# Ultrafocus: Rofi Launcher
bind = SUPER, Space, exec, rofi -show combi
bind = SUPER, R, exec, rofi -show run
bind = SUPER, W, exec, rofi -show window
BIND_EOF
            log_ok "Rofi keybinds added: Super+Space, Super+R, Super+W"
        else
            log_i "Rofi keybinds already configured"
        fi
    fi
}

toggle_launcher() {
    if pgrep -x "rofi" &>/dev/null; then
        pkill -x rofi 2>/dev/null || true
        log_ok "Rofi stopped"
    else
        rofi -show combi &
        log_ok "Rofi launched"
    fi
}

main_menu() {
    while true; do
        local c
        c=$(tui_menu "LAUNCHER" "Rofi Ultrafocus Launcher:" 14 52 5 \
            "[1]" "Setup Rofi + Ultrafocus theme" \
            "[2]" "Setup Hyprland keybinds (Super+Space)" \
            "[3]" "Rofi: Application menu" \
            "[4]" "Rofi: Window switcher" \
            "[B]" "Quay lai") || break
        case "$c" in
            "[1]")
                install_rofi
                setup_theme
                read -r -p "Press Enter..."
                ;;
            "[2]")
                setup_keybinds
                read -r -p "Press Enter..."
                ;;
            "[3]")
                rofi -show combi &
                sleep 1
                ;;
            "[4]")
                rofi -show window &
                sleep 1
                ;;
            "[B]") break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main_menu
fi
