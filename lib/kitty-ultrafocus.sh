#!/bin/bash
# ============================================================================
# KITTY-ULTRAFOCUS.SH — Kitty Terminal + Zsh Ultrafocus Config
# Minimal theme, keybinds, Oh My Zsh + plugins
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
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

setup_kitty() {
    mkdir -p "$HOME/.config/kitty"
    cat > "$HOME/.config/kitty/kitty.conf" << 'KITTY_EOF'
# Ultrafocus: Kitty Terminal Config
font_family JetBrains Mono Nerd Font
bold_font JetBrains Mono Nerd Font Bold
italic_font JetBrains Mono Nerd Font Italic
font_size 12.0

# Colors — Catppuccin Mocha
foreground #cdd6f4
background #1e1e2e
selection_foreground #1e1e2e
selection_background #f5e0dc
url_color #f5e0dc
cursor #f5e0dc
cursor_shape beam
cursor_beam_thickness 1.5

# Black
color0 #45475a
color8 #585b70
# Red
color1 #f38ba8
color9 #f38ba8
# Green
color2 #a6e3a1
color10 #a6e3a1
# Yellow
color3 #f9e2af
color11 #f9e2af
# Blue
color4 #89b4fa
color12 #89b4fa
# Magenta
color5 #f5c2e7
color13 #f5c2e7
# Cyan
color6 #94e2d5
color14 #94e2d5
# White
color7 #bac2de
color15 #a6adc8

background_opacity 0.88
background_blur 30
dynamic_background_opacity yes

scrollback_lines 50000
scrollback_pager_history_size 500
wheel_scroll_multiplier 5.0
touch_scroll_multiplier 5.0

mouse_hide_wait 2.0
hide_window_decorations no
window_padding_width 4
window_margin_width 0
single_window_margin_width 0
confirm_os_window_close 0

shell_integration enabled
allow_remote_control yes
update_check_interval 0

# Ultrafocus keybinds
map ctrl+shift+space launch --type=overlay rofi -show combi
map ctrl+shift+f toggle_fullscreen
map ctrl+shift+enter new_window
map ctrl+shift+right next_tab
map ctrl+shift+left previous_tab
map ctrl+shift+t new_tab
map ctrl+shift+q close_window
map ctrl+shift+z toggle_layout stack
map ctrl+shift+o launch --stdin-source=@screen_scrollback --stdin-add-formatting less
KITTY_EOF
    log_ok "Kitty configured — Catppuccin Mocha theme"
}

setup_zsh() {
    if ! command -v zsh &>/dev/null; then
        sudo pacman -S --noconfirm zsh zsh-completions 2>/dev/null && log_ok "Zsh installed" || {
            log_e "Failed to install zsh"; return 1
        }
    fi

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended 2>/dev/null || true
    fi

    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    mkdir -p "$ZSH_CUSTOM/plugins"

    for repo in "zsh-users/zsh-autosuggestions" "zsh-users/zsh-syntax-highlighting" "MichaelAquilina/zsh-you-should-use"; do
        local plugin_name="${repo##*/}"
        if [ ! -d "$ZSH_CUSTOM/plugins/$plugin_name" ]; then
            git clone --depth=1 "https://github.com/$repo" "$ZSH_CUSTOM/plugins/$plugin_name" 2>/dev/null || true
        fi
    done

    local p10k_dir="$ZSH_CUSTOM/themes/powerlevel10k"
    if [ ! -d "$p10k_dir" ]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir" 2>/dev/null || true
    fi

    cat > "$HOME/.zshrc" << 'ZSHRC_EOF'
# Ultrafocus: ZSH Configuration
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
POWERLEVEL9K_MODE="nerdfont-complete"
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(context dir vcs)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status background_jobs time)
POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_unique
POWERLEVEL9K_CONTEXT_DEFAULT_FG=075

plugins=(
    git
    docker docker-compose
    npm node
    archlinux systemd
    zsh-autosuggestions
    zsh-syntax-highlighting
    zsh-you-should-use
    zsh-completions
    sudo
    history
    copypath
    copyfile
)

source "$ZSH/oh-my-zsh.sh"

# Ultrafocus aliases
alias nv='nvim'
alias vim='nvim'
alias yt='bash ~/.config/calarch/yt-video.sh'
alias anime='bash ~/.config/calarch/anime.sh'
alias spot='spotify'
alias god='pascal-mode'
alias ff='firefox'
alias kitty='kitty'
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first'
alias lt='eza -T --icons'
alias cat='bat'
alias top='btop'
alias grep='rg'
alias du='dust'
alias df='duf'
alias ps='procs'
alias diff='delta'
alias find='fd'

# Ultrafocus tools
export EDITOR=nvim
export VISUAL=nvim
export BROWSER=firefox
export TERMINAL=kitty

# Node.js
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
    *":$PNPM_HOME:"*) ;;
    *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# Rust
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

# Go
export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
ZSHRC_EOF
    log_ok "Zsh + Oh My Zsh + plugins configured"

    if [ "$SHELL" != "$(which zsh)" ]; then
        chsh -s "$(which zsh)" 2>/dev/null && log_ok "Default shell changed to zsh" || log_i "Could not change shell (run: chsh -s /usr/bin/zsh)"
    fi
}

main_menu() {
    while true; do
        local c
        c=$(tui_menu "KITTY + ZSH" "Ultrafocus Terminal Setup:" 14 52 4 \
            "[1]" "Setup Kitty (Catppuccin theme)" \
            "[2]" "Setup Oh My Zsh + plugins" \
            "[3]" "Setup Zsh aliases + env" \
            "[B]" "Quay lai") || break
        case "$c" in
            "[1]") setup_kitty; read -r -p "Press Enter..." ;;
            "[2]") setup_zsh; read -r -p "Press Enter..." ;;
            "[3]") setup_zsh; read -r -p "Press Enter..." ;;
            "[B]") break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main_menu
fi
