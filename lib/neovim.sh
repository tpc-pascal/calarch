#!/bin/bash
# ============================================================================
# NEOVIM.SH — Neovim + LazyVim Ultrafocus Setup
# LazyVim distro, LSP servers, formatters, keybinds
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

install_neovim() {
    if command -v nvim &>/dev/null; then
        log_ok "Neovim da cai: $(nvim --version 2>/dev/null | head -1)"
        return 0
    fi
    log_i "Dang cai Neovim..."
    sudo pacman -S --noconfirm neovim 2>/dev/null && log_ok "Neovim installed" || {
        log_e "Failed to install neovim"
        return 1
    }
}

install_lazyvim() {
    local nvim_dir="$HOME/.config/nvim"
    if [ -d "$nvim_dir" ]; then
        if [ -f "$nvim_dir/lazy-lock.json" ]; then
            log_ok "LazyVim da duoc cai dat"
            return 0
        fi
        log_i "Phat hien $nvim_dir cu, backup..."
        mv "$nvim_dir" "${nvim_dir}.bak.$(date +%Y%m%d-%H%M%S)"
    fi

    log_i "Cloning LazyVim starter..."
    git clone --depth=1 https://github.com/LazyVim/starter "$nvim_dir" 2>/dev/null && {
        rm -rf "$nvim_dir/.git"
        log_ok "LazyVim starter cloned"
    } || {
        log_w "Git clone failed, thu phuong phap khac..."
        mkdir -p "$nvim_dir"
        cat > "$nvim_dir/init.lua" << 'INIT_EOF'
-- Ultrafocus: LazyVim bootstrap
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "lazyvim.plugins.extras.editor.telescope" },
    { import = "lazyvim.plugins.extras.lang.typescript" },
    { import = "lazyvim.plugins.extras.lang.json" },
    { import = "lazyvim.plugins.extras.lang.markdown" },
    { import = "lazyvim.plugins.extras.lang.rust" },
    { import = "lazyvim.plugins.extras.lang.python" },
    { import = "lazyvim.plugins.extras.lang.go" },
    { import = "lazyvim.plugins.extras.lang.lua" },
    { import = "lazyvim.plugins.extras.lang.bash" },
    { import = "lazyvim.plugins.extras.lang.yaml" },
    { import = "lazyvim.plugins.extras.formatting.prettier" },
    { import = "lazyvim.plugins.extras.formatting.stylua" },
    { import = "lazyvim.plugins.extras.coding.yanky" },
    { import = "lazyvim.plugins.extras.ui.mini-animate" },
}, {
    defaults = { lazy = true, version = false },
    install = { colorscheme = { "catppuccin" } },
    checker = { enabled = false },
    performance = {
        rtp = { disabled_plugins = { "gzip", "matchit", "matchparen", "netrwPlugin", "tarPlugin", "tohtml", "tutor", "zipPlugin" } }
    },
})
INIT_EOF
        log_ok "LazyVim init.lua created"
    }
}

install_lsps() {
    log_i "Cai dat LSP servers..."

    # Binary -> npm package (ten package khac ten binary: tsc, prettierd, vscode-*-language-server)
    local -A npm_lsps=(
        [typescript-language-server]=typescript-language-server
        [tsc]=typescript
        [prettierd]=@fsouza/prettierd
        [vscode-html-language-server]=vscode-langservers-extracted
    )
    local bin pkg
    for bin in "${!npm_lsps[@]}"; do
        command -v "$bin" &>/dev/null && continue
        pkg="${npm_lsps[$bin]}"
        sudo npm install -g "$pkg" 2>/dev/null && log_ok "npm: $pkg" || log_w "npm: $pkg failed"
    done

    local pacman_lsps=("lua-language-server" "bash-language-server" "yaml-language-server" "marksman" "texlab" "ruff")
    for lsp in "${pacman_lsps[@]}"; do
        command -v "$lsp" &>/dev/null && continue
        sudo pacman -S --noconfirm "$lsp" 2>/dev/null && log_ok "pacman: $lsp" || log_w "pacman: $lsp failed"
    done

    if ! command -v rust-analyzer &>/dev/null; then
        if command -v rustup &>/dev/null; then
            rustup component add rust-analyzer 2>/dev/null && log_ok "rust-analyzer installed via rustup" || true
        fi
    fi

    if ! command -v pyright &>/dev/null; then
        sudo npm install -g pyright 2>/dev/null && log_ok "pyright installed" || true
    fi

    log_ok "LSP servers installation complete"
}

install_formatters() {
    log_i "Cai dat formatters..."

    for fmt in "shfmt" "stylua" "prettier"; do
        command -v "$fmt" &>/dev/null && continue
        case "$fmt" in
            shfmt|stylua) sudo pacman -S --noconfirm "$fmt" 2>/dev/null && log_ok "$fmt" || true ;;
            prettier) sudo npm install -g prettier 2>/dev/null && log_ok "prettier" || true ;;
        esac
    done

    log_ok "Formatters installation complete"
}

main_menu() {
    while true; do
        local c
        c=$(tui_menu "NEOVIM" "Ultrafocus Editor Setup:" 14 54 5 \
            "[1]" "Install Neovim + LazyVim" \
            "[2]" "Install LSP servers" \
            "[3]" "Install formatters" \
            "[4]" "Install tat ca" \
            "[B]" "Quay lai") || break
        case "$c" in
            "[1]") install_neovim; install_lazyvim; read -r -p "Press Enter..." ;;
            "[2]") install_lsps; read -r -p "Press Enter..." ;;
            "[3]") install_formatters; read -r -p "Press Enter..." ;;
            "[4]") install_neovim; install_lazyvim; install_lsps; install_formatters; read -r -p "Press Enter..." ;;
            "[B]") break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main_menu
fi
