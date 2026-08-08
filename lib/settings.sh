#!/bin/bash
# ============================================================================
# SETTINGS.SH — Settings Panel (3 submenus: System, Services, Apps)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/tui.sh"
CORE="$SCRIPT_DIR/core.sh"
CONFIG_FILE="$SCRIPT_DIR/../calarch.conf"
source "$SCRIPT_DIR/config-load.sh"
calarch_load_config "$CONFIG_FILE"

R='\033[0m'; B='\033[1m'; D='\033[0;90m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'; MG='\033[0;35m'
SUPER_SCRIPT="$SCRIPT_DIR/super-mode.sh"
EVENT_MON="$SCRIPT_DIR/hyprland-event-monitor.sh"
ROTATOR="$SCRIPT_DIR/cf-xz6-rotator.sh"
FOCUS_SH="$SCRIPT_DIR/focus.sh"
NOTES_SH="$SCRIPT_DIR/notes.sh"
HOSTS_BACKUP="/var/lib/calarch/hosts.backup"
HOSTS_BACKUP_LEGACY="/tmp/hosts.focus.backup"
BLOCK_MARK_BEGIN="# --- calarch-blocker: begin ---"
BLOCK_MARK_END="# --- calarch-blocker: end ---"
FOCUS_FLAG="/tmp/focus.mode.flag"
LAUNCHER_SH="$SCRIPT_DIR/launcher.sh"
FIREFOX_SH="$SCRIPT_DIR/firefox.sh"
KITTY_UF_SH="$SCRIPT_DIR/kitty-ultrafocus.sh"
NEOVIM_SH="$SCRIPT_DIR/neovim.sh"
SPOTIFY_SH="$SCRIPT_DIR/spotify.sh"
EMACS_SH="$SCRIPT_DIR/emacs.sh"
YT_SH="$SCRIPT_DIR/yt-video.sh"

log_i()  { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_w()  { echo -e "${YEL}[!!]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }

has() { command -v "$1" &>/dev/null; }

# ==================================================================
# STATE READERS
# ==================================================================
super_on()     { pgrep -f "super-mode.sh" &>/dev/null; }
affinity_on()  { pgrep -f "hyprland-event-monitor.sh" &>/dev/null; }
eco_on()       { [ -f /sys/devices/platform/panasonic/eco_mode ] && [ "$(cat /sys/devices/platform/panasonic/eco_mode)" = "1" ]; }
uv_on()        { has intel-undervolt && sudo intel-undervolt read 2>/dev/null | grep -qE ':\s*-[0-9]'; }
rotate_on()    { systemctl is-active iio-sensor-proxy &>/dev/null; }
touch_on()     { xinput list --name-only 2>/dev/null | grep -qi touchpad; }
maint_on()     { systemctl is-enabled godmode-clean.timer &>/dev/null 2>&1; }
dock_on()      { systemctl is-active docker &>/dev/null; }
kvm_on()       { systemctl is-active libvirtd &>/dev/null; }
ollama_on()    { systemctl is-active ollama &>/dev/null; }
obs_on()       { command -v obsidian &>/dev/null; }
block_on()     { blocker_active; }
notes_on()     { command -v obsidian &>/dev/null; }
focus_on()     { [ -f "$FOCUS_FLAG" ]; }
launcher_on()  { command -v rofi &>/dev/null; }
firefox_on()   { local f; for f in "$HOME/.mozilla/firefox"/*/chrome/userChrome.css; do [ -f "$f" ] && return 0; done; return 1; }
neovim_on()    { command -v nvim &>/dev/null; }
spotify_on()   { command -v spicetify &>/dev/null; }
emacs_on()     { command -v emacs &>/dev/null; }

# ==================================================================
# WEBSITE BLOCKER HELPERS (shared logic voi focus.sh)
# Trang thai block = marker section trong /etc/hosts (khong phu thuoc /tmp)
# ==================================================================
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
    # install -m 644: giu nguyen mode cua /etc/hosts (cp tu mktemp se thanh 0600)
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

    if ! _blocker_backup >/dev/null; then
        sudo mkdir -p /var/lib/calarch 2>/dev/null || true
        sudo cp /etc/hosts "$HOSTS_BACKUP" 2>/dev/null || {
            log_e "Khong the tao backup /etc/hosts — huy chan web"
            return 1
        }
    fi

    strip_block_section || log_w "Khong the strip section cu trong /etc/hosts"

    local tmp
    tmp=$(mktemp) || return 1
    cp /etc/hosts "$tmp" 2>/dev/null || true
    echo "$BLOCK_MARK_BEGIN" >> "$tmp"
    local sites="${BLOCKER_SITES:-facebook.com,twitter.com,x.com,instagram.com,reddit.com,tiktok.com,youtube.com,netflix.com}"
    local IFS=','; read -ra ADDR <<< "$sites"
    for entry in "${ADDR[@]}"; do
        entry="${entry#"${entry%%[![:space:]]*}"}"
        entry="${entry%"${entry##*[![:space:]]}"}"
        [ -n "$entry" ] || continue
        for s in "$entry" "www.$entry"; do
            if ! grep -qF " $s" "$tmp" 2>/dev/null; then
                echo "127.0.0.1 $s" >> "$tmp"
                echo "::1 $s" >> "$tmp"
            fi
        done
    done
    echo "$BLOCK_MARK_END" >> "$tmp"
    if sudo install -m 644 "$tmp" /etc/hosts 2>/dev/null; then
        rm -f "$tmp"
        log_ok "Blocker ON"
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
        log_ok "Blocker OFF"
    else
        log_w "Chua the restore /etc/hosts — backup tai $HOSTS_BACKUP"
    fi
}

# ==================================================================
# TOGGLE FUNCTIONS
# ==================================================================
toggle_super() {
    if super_on; then pkill -f "super-mode.sh" 2>/dev/null && log_ok "Super Mode OFF" || log_w "Super Mode OFF failed"
    else nohup bash "$SUPER_SCRIPT" >/dev/null 2>&1 & log_ok "Super Mode ON"; fi
}
toggle_affinity() {
    if affinity_on; then pkill -f "hyprland-event-monitor.sh" 2>/dev/null && log_ok "Affinity OFF" || log_w "Affinity OFF failed"
    else nohup bash "$EVENT_MON" >/dev/null 2>&1 & log_ok "Affinity ON"; fi
}
toggle_eco() {
    local p="/sys/devices/platform/panasonic/eco_mode" limit
    if [ ! -f "$p" ]; then log_w "Eco mode N/A"; return; fi
    limit=$("$CORE" get ECO_CHARGE_LIMIT 2>/dev/null || echo "80")
    if eco_on; then echo 0 | sudo tee "$p" >/dev/null && log_ok "Eco OFF (100%)" || log_w "Eco OFF failed"
    else echo 1 | sudo tee "$p" >/dev/null && log_ok "Eco ON (${limit}%)" || log_w "Eco ON failed"; fi
}
toggle_uv() {
    if uv_on; then log_w "Undervolt: reset can reboot"
    elif has intel-undervolt; then
      "$CORE" set UNDERVOLT_CPU "${UNDERVOLT_CPU:--50}" 2>/dev/null || log_w "Khong set duoc UNDERVOLT_CPU"
      "$CORE" set UNDERVOLT_GPU "${UNDERVOLT_GPU:--20}" 2>/dev/null || log_w "Khong set duoc UNDERVOLT_GPU"
      "$CORE" set UNDERVOLT_CACHE "${UNDERVOLT_CACHE:--50}" 2>/dev/null || log_w "Khong set duoc UNDERVOLT_CACHE"
      log_ok "Undervolt applied via core.sh (safety active)"
    fi
}
toggle_rotate() {
    if rotate_on; then
        sudo systemctl disable --now iio-sensor-proxy 2>/dev/null && log_ok "Rotate OFF" || log_w "Rotate OFF failed"
        pkill -f "cf-xz6-rotator.sh" 2>/dev/null || true
    else
        sudo systemctl enable --now iio-sensor-proxy 2>/dev/null && log_ok "Rotate ON" || log_w "Rotate ON failed"
        nohup bash "$ROTATOR" >/dev/null 2>&1 &
    fi
}
toggle_touch() {
    local id
    id=$(xinput list | grep -i touchpad | grep -oP 'id=\K\d+' || echo "")
    [ -z "$id" ] && { log_w "No touchpad"; return; }
    if touch_on; then xinput set-prop "$id" "Device Enabled" 0 2>/dev/null && log_ok "Touchpad OFF" || log_w "Touchpad OFF failed"
    else xinput set-prop "$id" "Device Enabled" 1 2>/dev/null && xinput set-prop "$id" "libinput Tapping Enabled" 1 2>/dev/null && log_ok "Touchpad ON" || log_w "Touchpad ON failed"; fi
}
toggle_maint() {
    if maint_on; then sudo systemctl disable --now godmode-clean.timer 2>/dev/null && log_ok "Timer OFF" || log_w "Timer OFF failed"
    else sudo systemctl enable --now godmode-clean.timer 2>/dev/null && log_ok "Timer ON" || log_w "Timer ON failed"; fi
}
toggle_dock() {
    if dock_on; then sudo systemctl disable --now docker docker.socket 2>/dev/null && log_ok "Docker OFF" || log_w "Docker OFF failed"
    else sudo systemctl enable --now docker docker.socket 2>/dev/null && log_ok "Docker ON" || log_w "Docker ON failed"; fi
}
toggle_kvm() {
    if kvm_on; then sudo systemctl disable --now libvirtd 2>/dev/null && log_ok "KVM OFF" || log_w "KVM OFF failed"
    else sudo systemctl enable --now libvirtd 2>/dev/null && log_ok "KVM ON" || log_w "KVM ON failed"; fi
}
toggle_ollama() {
    if ollama_on; then sudo systemctl disable --now ollama 2>/dev/null && log_ok "Ollama OFF" || log_w "Ollama OFF failed"
    else sudo systemctl enable --now ollama 2>/dev/null && log_ok "Ollama ON" || log_w "Ollama ON failed"; fi
}
toggle_obs() {
    if obs_on; then log_ok "Obsidian ready"
    else
        sudo pacman -S --noconfirm obsidian 2>/dev/null && log_ok "Obsidian installed" || log_w "Install fail"
    fi
    mkdir -p "$HOME/notes/obsidian"
}
toggle_block() {
    if block_on; then
        unblock_websites
    else
        block_websites
    fi
}
toggle_notes() {
    if [ -f "$NOTES_SH" ]; then bash "$NOTES_SH"
    else log_e "Missing $NOTES_SH"; fi
}
toggle_focus() {
    if focus_on; then
        rm -f "$FOCUS_FLAG"
        if blocker_active; then
            unblock_websites
        fi
        log_ok "Focus OFF"
    else
        touch "$FOCUS_FLAG"
        if [ -f "$FOCUS_SH" ]; then bash "$FOCUS_SH"
        else rm -f "$FOCUS_FLAG"; log_e "Missing $FOCUS_SH"; fi
    fi
}
toggle_launcher() {
    if [ -f "$LAUNCHER_SH" ]; then bash "$LAUNCHER_SH"
    else log_e "Missing $LAUNCHER_SH"; fi
}
toggle_firefox() {
    if [ -f "$FIREFOX_SH" ]; then bash "$FIREFOX_SH"
    else log_e "Missing $FIREFOX_SH"; fi
}
toggle_neovim() {
    if [ -f "$NEOVIM_SH" ]; then bash "$NEOVIM_SH"
    else log_e "Missing $NEOVIM_SH"; fi
}
toggle_spotify() {
    if [ -f "$SPOTIFY_SH" ]; then bash "$SPOTIFY_SH"
    else log_e "Missing $SPOTIFY_SH"; fi
}
toggle_emacs() {
    if [ -f "$EMACS_SH" ]; then bash "$EMACS_SH"
    else log_e "Missing $EMACS_SH"; fi
}

# ==================================================================
# GENERIC: build checklist + apply for a group of tags
# ==================================================================
# tag list per group
SYSTEM_TAGS=(super affinity eco uv rotate touch)
SERVICES_TAGS=(dock kvm ollama maint)
APPS_TAGS=(obs block notes focus launcher firefox neovim spotify emacs)

build_group() {
    local group_name="$1"; shift
    local tags=("$@")
    local items=() sel_items=() state desc disp

    for item in "${tags[@]}"; do
        case "$item" in
            super)   state=$(super_on && echo "ON" || echo "OFF");    desc="Super Mode Daemon              auto CPU/GPU/thermal";;
            affinity)state=$(affinity_on && echo "ON" || echo "OFF"); desc="CPU Affinity Engine             active 0,1 | bg 2,3";;
            eco)     state=$(eco_on && echo "ON" || echo "OFF");      desc="Eco Mode                        80% charge limit";;
            uv)      state=$(uv_on && echo "ON" || echo "OFF");       desc="Undervolt                       -50/-20/-50mV";;
            rotate)  state=$(rotate_on && echo "ON" || echo "OFF");   desc="Auto-rotate                     screen rotation sensor";;
            touch)   state=$(touch_on && echo "ON" || echo "OFF");    desc="Touchpad gestures               tapping + scroll";;
            maint)   state=$(maint_on && echo "ON" || echo "OFF");    desc="Auto-maintenance timer          CN 23:00";;
            dock)    state=$(dock_on && echo "ON" || echo "OFF");     desc="Docker daemon                   container runtime";;
            kvm)     state=$(kvm_on && echo "ON" || echo "OFF");      desc="KVM/libvirtd                    virtual machine host";;
            ollama)  state=$(ollama_on && echo "ON" || echo "OFF");   desc="Ollama AI                       local LLM + OpenCode";;
            obs)     state=$(obs_on && echo "ON" || echo "OFF");      desc="Obsidian Notes                  vault ~/notes/";;
            block)   state=$(block_on && echo "ON" || echo "OFF");    desc="Website Blocker                 FB, Reddit, YouTube";;
            notes)   state=$(notes_on && echo "ON" || echo "OFF");    desc="Notes Manager                   Obsidian vault manager";;
            focus)   state=$(focus_on && echo "ON" || echo "OFF");    desc="Focus Mode                      Pomodoro + site blocker";;
            launcher)state=$(launcher_on && echo "ON" || echo "OFF"); desc="Rofi Launcher                   Ultrafocus theme";;
            firefox) state=$(firefox_on && echo "ON" || echo "OFF");  desc="Firefox Config                  Vertical tabs + privacy";;
            neovim)  state=$(neovim_on && echo "ON" || echo "OFF");   desc="Neovim + LazyVim                Editor + LSP servers";;
            spotify) state=$(spotify_on && echo "ON" || echo "OFF");  desc="Spotify + Spicetify             Adblock + Dribbblish";;
            emacs)   state=$(emacs_on && echo "ON" || echo "OFF");    desc="Emacs + Org-mode                Notes + org-roam";;
        esac
        disp="$desc  [$state]"
        items+=("$item" "$disp" "$state")
        [ "$state" = "ON" ] && sel_items+=("$disp")
    done

    # Pre-select cac muc dang ON (dung cu phap --selected cua gum)
    local sel_list=""
    [ ${#sel_items[@]} -gt 0 ] && sel_list=$(IFS=','; printf '%s' "${sel_items[*]}")

    local sel
    sel=$(tui_checklist "SETTINGS — $group_name" \
        "SPACE=toggle | ENTER=apply | ESC=back" \
        18 68 --selected "$sel_list" "${items[@]}") || return 1
    echo "$sel"
}

apply_tags() {
    local sel="$1"; shift
    local tags=("$@")
    for tag in "${tags[@]}"; do
        local want=0 cur=0
        echo "$sel" | grep -q "$tag" && want=1
        case "$tag" in
            super)   super_on && cur=1;;   affinity)affinity_on && cur=1;;
            eco)     eco_on && cur=1;;     uv)      uv_on && cur=1;;
            rotate)  rotate_on && cur=1;;  touch)   touch_on && cur=1;;
            maint)   maint_on && cur=1;;   dock)    dock_on && cur=1;;
            kvm)     kvm_on && cur=1;;     ollama)  ollama_on && cur=1;;
            obs)     obs_on && cur=1;;     block)   block_on && cur=1;;
            notes)   notes_on && cur=1;;   focus)   focus_on && cur=1;;
            launcher)launcher_on && cur=1;; firefox) firefox_on && cur=1;;
            neovim)  neovim_on && cur=1;;   spotify) spotify_on && cur=1;;
            emacs)   emacs_on && cur=1;;
        esac
        [ "$want" -eq "$cur" ] && continue
        toggle_"$tag"
    done
}

subpanel() {
    local group_name="$1"; shift
    local tags=("$@")
    while true; do
        local sel
        sel=$(build_group "$group_name" "${tags[@]}") || break
        clear
        echo -e "${MG}=== APPLYING SETTINGS — $group_name ===${R}"
        echo ""
        if apply_tags "$sel" "${tags[@]}"; then
            log_ok "Done"
        else
            log_e "Some settings failed"
        fi
        echo ""
        read -r -p "  Mo lai $group_name? (y/N): " again
        case "${again,,}" in y|yes) continue ;; *) break ;; esac
    done
}

# ==================================================================
# MAIN MENU
# ==================================================================
settings_main_menu() {
    while true; do
        local c
        c=$(tui_menu "SYSTEM SETTINGS" "Chon nhom:" 14 56 4 \
            1 "System    — Super Mode, Affinity, Eco, Undervolt..." \
            2 "Services  — Docker, KVM, Ollama, Maintenance" \
            3 "Apps      — Obsidian, Blocker, Notes, Focus" \
            4 "Back") || break
        [ -z "$c" ] && break
        case "$c" in
            1) subpanel "System" "${SYSTEM_TAGS[@]}" ;;
            2) subpanel "Services" "${SERVICES_TAGS[@]}" ;;
            3) subpanel "Apps" "${APPS_TAGS[@]}" ;;
            4) break ;;
        esac
    done
}

# ==================================================================
# ENTRY
# ==================================================================
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    settings_main_menu
fi
