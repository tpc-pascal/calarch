#!/bin/bash
# ============================================================================
# NOTES.SH — Obsidian Vault Manager
# ============================================================================
# Chay: bash lib/notes.sh

set -euo pipefail

R='\033[0m'; B='\033[1m'; D='\033[0;90m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'; MG='\033[0;35m'

log_i() { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/tui.sh"

VAULT_DIR="$HOME/notes/obsidian"

open_vault() {
    if ! command -v obsidian &>/dev/null; then
        log_e "Obsidian chua cai. Cai bang: sudo pacman -S obsidian"
        read -r -p "Press Enter..."
        return 1
    fi
    if [ -d "$VAULT_DIR" ]; then
        nohup obsidian "$VAULT_DIR" >/dev/null 2>&1 &
        log_ok "Obsidian dang mo vault: $VAULT_DIR"
    else
        log_i "Vault chua ton tai. Tao moi..."
        mkdir -p "$VAULT_DIR"
        nohup obsidian "$VAULT_DIR" >/dev/null 2>&1 &
        log_ok "Da tao va mo vault: $VAULT_DIR"
    fi
    sleep 2
}

create_vault() {
    local name="$1"
    local path="$HOME/notes/$name"
    if [ -d "$path" ]; then
        log_i "Vault '$name' da ton tai"
    else
        mkdir -p "$path"
        cat > "$path/Welcome.md" <<- EOF
# $name

Created: $(date '+%Y-%m-%d %H:%M')
EOF
        log_ok "Vault '$name' da tao tai $path"
    fi
}

backup_vault() {
    local backup_dir="$HOME/notes/backups"
    mkdir -p "$backup_dir"
    local stamp=$(date '+%Y%m%d-%H%M%S')
    if [ -d "$VAULT_DIR" ]; then
        tar czf "$backup_dir/obsidian-$stamp.tar.gz" -C "$HOME/notes" obsidian 2>/dev/null
        log_ok "Backup: $backup_dir/obsidian-$stamp.tar.gz"
    else
        log_e "Vault khong ton tai: $VAULT_DIR"
    fi
    read -r -p "Press Enter..."
}

list_vaults() {
    clear
    echo -e "${MG}=== OBSIDIAN VAULTS ===${R}"
    if [ -d "$HOME/notes" ]; then
        for d in "$HOME/notes"/*/; do
            local name=$(basename "$d")
            local count=$(find "$d" -name '*.md' 2>/dev/null | wc -l)
            echo -e "  ${CY}$name${R} (${count} notes)"
        done
    else
        echo "  (No vaults yet)"
    fi
    echo ""
}

main_menu() {
    while true; do
        local c
        c=$(tui_menu "NOTES" "Chon chuc nang:" 14 48 4 \
            "[1]" "Mo Obsidian vault" \
            "[2]" "Tao vault moi" \
            "[3]" "Backup vault" \
            "[4]" "Xem danh sach vault" \
            "[B]" "Quay lai") || break

        case "$c" in
            "[1]") open_vault ;;
            "[2]")
                local name
                name=$(tui_input "NOTES" "Ten vault moi:" 8 44 "my-vault") || true
                [ -n "$name" ] && create_vault "$name"
                ;;
            "[3]") backup_vault ;;
            "[4]") list_vaults; read -r -p "Press Enter..." ;;
            "[B]") break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main_menu
fi
