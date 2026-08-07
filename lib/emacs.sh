#!/bin/bash
# ============================================================================
# EMACS.SH — Emacs + Org-mode Ultrafocus Setup
# Org-mode, org-roam, org-pomodoro, Obsidian integration
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

NOTES_DIR="$HOME/notes"
OBSIDIAN_VAULT="$NOTES_DIR/obsidian"
ORG_DIR="$NOTES_DIR/org"

install_emacs() {
    if command -v emacs &>/dev/null; then
        log_ok "Emacs da cai"
        return 0
    fi
    log_i "Dang cai Emacs (Wayland)..."
    sudo pacman -S --noconfirm emacs-wayland 2>/dev/null || sudo pacman -S --noconfirm emacs 2>/dev/null || {
        log_e "Failed to install Emacs"
        return 1
    }
    log_ok "Emacs installed"
}

setup_orgmode() {
    mkdir -p "$ORG_DIR" "$HOME/.emacs.d"

    cat > "$HOME/.emacs.d/init.el" << 'INIT_EOF'
;; Ultrafocus: Emacs + Org-mode configuration
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

;; Bootstrap use-package
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(eval-when-compile (require 'use-package))
(setq use-package-always-ensure t)

;; Performance
(setq gc-cons-threshold 100000000)
(setq read-process-output-max (* 1024 1024))
(setq inhibit-startup-message t)
(setq visible-bell nil)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(global-display-line-numbers-mode t)
(setq display-line-numbers-type 'relative)

;; Theme
(use-package catppuccin-theme
  :config
  (load-theme 'catppuccin :no-confirm)
  (setq catppuccin-flavor 'mocha))

;; Font
(set-face-attribute 'default nil :font "JetBrains Mono" :height 120)

;; Org-mode
(use-package org
  :bind (("C-c l" . org-capture)
         ("C-c a" . org-agenda)
         ("C-c c" . org-capture))
  :config
  (setq org-directory "~/notes/org")
  (setq org-default-notes-file (concat org-directory "/inbox.org"))
  (setq org-capture-templates
        '(("t" "Task" entry (file+headline (concat org-directory "/tasks.org") "Inbox")
           "* TODO %? %^G")
          ("n" "Note" entry (file+headline (concat org-directory "/notes.org") "Inbox")
           "* %? :NOTE:")
          ("j" "Journal" entry (file+datetree (concat org-directory "/journal.org"))
           "* %?")))
  (setq org-agenda-files (list org-directory))
  (setq org-todo-keywords '((sequence "TODO(t)" "NEXT(n)" "WAITING(w)" "|" "DONE(d)" "CANCELLED(c)")))
  (setq org-log-done 'time))

;; org-roam — knowledge base
(use-package org-roam
  :after org
  :bind (("C-c n f" . org-roam-node-find)
         ("C-c n i" . org-roam-node-insert)
         ("C-c n c" . org-roam-capture)
         ("C-c n g" . org-roam-graph))
  :config
  (setq org-roam-directory (file-truename "~/notes/org"))
  (org-roam-db-autosync-mode))

;; org-pomodoro
(use-package org-pomodoro
  :bind (("C-c p" . org-pomodoro))
  :config
  (setq org-pomodoro-length 25)
  (setq org-pomodoro-break-length 5))

;; productivity
(use-package which-key :config (which-key-mode))

;; Obsidian integration — bidirectional sync with org-roam
(defun org-to-markdown (org-file)
  "Convert ORG-FILE to markdown in Obsidian vault."
  (interactive "fOrg file: ")
  (let ((md-file (concat (file-name-sans-extension org-file) ".md")))
    (with-temp-buffer
      (insert-file-contents org-file)
      (org-md-convert-to-markdown)
      (write-file md-file))))

(provide 'ultrafocus-emacs)
;; Ultrafocus: Emacs ready. M-x org-agenda to start.
INIT_EOF
    log_ok "Emacs init.el created with Org-mode + org-roam + org-pomodoro"
}

sync_obsidian() {
    mkdir -p "$OBSIDIAN_VAULT" "$ORG_DIR"
    log_i "Dang dong bo Obsidian ↔ Org..."

    local count=0
    for f in "$OBSIDIAN_VAULT"/*.md; do
        [ -f "$f" ] || continue
        local name
        name=$(basename "$f" .md)
        local org_file="$ORG_DIR/${name}.org"
        if [ ! -f "$org_file" ]; then
            echo "* $name" > "$org_file"
            echo ":PROPERTIES:" >> "$org_file"
            echo ":SOURCE: obsidian" >> "$org_file"
            echo ":END:" >> "$org_file"
            echo "" >> "$org_file"
            cat "$f" >> "$org_file"
            count=$((count + 1))
        fi
    done

    for f in "$ORG_DIR"/*.org; do
        [ -f "$f" ] || continue
        local name
        name=$(basename "$f" .org)
        local md_file="$OBSIDIAN_VAULT/${name}.md"
        if [ ! -f "$md_file" ]; then
            head -1 "$f" | sed 's/^\* //' > "$md_file"
            echo "" >> "$md_file"
            echo "*Synced from Org-mode*" >> "$md_file"
            echo "" >> "$md_file"
            grep -v '^:' "$f" | tail -n +2 >> "$md_file" 2>/dev/null || true
            ((count++))
        fi
    done

    log_ok "Synced $count notes between Obsidian and Org"
}

main_menu() {
    while true; do
        local c
        c=$(tui_menu "EMACS" "Ultrafocus Notes Setup:" 14 52 5 \
            "[1]" "Install Emacs (Wayland)" \
            "[2]" "Setup Org-mode + org-roam" \
            "[3]" "Sync Obsidian vault ↔ Org" \
            "[4]" "Mo Emacs" \
            "[B]" "Quay lai") || break
        case "$c" in
            "[1]") install_emacs; read -r -p "Press Enter..." ;;
            "[2]") install_emacs; setup_orgmode; read -r -p "Press Enter..." ;;
            "[3]") sync_obsidian; read -r -p "Press Enter..." ;;
            "[4]")
                nohup emacs >/dev/null 2>&1 &
                log_ok "Emacs dang chay"
                sleep 1
                ;;
            "[B]") break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main_menu
fi
