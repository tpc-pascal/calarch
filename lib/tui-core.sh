#!/bin/bash

R='\e[0m'

declare -A P=(
  [border]="\e[36m"   [title]="\e[1;36m" [ok]="\e[32m"
  [warn]="\e[33m"     [crit]="\e[31m"     [muted]="\e[90m"
  [hl]="\e[1;37m"     [btitle]="\e[1;36m" [bborder]="\e[36m"
)

declare -A PAL_PRESETS
PAL_PRESETS[cyan]="border=36 title=1;36 ok=32 warn=33 crit=31 muted=90 hl=1;37 btitle=1;36 bborder=36"
PAL_PRESETS[matrix]="border=32 title=1;32 ok=92 warn=33 crit=31 muted=32 hl=1;37 btitle=1;32 bborder=32"
PAL_PRESETS[royal]="border=35 title=1;35 ok=94 warn=93 crit=31 muted=90 hl=1;37 btitle=1;35 bborder=35"
PAL_PRESETS[amber]="border=33 title=1;33 ok=93 warn=31 crit=31 muted=90 hl=1;37 btitle=1;33 bborder=33"
PAL_PRESETS[mono]="border=37 title=1;37 ok=37 warn=33 crit=31 muted=90 hl=1;37 btitle=1;37 bborder=37"

PAL_CURRENT="cyan"
LAYOUT_DIR="$HOME/.config/calarch"
LAYOUT_FILE="$LAYOUT_DIR/layout.conf"

load_palette() {
  local ps
  ps=$(grep -E '^palette=' "$LAYOUT_FILE" 2>/dev/null | cut -d= -f2 || echo "cyan")
  PAL_CURRENT="$ps"
  if [ "$ps" = "custom" ]; then
    for key in border title ok warn crit muted hl btitle bborder; do
      local val
      val=$(grep -E "^${key}=" "$LAYOUT_FILE" 2>/dev/null | cut -d= -f2 || true)
      [ -n "$val" ] && P[$key]="\e[${val}m"
    done
  else
    local preset="${PAL_PRESETS[$ps]:-${PAL_PRESETS[cyan]}}"
    for pair in $preset; do
      local k="${pair%=*}" v="${pair#*=}"
      P[$k]="\e[${v}m"
    done
  fi
}

save_palette() {
  mkdir -p "$LAYOUT_DIR" 2>/dev/null || true
  sed -i "/^palette=/d" "$LAYOUT_FILE" 2>/dev/null || true
  echo "palette=${PAL_CURRENT}" >> "$LAYOUT_FILE"
  if [ "$PAL_CURRENT" = "custom" ]; then
    for key in border title ok warn crit muted hl btitle bborder; do
      local code="${P[$key]}"
      code="${code#\\e[}"; code="${code%m}"
      echo "${key}=${code}" >> "$LAYOUT_FILE"
    done
  fi
}

load_palette_preset() {
  local name="$1"
  PAL_CURRENT="$name"
  local preset="${PAL_PRESETS[$name]}"
  if [ -n "$preset" ]; then
    for pair in $preset; do
      local k="${pair%=*}" v="${pair#*=}"
      P[$k]="\e[${v}m"
    done
  fi
}

palette_picker() {
  local c
  c=$(tui_menu "PALETTE" "Choose color preset:" 16 44 6 \
    "cyan"    "Default cyan/blue (current)" \
    "matrix"  "Green on black (Matrix)" \
    "royal"   "Purple and gold" \
    "amber"   "Orange old terminal" \
    "mono"    "White on black" \
    "custom"  "Custom — pick individual colors") || return
  if [ "$c" = "custom" ]; then
    custom_palette
  else
    load_palette_preset "$c"
    save_palette
    tui_msg "PALETTE" "Applied: ${b}${c}${R}" 6 30
  fi
}

log_i()  { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_w()  { echo -e "${YEL}[!!]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }
