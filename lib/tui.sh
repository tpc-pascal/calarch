#!/bin/bash
# ============================================================================
# TUI.SH — Widget library: gum (charmbracelet/gum)
#   menu, checklist, msgbox, yesno, inputbox, form, tailbox
# ============================================================================

TUI_OK=0
command -v gum &>/dev/null && TUI_OK=1

_BDR="212"  _ACC="99"  _OK="76"  _ER="196"  _WA="214"  _IN="33"

tui_detect()   { [ "$TUI_OK" -eq 1 ]; }

tui_menu() {
  local title="$1" prompt="$2"; shift 5
  local -a tags items
  while [ $# -gt 0 ]; do
    tags+=("$1"); items+=("$2"); shift 2
  done
  local sel
  sel=$(gum choose --height 12 --header "$title" "${items[@]}" 2>/dev/null) || return 1
  for i in "${!items[@]}"; do
    [ "${items[$i]}" = "$sel" ] && echo "${tags[$i]}" && return 0
  done
  echo "$sel"
}

tui_checklist() {
  local title="$1" prompt="$2"; shift 5
  local -a tags items
  while [ $# -gt 0 ]; do
    tags+=("$1"); items+=("$2"); shift 3
  done
  printf '%s\n' "${items[@]}" \
    | gum choose --no-limit --height 12 --header "$title" 2>/dev/null \
    | while read -r sel; do
        for i in "${!items[@]}"; do
          [ "${items[$i]}" = "$sel" ] && echo "${tags[$i]}" && break
        done
      done
}

tui_msg() {
  echo ""
  gum style --border rounded --padding "1 2" --width 70 --foreground "$_BDR" "$2"
  echo ""
  read -r -s -n1
}

tui_yn() {
  gum confirm --prompt.foreground "$_ACC" "$2" 2>/dev/null
}

tui_input() {
  local prompt="$2" default="$5"
  gum input --header "$1" --placeholder "$prompt" --value "$default" 2>/dev/null
}

tui_form() {
  local title="$1"; shift 5
  local -a labels results
  while [ $# -gt 0 ]; do
    labels+=("$1"); shift 5
  done
  for label in "${labels[@]}"; do
    local val
    val=$(gum input --header "$title — $label" --placeholder "$label" 2>/dev/null) || return 1
    results+=("$val")
  done
  printf '%s\n' "${results[@]}"
}

tui_tailbox() {
  gum pager --header "$1" < "$2"
}

tui_gauge()   { gum spin --title "$1: $2" -- sleep 999; }
tui_info()    { echo ""; gum style --padding "1 2" --foreground "$_IN" "$2"; }
tui_backtitle() { :; }
tui_radiolist() { tui_menu "$@"; }

tui_section() {
    local text="$1"
    gum style --border double --padding "0 1" --margin "1 0" --foreground 99 "$text" 2>/dev/null || echo "=== $text ==="
}
