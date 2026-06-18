#!/bin/bash
# ============================================================================
# SETTINGS.SH — Settings Panel (3 submenus: System, Services, Apps)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/tui.sh"

R='\033[0m'; B='\033[1m'; D='\033[0;90m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'; MG='\033[0;35m'
SUPER_SCRIPT="$SCRIPT_DIR/super-mode.sh"
EVENT_MON="$SCRIPT_DIR/hyprland-event-monitor.sh"
ROTATOR="$SCRIPT_DIR/cf-xz6-rotator.sh"
FOCUS_SH="$SCRIPT_DIR/focus.sh"
NOTES_SH="$SCRIPT_DIR/notes.sh"
HOSTS_BACKUP="/tmp/hosts.focus.backup"
FOCUS_FLAG="/tmp/focus.mode.flag"

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
uv_on()        { has intel-undervolt && sudo intel-undervolt read 2>/dev/null | grep -q '\-'; }
rotate_on()    { systemctl is-active iio-sensor-proxy &>/dev/null; }
touch_on()     { xinput list --name-only 2>/dev/null | grep -qi touchpad; }
maint_on()     { systemctl is-enabled godmode-clean.timer &>/dev/null 2>&1; }
dock_on()      { systemctl is-active docker &>/dev/null; }
kvm_on()       { systemctl is-active libvirtd &>/dev/null; }
ollama_on()    { systemctl is-active ollama &>/dev/null; }
obs_on()       { command -v obsidian &>/dev/null; }
block_on()     { [ -f "$HOSTS_BACKUP" ]; }
notes_on()     { command -v obsidian &>/dev/null; }
focus_on()     { [ -f "$FOCUS_FLAG" ]; }

# ==================================================================
# TOGGLE FUNCTIONS
# ==================================================================
toggle_super() {
    if super_on; then pkill -f "super-mode.sh" 2>/dev/null; log_ok "Super Mode OFF"
    else nohup bash "$SUPER_SCRIPT" >/dev/null 2>&1 & log_ok "Super Mode ON"; fi
}
toggle_affinity() {
    if affinity_on; then pkill -f "hyprland-event-monitor.sh" 2>/dev/null; log_ok "Affinity OFF"
    else nohup bash "$EVENT_MON" >/dev/null 2>&1 & log_ok "Affinity ON"; fi
}
toggle_eco() {
    local p="/sys/devices/platform/panasonic/eco_mode"
    if [ ! -f "$p" ]; then log_w "Eco mode N/A"; return; fi
    if eco_on; then echo 0 | sudo tee "$p" >/dev/null; log_ok "Eco OFF (100%)"
    else echo 1 | sudo tee "$p" >/dev/null; log_ok "Eco ON (80%)"; fi
}
toggle_uv() {
    if uv_on; then log_w "Undervolt: reset can reboot"
    elif has intel-undervolt; then sudo intel-undervolt apply 2>/dev/null && log_ok "Undervolt ON" || log_w "Undervolt fail"; fi
}
toggle_rotate() {
    if rotate_on; then
        sudo systemctl disable --now iio-sensor-proxy 2>/dev/null; pkill -f "cf-xz6-rotator.sh" 2>/dev/null; log_ok "Rotate OFF"
    else
        sudo systemctl enable --now iio-sensor-proxy 2>/dev/null; nohup bash "$ROTATOR" >/dev/null 2>&1 & log_ok "Rotate ON"
    fi
}
toggle_touch() {
    local id
    id=$(xinput list | grep -i touchpad | grep -oP 'id=\K\d+' || echo "")
    [ -z "$id" ] && { log_w "No touchpad"; return; }
    if touch_on; then xinput set-prop "$id" "Device Enabled" 0 2>/dev/null; log_ok "Touchpad OFF"
    else xinput set-prop "$id" "Device Enabled" 1 2>/dev/null; xinput set-prop "$id" "libinput Tapping Enabled" 1 2>/dev/null; log_ok "Touchpad ON"; fi
}
toggle_maint() {
    if maint_on; then sudo systemctl disable --now godmode-clean.timer 2>/dev/null; log_ok "Timer OFF"
    else sudo systemctl enable --now godmode-clean.timer 2>/dev/null; log_ok "Timer ON"; fi
}
toggle_dock() {
    if dock_on; then sudo systemctl disable --now docker docker.socket 2>/dev/null; log_ok "Docker OFF"
    else sudo systemctl enable --now docker docker.socket 2>/dev/null; log_ok "Docker ON"; fi
}
toggle_kvm() {
    if kvm_on; then sudo systemctl disable --now libvirtd 2>/dev/null; log_ok "KVM OFF"
    else sudo systemctl enable --now libvirtd 2>/dev/null; log_ok "KVM ON"; fi
}
toggle_ollama() {
    if ollama_on; then sudo systemctl disable --now ollama 2>/dev/null; log_ok "Ollama OFF"
    else sudo systemctl enable --now ollama 2>/dev/null; log_ok "Ollama ON"; fi
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
        sudo cp "$HOSTS_BACKUP" /etc/hosts 2>/dev/null; rm -f "$HOSTS_BACKUP"; log_ok "Blocker OFF"
    else
        sudo cp /etc/hosts "$HOSTS_BACKUP" 2>/dev/null
        for s in facebook.com www.facebook.com twitter.com www.twitter.com x.com www.x.com instagram.com www.instagram.com reddit.com www.reddit.com tiktok.com www.tiktok.com youtube.com www.youtube.com; do
            echo "127.0.0.1 $s" | sudo tee -a /etc/hosts >/dev/null
            echo "::1 $s" | sudo tee -a /etc/hosts >/dev/null
        done
        log_ok "Blocker ON"
    fi
}
toggle_notes() {
    if [ -f "$NOTES_SH" ]; then bash "$NOTES_SH"
    else log_e "Missing $NOTES_SH"; fi
}
toggle_focus() {
    if focus_on; then
        rm -f "$FOCUS_FLAG"
        if [ -f "$HOSTS_BACKUP" ]; then
            sudo cp "$HOSTS_BACKUP" /etc/hosts 2>/dev/null; rm -f "$HOSTS_BACKUP"
        fi
        log_ok "Focus OFF"
    else
        touch "$FOCUS_FLAG"
        if [ -f "$FOCUS_SH" ]; then bash "$FOCUS_SH"
        else rm -f "$FOCUS_FLAG"; log_e "Missing $FOCUS_SH"; fi
    fi
}

# ==================================================================
# GENERIC: build checklist + apply for a group of tags
# ==================================================================
# tag list per group
SYSTEM_TAGS=(super affinity eco uv rotate touch)
SERVICES_TAGS=(dock kvm ollama maint)
APPS_TAGS=(obs block notes focus)

build_group() {
    local group_name="$1"; shift
    local tags=("$@")
    local items=() state desc

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
        esac
        items+=("$item" "$desc  [$state]" "$state")
    done

    local sel
    sel=$(tui_checklist "SETTINGS — $group_name" \
        "SPACE=toggle | ENTER=apply | ESC=back" \
        18 68 "${#tags[@]}" "${items[@]}") || return 1
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
        apply_tags "$sel" "${tags[@]}"
        [ $? -eq 0 ] && log_ok "Done" || log_e "Some settings failed"
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
