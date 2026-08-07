#!/bin/bash
# ============================================================================
# SPOTIFY.SH — Spotify + Spicetify Ultrafocus Setup
# Ad-block, custom theme, dark mode
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
CONFIG_FILE="$SCRIPT_DIR/../calarch.conf"
source "$SCRIPT_DIR/config-load.sh"
calarch_load_config "$CONFIG_FILE"

install_spotify() {
    if command -v spotify &>/dev/null; then
        log_ok "Spotify da cai"
        return 0
    fi
    log_i "Dang cai Spotify tu AUR..."
    yay -S --noconfirm spotify 2>/dev/null && log_ok "Spotify installed" || {
        log_e "Failed to install Spotify"
        return 1
    }
}

install_spicetify() {
    if command -v spicetify &>/dev/null; then
        log_ok "Spicetify da cai"
        return 0
    fi
    log_i "Dang cai Spicetify CLI..."
    curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sh 2>/dev/null || {
        yay -S --noconfirm spicetify-cli 2>/dev/null || {
            log_e "Failed to install Spicetify"
            return 1
        }
    }
    log_ok "Spicetify installed"
}

setup_spicetify() {
    if ! command -v spicetify &>/dev/null; then
        install_spicetify
    fi

    log_i "Cau hinh Spicetify..."
    spicetify backup 2>/dev/null || true

    cat > "$HOME/.config/spicetify/config-xpui.ini" << 'SPICE_EOF'
[Setting]
spotify_path = /usr/share/spotify
prefs_path = ~/.config/spotify/prefs
xpui_path = /usr/share/spotify/Apps/xpui.spa
spotify_version = 1.2.0
current_theme = Dribbblish
color_scheme = dark
inject_css = 1
replace_colors = 1
overwrite_assets = 1
check_spicetify_upgrade = 0
fast_forward_rewind = 5
home = 1
SPICE_EOF

    # Install Dribbblish theme
    local theme_dir="$HOME/.config/spicetify/Themes/Dribbblish"
    if [ ! -d "$theme_dir" ]; then
        mkdir -p "$(dirname "$theme_dir")"
        git clone --depth=1 https://github.com/spicetify/spicetify-themes.git /tmp/spicetify-themes 2>/dev/null || true
        if [ -d "/tmp/spicetify-themes/Dribbblish" ]; then
            cp -r "/tmp/spicetify-themes/Dribbblish" "$theme_dir"
            rm -rf /tmp/spicetify-themes
        fi
    fi

    # Ad-block extension
    local ext_dir="$HOME/.config/spicetify/Extensions"
    mkdir -p "$ext_dir"
    if [ ! -f "$ext_dir/adblock.js" ]; then
        curl -sL "https://raw.githubusercontent.com/spicetify/spicetify-cli/master/CustomApps/adblock/adblock.js" \
            -o "$ext_dir/adblock.js" 2>/dev/null || true
    fi

    # Enable adblock extension
    spicetify config extensions adblock.js 2>/dev/null || true
    spicetify config inject_css 1 2>/dev/null || true
    spicetify config replace_colors 1 2>/dev/null || true

    spicetify apply 2>/dev/null && log_ok "Spicetify applied — Dribbblish dark" || log_w "Spicetify apply failed"

    # Fix permissions (Spicetify needs write access to Spotify)
    if [ -d /usr/share/spotify ]; then
        sudo chmod a+wr /usr/share/spotify 2>/dev/null || true
        sudo chmod a+wr /usr/share/spotify/Apps -R 2>/dev/null || true
    fi
}

toggle_adblock() {
    log_i "Toggle Spicetify adblock..."
    if grep -q "adblock" "$HOME/.config/spicetify/config-xpui.ini" 2>/dev/null; then
        spicetify config extensions adblock.js 2>/dev/null || true
        spicetify apply 2>/dev/null && log_ok "Adblock toggled" || log_w "Failed"
    else
        spicetify config extensions adblock.js 2>/dev/null || true
        spicetify apply 2>/dev/null && log_ok "Adblock enabled" || log_w "Failed"
    fi
}

main_menu() {
    while true; do
        local c
        c=$(tui_menu "SPOTIFY" "Ultrafocus Music Setup:" 14 50 5 \
            "[1]" "Install Spotify" \
            "[2]" "Install + config Spicetify" \
            "[3]" "Toggle adblock" \
            "[4]" "Mo Spotify" \
            "[B]" "Quay lai") || break
        case "$c" in
            "[1]") install_spotify; read -r -p "Press Enter..." ;;
            "[2]") install_spotify; install_spicetify; setup_spicetify; read -r -p "Press Enter..." ;;
            "[3]") toggle_adblock; read -r -p "Press Enter..." ;;
            "[4]")
                nohup spotify >/dev/null 2>&1 &
                log_ok "Spotify dang chay"
                sleep 1
                ;;
            "[B]") break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main_menu
fi
