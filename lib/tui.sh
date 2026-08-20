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
  local title="$1" prompt="$2"; shift 2
  local sel_default=""
  # Bo qua geometry (so) truoc, vi so luong tham so geometry khong dong nhat
  while [ $# -gt 0 ] && [[ "$1" =~ ^[0-9]+$ ]]; do shift; done
  # Optional: "--selected" de pre-check state hien tai
  if [ "${1:-}" = "--selected" ]; then shift; sel_default="${1:-}"; shift; fi
  local -a tags items
  while [ $# -gt 0 ]; do
    tags+=("$1"); items+=("$2"); shift 3
  done
  local -a extra=()
  [ -n "$sel_default" ] && extra=(--selected "$sel_default")
  # Bat loi ESC/cancel (truoc day pipe nuot exit code cua gum -> apply ngam tai tat ca)
  local out
  out=$(printf '%s\n' "${items[@]}" \
    | gum choose --no-limit --height 12 --header "$title" "${extra[@]}" 2>/dev/null) || return 1
  [ -z "$out" ] && return 1
  local line sel
  while IFS= read -r line; do
    sel="$line"
    for i in "${!items[@]}"; do
      [ "${items[$i]}" = "$sel" ] && echo "${tags[$i]}" && break
    done
  done <<< "$out"
}

tui_msg() {
  echo ""
  local text
  text=$(printf '%b' "$2")
  gum style --border rounded --padding "1 2" --width 70 --foreground "$_BDR" "$text"
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
  local -a labels defaults results
  while [ $# -gt 0 ]; do
    labels+=("$1")
    defaults+=("$4")
    shift 8
  done
  local i=0
  for label in "${labels[@]}"; do
    local val
    val=$(gum input --header "$title — $label" --placeholder "$label" --value "${defaults[$i]}" 2>/dev/null) || return 1
    results+=("$val")
    i=$((i + 1))
  done
  printf '%s\n' "${results[@]}"
}

tui_tailbox() {
  gum pager --header "$1" < "$2"
}

tui_gauge()   { gum spin --title "$1: $2" -- sleep 999; }
tui_info()    { echo ""; local text; text=$(printf '%b' "$2"); gum style --padding "1 2" --foreground "$_IN" "$text"; }
tui_backtitle() { :; }
tui_radiolist() { tui_menu "$@"; }

tui_section() {
    local text="$1"
    gum style --border double --padding "0 1" --margin "1 0" --foreground 99 "$text" 2>/dev/null || echo "=== $text ==="
}
