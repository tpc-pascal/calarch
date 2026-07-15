#!/bin/bash
# ============================================================================
# TUI.SH — TUI abstraction layer
#   dialog (preferred) → whiptail (fallback)
# ============================================================================

# Auto-detect
TUI=""
TUI_OK=0
BACKTITLE=""
if command -v dialog &>/dev/null; then
    TUI="dialog"
    TUI_OK=1
elif command -v whiptail &>/dev/null; then
    TUI="whiptail"
    TUI_OK=1
fi

tui_detect()  { [ "$TUI_OK" -eq 1 ]; }
# Unused but kept for API completeness
tui_is_dialog() { [ "$TUI" = "dialog" ]; }

tui_backtitle() { BACKTITLE="$1"; }

# --- Menu: returns selected tag, exit code 1 if Cancel ---
tui_menu() {
    local title="$1" prompt="$2" h="$3" w="$4" mh="$5"; shift 5
    local output rc
    case "$TUI" in
        dialog) output=$(dialog --shadow --colors --backtitle "$BACKTITLE" \
                --title "$title" --menu "$prompt" "$h" "$w" "$mh" "$@" 2>&1 >/dev/tty) ;;
        whiptail) output=$(whiptail --title "$title" --menu "$prompt" "$h" "$w" "$mh" "$@" 3>&1 1>&2 2>&3) ;;
    esac
    rc=$?
    echo "$output"
    return $rc
}

# --- Checklist: returns space-separated tags, exit code 1 if Cancel ---
tui_checklist() {
    local title="$1" prompt="$2" h="$3" w="$4" lh="$5"; shift 5
    local output rc
    case "$TUI" in
        dialog) output=$(dialog --shadow --colors --backtitle "$BACKTITLE" \
                --title "$title" --checklist "$prompt" "$h" "$w" "$lh" "$@" 2>&1 >/dev/tty) ;;
        whiptail) output=$(whiptail --title "$title" --checklist "$prompt" "$h" "$w" "$lh" "$@" 3>&1 1>&2 2>&3) ;;
    esac
    rc=$?
    echo "$output"
    return $rc
}

# --- Message box (unused but kept for API completeness) ---
tui_msg() {
    local title="$1" msg="$2" h="$3" w="$4"
    case "$TUI" in
        dialog) dialog --shadow --colors --backtitle "$BACKTITLE" \
                --title "$title" --msgbox "$msg" "$h" "$w" 2>&1 >/dev/tty ;;
        whiptail) whiptail --title "$title" --msgbox "$msg" "$h" "$w" 3>&1 1>&2 2>&3 ;;
    esac
}

# --- Yes/No: return 0 for Yes, 1 for No/Cancel (unused but kept for API completeness) ---
tui_yn() {
    local title="$1" msg="$2" h="$3" w="$4"
    case "$TUI" in
        dialog) dialog --shadow --colors --backtitle "$BACKTITLE" \
                --title "$title" --yesno "$msg" "$h" "$w" 2>&1 >/dev/tty ;;
        whiptail) whiptail --title "$title" --yesno "$msg" "$h" "$w" 3>&1 1>&2 2>&3 ;;
    esac
    return $?
}

# --- Gauge (progress bar): reads percentage from stdin (unused but kept for API completeness) ---
# Usage: echo "50" | tui_gauge "Title" "Message" h w
#        (echo "10"; sleep 1; echo "50") | tui_gauge ...
tui_gauge() {
    local title="$1" msg="$2" h="$3" w="$4"
    case "$TUI" in
        dialog) dialog --shadow --colors --backtitle "$BACKTITLE" \
                --title "$title" --gauge "$msg" "$h" "$w" 0 2>&1 >/dev/tty ;;
        whiptail) whiptail --title "$title" --gauge "$msg" "$h" "$w" 0 2>&1 >/dev/tty ;;
    esac
}

# --- Input box: returns text, exit code 1 if Cancel ---
tui_input() {
    local title="$1" prompt="$2" h="$3" w="$4" default="$5"
    local output rc
    case "$TUI" in
        dialog) output=$(dialog --shadow --colors --backtitle "$BACKTITLE" \
                --title "$title" --inputbox "$prompt" "$h" "$w" "$default" 2>&1 >/dev/tty) ;;
        whiptail) output=$(whiptail --title "$title" --inputbox "$prompt" "$h" "$w" "$default" 3>&1 1>&2 2>&3) ;;
    esac
    rc=$?
    echo "$output"
    return $rc
}

# --- Infobox (non-blocking message, unused but kept for API completeness) ---
tui_info() {
    local title="$1" msg="$2" h="$3" w="$4"
    case "$TUI" in
        dialog) dialog --shadow --colors --backtitle "$BACKTITLE" \
                --title "$title" --infobox "$msg" "$h" "$w" 2>&1 >/dev/tty ;;
        whiptail) whiptail --title "$title" --infobox "$msg" "$h" "$w" 2>&1 >/dev/tty ;;
    esac
}
