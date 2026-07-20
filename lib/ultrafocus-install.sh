#!/bin/bash
# ============================================================================
# ULTRAFOCUS-INSTALL.SH — Module cai dat Ultrafocus Toolchain
# Goi tu: lib/core.sh, hoac dung doc lap
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE="$SCRIPT_DIR/core.sh"
CONFIG_FILE="$SCRIPT_DIR/../calarch.conf"
PROFILES_DIR="$SCRIPT_DIR/../profiles"

# Color definitions
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'

log_info() { echo -e "${BLUE}ℹ [INFO]${RESET} $*"; }
log_success() { echo -e "${GREEN}✓ [OK]${RESET} $*"; }
log_warn() { echo -e "${YELLOW}⚠ [WARN]${RESET} $*"; }
log_error() { echo -e "${RED}✗ [ERROR]${RESET} $*"; }
log_header() { echo ""; echo -e "${MAGENTA}═════ $* ═════${RESET}"; echo ""; }

try_catch() {
    local desc="$1"; shift
    local cmd="$*"
    echo -e "${GRAY}  → ${desc}...${RESET}"
    if eval "$cmd" >> /tmp/ultrafocus-install.log 2>&1; then
        log_success "${desc}"
        return 0
    else
        log_warn "${desc} — failed"
        return 1
    fi
}

install_base_pkgs() {
    log_header "INSTALL: Base packages"
    local pkgs=("neovim" "rofi" "mpv" "yt-dlp" "curl" "jq")
    local missing=()
    for p in "${pkgs[@]}"; do
        command -v "$p" &>/dev/null || pacman -Qi "$p" &>/dev/null || missing+=("$p")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        try_catch "Install base packages: ${missing[*]}" "sudo pacman -S --noconfirm ${missing[*]} 2>/dev/null; true"
    else
        log_success "All base packages already installed"
    fi
}

install_aur_pkgs() {
    log_header "INSTALL: AUR packages"
    command -v yay &>/dev/null || { log_warn "yay not available, skipping AUR"; return; }
    local aur_pkgs=()
    command -v spotify &>/dev/null || aur_pkgs+=("spotify")
    command -v spicetify &>/dev/null || aur_pkgs+=("spicetify-cli")
    if [ ${#aur_pkgs[@]} -gt 0 ]; then
        try_catch "Install AUR packages: ${aur_pkgs[*]}" "yay -S --noconfirm ${aur_pkgs[*]} 2>/dev/null; true"
    else
        log_success "All AUR packages already installed"
    fi
}

setup_neovim() {
    log_header "SETUP: Neovim + LazyVim"
    bash "$SCRIPT_DIR/neovim.sh" <<< $'[4]\n[B]' 2>/dev/null || true
}

setup_rofi() {
    log_header "SETUP: Rofi launcher"
    # Install rofi if not present
    command -v rofi &>/dev/null || try_catch "Install rofi" "sudo pacman -S --noconfirm rofi"
    # Setup theme
    bash "$SCRIPT_DIR/launcher.sh" <<< $'[1]\n[B]' 2>/dev/null || true
}

setup_firefox() {
    log_header "SETUP: Firefox vertical tabs + privacy"
    bash "$SCRIPT_DIR/firefox.sh" <<< $'[1]\n[2]\n[B]' 2>/dev/null || true
}

setup_kitty_zsh() {
    log_header "SETUP: Kitty + Zsh"
    bash "$SCRIPT_DIR/kitty-ultrafocus.sh" <<< $'[1]\n[2]\n[B]' 2>/dev/null || true
}

setup_spotify() {
    log_header "SETUP: Spotify + Spicetify"
    bash "$SCRIPT_DIR/spotify.sh" <<< $'[2]\n[B]' 2>/dev/null || true
}

setup_emacs() {
    log_header "SETUP: Emacs + Org-mode"
    bash "$SCRIPT_DIR/emacs.sh" <<< $'[2]\n[B]' 2>/dev/null || true
}

install_ultrafocus() {
    log_header "=== CALARCH ULTRAFOCUS TOOLCHAIN ==="
    echo -e "${CYAN}Cai dat bo cong cu Ultrafocus:${RESET}"
    echo "  • Neovim + LazyVim"
    echo "  • Rofi launcher (Super+Space)"
    echo "  • Firefox vertical tabs + privacy"
    echo "  • Kitty terminal + Oh My Zsh"
    echo "  • Spotify + Spicetify (adblock)"
    echo "  • Emacs + Org-mode (notes)"
    echo "  • yt-dlp + mpv (terminal media)"
    echo ""

    install_base_pkgs
    install_aur_pkgs
    setup_neovim
    setup_rofi
    setup_firefox
    setup_kitty_zsh
    setup_spotify
    setup_emacs

    # Config keys
    "$CORE" set LAUNCHER_ENGINE "rofi" 2>/dev/null || true
    "$CORE" set LAUNCHER_THEME "ultrafocus" 2>/dev/null || true
    "$CORE" set FIREFOX_VTABS "yes" 2>/dev/null || true
    "$CORE" set EDITOR_ENGINE "neovim" 2>/dev/null || true
    "$CORE" set EDITOR_DISTRO "lazyvim" 2>/dev/null || true
    "$CORE" set MEDIA_YT_PLAYER "mpv" 2>/dev/null || true
    "$CORE" set MEDIA_QUALITY "1080p" 2>/dev/null || true
    "$CORE" set SPOTIFY_THEME "dribbblish" 2>/dev/null || true
    "$CORE" set SPOTIFY_ADBLOCK "yes" 2>/dev/null || true
    "$CORE" set NOTES_ENGINE "emacs-org" 2>/dev/null || true

    log_header "ULTRAFOCUS TOOLCHAIN INSTALLATION COMPLETE"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    install_ultrafocus
fi
