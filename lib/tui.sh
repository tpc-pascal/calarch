#!/bin/bash
# ============================================================================
# TUI.SH — Widget library: dialog only
#   menu, checklist, msgbox, yesno, inputbox, gauge, infobox,
#   form (multi-field edit), tailbox (live log)
# ============================================================================

TUI_OK=0
BACKTITLE=""
command -v dialog &>/dev/null && TUI_OK=1

tui_detect()   { [ "$TUI_OK" -eq 1 ]; }
tui_backtitle() { BACKTITLE="$1"; }

tui_menu() {
  local title="$1" prompt="$2" h="$3" w="$4" mh="$5"; shift 5
  dialog --shadow --colors --backtitle "$BACKTITLE" \
    --title "$title" --menu "$prompt" "$h" "$w" "$mh" "$@" 2>&1 >/dev/tty
}

tui_checklist() {
  local title="$1" prompt="$2" h="$3" w="$4" lh="$5"; shift 5
  dialog --shadow --colors --backtitle "$BACKTITLE" \
    --title "$title" --checklist "$prompt" "$h" "$w" "$lh" "$@" 2>&1 >/dev/tty
}

tui_msg() {
  local title="$1" msg="$2" h="$3" w="$4"
  dialog --shadow --colors --backtitle "$BACKTITLE" \
    --title "$title" --msgbox "$msg" "$h" "$w"
}

tui_yn() {
  local title="$1" msg="$2" h="$3" w="$4"
  dialog --shadow --colors --backtitle "$BACKTITLE" \
    --title "$title" --yesno "$msg" "$h" "$w"
}

tui_input() {
  local title="$1" prompt="$2" h="$3" w="$4" default="$5"
  dialog --shadow --colors --backtitle "$BACKTITLE" \
    --title "$title" --inputbox "$prompt" "$h" "$w" "$default" 2>&1 >/dev/tty
}

tui_gauge() {
  local title="$1" msg="$2" h="$3" w="$4"
  dialog --shadow --colors --backtitle "$BACKTITLE" \
    --title "$title" --gauge "$msg" "$h" "$w" 0
}

tui_info() {
  local title="$1" msg="$2" h="$3" w="$4"
  dialog --shadow --colors --backtitle "$BACKTITLE" \
    --title "$title" --infobox "$msg" "$h" "$w"
}

tui_form() {
  local title="$1" text="$2" h="$3" w="$4" fh="$5"; shift 5
  dialog --shadow --colors --backtitle "$BACKTITLE" \
    --title "$title" --form "$text" "$h" "$w" "$fh" "$@" 2>&1 >/dev/tty
}

tui_tailbox() {
  local title="$1" file="$2" h="$3" w="$4"
  dialog --shadow --colors --backtitle "$BACKTITLE" \
    --title "$title" --tailbox "$file" "$h" "$w"
}

tui_radiolist() {
  local title="$1" prompt="$2" h="$3" w="$4" lh="$5"; shift 5
  dialog --shadow --colors --backtitle "$BACKTITLE" \
    --title "$title" --radiolist "$prompt" "$h" "$w" "$lh" "$@" 2>&1 >/dev/tty
}
