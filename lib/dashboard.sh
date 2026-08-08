#!/bin/bash
# ============================================================================
# DASHBOARD.SH — Single-screen TUI Control Center
# ANSI boxes, mouse drag-and-drop, keyboard nav, gum popups
# ============================================================================
set -euo pipefail

# ============================================================================
# PATHS
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE="$SCRIPT_DIR/core.sh"
CONFIG_FILE="$SCRIPT_DIR/../calarch.conf"
LAYOUT_DIR="$HOME/.config/calarch"
LAYOUT_FILE="$LAYOUT_DIR/layout.conf"

# State paths — phai dung chung logic voi core.sh (per-user ~/.local/state)
STATE_BASE="${XDG_STATE_HOME:-$HOME/.local/state}/calarch"
BOOT_COUNT_FILE="$STATE_BASE/boot-count"
HISTORY_LOG="$STATE_BASE/history/history.log"

source "$SCRIPT_DIR/tui.sh"
source "$SCRIPT_DIR/config-load.sh"
calarch_load_config "$CONFIG_FILE"

# ============================================================================
# ANSI RESET
# ============================================================================
R='\e[0m'; B='\e[1m'

# ============================================================================
# PALETTE — ANSI color codes
# ============================================================================
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
  # Xoa moi dong cu cua tung key truoc khi append — tranh chong mau khi lu nhieu lan
  sed -i -e "/^palette=/d" \
         -e "/^border=/d" -e "/^title=/d" -e "/^ok=/d" -e "/^warn=/d" \
         -e "/^crit=/d" -e "/^muted=/d" -e "/^hl=/d" -e "/^btitle=/d" \
         -e "/^bborder=/d" "$LAYOUT_FILE" 2>/dev/null || true
  echo "palette=${PAL_CURRENT}" >> "$LAYOUT_FILE"
  if [ "${PAL_CURRENT}" = "custom" ]; then
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
    redraw_all
  fi
}

custom_palette() {
  local fields=(
    "Border"   1 1 "36"  1 15 5 0
    "Title"    2 1 "1;36" 2 15 5 0
    "OK"       3 1 "32"  3 15 5 0
    "Warn"     4 1 "33"  4 15 5 0
    "Crit"     5 1 "31"  5 15 5 0
    "Muted"    6 1 "90"  6 15 5 0
    "H.Light"  7 1 "1;37" 7 15 5 0
    "B.Title"  8 1 "1;36" 8 15 5 0
    "B.Border" 9 1 "36"  9 15 5 0
  )
  local result
  result=$(tui_form "CUSTOM PALETTE" \
    "Enter ANSI color codes (e.g. 32, 1;33, 90):" 14 40 9 "${fields[@]}") || return
  local i=0 keys=(border title ok warn crit muted hl btitle bborder)
  while IFS= read -r val; do
    [ -n "$val" ] && P[${keys[$i]}]="\e[${val}m"
    i=$((i + 1))
  done <<< "$result"
  PAL_CURRENT="custom"
  save_palette
  redraw_all
}

# ============================================================================
# BOX DEFINITIONS
# ============================================================================
BOX_IDS=(system services focus profiles tools ultrafocus status)
BOX_NAMES=("SYSTEM" "SERVICES" "FOCUS" "PROFILES" "TOOLS" "ULTRAFOCUS" "STATUS")

DEFAULT_LAYOUT=(
  "system=2,3,40,7,1"
  "services=44,3,40,7,1"
  "focus=2,11,40,6,1"
  "profiles=44,11,40,6,1"
  "tools=2,18,26,6,1"
  "ultrafocus=29,18,26,6,1"
  "status=56,18,26,6,1"
)

declare -A B  # box positions: "x,y,w,h,visible"

load_layout() {
  mkdir -p "$LAYOUT_DIR" 2>/dev/null || true
  if [ ! -f "$LAYOUT_FILE" ]; then
    default_layout
    return
  fi
  for entry in "${DEFAULT_LAYOUT[@]}"; do
    local id="${entry%=*}" default="${entry#*=}"
    local saved
    saved=$(grep -E "^${id}=" "$LAYOUT_FILE" 2>/dev/null | cut -d= -f2 || echo "$default")
    B[$id]="$saved"
  done
}

save_layout() {
  mkdir -p "$LAYOUT_DIR" 2>/dev/null || true
  for id in "${BOX_IDS[@]}"; do
    [ -n "${B[$id]:-}" ] && sed -i "/^${id}=/d" "$LAYOUT_FILE" 2>/dev/null || true
    echo "${id}=${B[$id]}" >> "$LAYOUT_FILE"
  done
}

default_layout() {
  for entry in "${DEFAULT_LAYOUT[@]}"; do
    local id="${entry%=*}" val="${entry#*=}"
    B[$id]="$val"
  done
}

# ============================================================================
# STATE
# ============================================================================
DRAG_ID="" DRAG_OX=0 DRAG_OY=0
EVENT="" EVENT_TYPE=""

# ============================================================================
# SYSTEM HELPERS
# ============================================================================
cpu_temp() {
  local t=0
  local z
  for z in /sys/class/thermal/thermal_zone*; do
    local ztype
    ztype=$(cat "$z/type" 2>/dev/null)
    case "$ztype" in x86_pkg_temp|coretemp|acpitz) t=$(cat "$z/temp" 2>/dev/null); t=$((t/1000)); break;; esac
  done
  echo "$t"
}
cpu_freq() {
  local f=0
  [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ] && f=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq) && f=$((f/1000))
  echo "$f"
}
cpu_load() {
  awk '/cpu /{printf "%d",($2+$4)*100/($2+$4+$5)}' /proc/stat 2>/dev/null || echo "0"
}
mem_used() {
  free -m 2>/dev/null | awk '/Mem:/{printf "%d", $3}' || echo "0"
}
mem_total() {
  free -m 2>/dev/null | awk '/Mem:/{printf "%d", $2}' || echo "0"
}
eco_mode() {
  local v
  v=$(cat /sys/devices/platform/panasonic/eco_mode 2>/dev/null || echo "0")
  echo "$v"
}
eco_text() {
  local v limit
  v=$(eco_mode)
  limit=$(grep -E '^ECO_CHARGE_LIMIT=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2 || echo "80")
  if [ "$v" = "1" ]; then echo -e "${P[ok]}ON${R} ${limit}%"
  else echo -e "${P[muted]}OFF${R} 100%"; fi
}
super_text() {
  if pgrep -f "super-mode.sh" &>/dev/null; then echo -e "${P[ok]}ACTIVE${R}"
  else echo -e "${P[muted]}OFF${R}"; fi
}
affinity_text() {
  if pgrep -f "hyprland-event-monitor.sh" &>/dev/null; then echo -e "${P[ok]}ACTIVE${R}"
  else echo -e "${P[muted]}OFF${R}"; fi
}
gov_text() {
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "?"
}
grace_text() {
  local g
  g=$("$CORE" grace_status 2>/dev/null) || true
  echo "$g"
}
boot_text() {
  local c=0
  [ -f "$BOOT_COUNT_FILE" ] && c=$(cat "$BOOT_COUNT_FILE" 2>/dev/null || echo 0)
  [[ "$c" =~ ^[0-9]+$ ]] || c=0
  if [ "$c" -le 2 ]; then echo -e "${P[ok]}OK${R} ($c boot)"
  else echo -e "${P[crit]}ISSUE${R} ($c boots)"; fi
}
swap_used() {
  free -m 2>/dev/null | awk '/Swap:/{printf "%d", $3}' || echo "0"
}
swap_total() {
  free -m 2>/dev/null | awk '/Swap:/{printf "%d", $2}' || echo "0"
}

# ============================================================================
# CONTENT RENDERERS
# ============================================================================
render_box_content() {
  local id="$1" line="$2" x="$3" w="$4"
  local inner=$((w-2))
  local pad=""
  local i
  pad=$(printf '%*s' "$inner" '')

  case "$id" in
    system)
      case "$line" in
        0)
          local load=$(cpu_load) temp=$(cpu_temp) freq=$(cpu_freq) gov=$(gov_text)
          local lcol="${P[ok]}"; [ "$load" -gt 70 ] && lcol="${P[crit]}"
          local tcol="${P[ok]}"; [ "$temp" -gt 80 ] && tcol="${P[crit]}"
          printf "${lcol}CPU %3d%%${R}  ${tcol}%2d°C${R}  %sMHz  ${P[muted]}%s${R}" "$load" "$temp" "$freq" "$gov"
          ;;
        1)
          printf "Eco: %b  Super: %b  Aff: %b" "$(eco_text)" "$(super_text)" "$(affinity_text)"
          ;;
        2)
          local uv_cpu="${UNDERVOLT_CPU:-0}" uv_gpu="${UNDERVOLT_GPU:-0}" uv_cache="${UNDERVOLT_CACHE:-0}" mc="${MAX_CSTATE:-4}"
          printf "UV: %s/%s/%smV  CState:%s" "$uv_cpu" "$uv_gpu" "$uv_cache" "$mc"
          ;;
        3)
          printf "${P[muted]}%s${R}" "──────────────────────────────────────"
          ;;
        4)
          printf "${P[ok]}Enter${R}=${P[muted]}edit  ${P[ok]}Drag${R}=${P[muted]}title bar${R}"
          ;;
        *)
          printf "%s" "$pad"
          ;;
      esac
      ;;
    services)
      case "$line" in
        0)
          local dk=$(systemctl is-active docker &>/dev/null && echo "${P[ok]}ON${R}" || echo "${P[muted]}OFF${R}")
          local kv=$(systemctl is-active libvirtd &>/dev/null && echo "${P[ok]}ON${R}" || echo "${P[muted]}OFF${R}")
          local ol=$(systemctl is-active ollama &>/dev/null && echo "${P[ok]}ON${R}" || echo "${P[muted]}OFF${R}")
          printf "Docker:%b  KVM:%b  Ollama:%b" "$dk" "$kv" "$ol"
          ;;
        1)
          local mt=$(systemctl is-enabled godmode-clean.timer &>/dev/null 2>&1 && echo "${P[ok]}ON${R}" || echo "${P[muted]}OFF${R}")
          local rt=$(systemctl is-active iio-sensor-proxy &>/dev/null && echo "${P[ok]}ON${R}" || echo "${P[muted]}OFF${R}")
          local tp=$(xinput list --name-only 2>/dev/null | grep -qi touchpad && echo "${P[ok]}ON${R}" || echo "${P[muted]}OFF${R}")
          printf "Maint:%b  Rotate:%b  Touch:%b" "$mt" "$rt" "$tp"
          ;;
        2)
          printf "${P[muted]}%s${R}" "──────────────────────────────────────"
          ;;
        3)
          printf "${P[ok]}Enter${R}=${P[muted]}toggle${R}"
          ;;
        *)
          printf "%s" "$pad"
          ;;
      esac
      ;;
    focus)
      case "$line" in
        0)
          printf "Pomodoro ${P[hl]}%s${R}/${P[hl]}%s${R}/${P[hl]}%s${R}" \
            "${POMODORO_WORK_MINUTES:-25}" "${POMODORO_BREAK_MINUTES:-5}" "${POMODORO_CYCLES:-4}"
          ;;
        1)
          local bl="OFF"
          grep -qF "# --- calarch-blocker: begin ---" /etc/hosts 2>/dev/null && bl="ON"
          local fo=$( [ -f /tmp/focus.mode.flag ] && echo "${P[ok]}ON${R}" || echo "${P[muted]}OFF${R}" )
          printf "Blocker:%b  Focus:%b" "$bl" "$fo"
          ;;
        2)
          printf "${P[muted]}%s${R}" "──────────────────────────────────────"
          ;;
        3)
          printf "${P[ok]}Enter${R}=${P[muted]}open${R}"
          ;;
        *)
          printf "%s" "$pad"
          ;;
      esac
      ;;
    profiles)
      case "$line" in
        0)
          local current_profile=""
          local profiles=()
          mkdir -p "$SCRIPT_DIR/../profiles" 2>/dev/null || true
          for f in "$SCRIPT_DIR/../profiles"/*.conf; do
            [ -f "$f" ] || continue
            local name=$(basename "$f" .conf)
            profiles+=("$name")
          done
          if [ ${#profiles[@]} -gt 0 ]; then
            local first="${profiles[0]}"
            printf "${P[hl]}%s${P[muted]}%s${R}" "$first" "  ${profiles[*]:1}"
          else
            printf "${P[muted]}(no profiles)${R}"
          fi
          ;;
        1)
          printf "${P[muted]}%s${R}" "──────────────────────────────────────"
          ;;
        2)
          printf "${P[ok]}Enter${R}=${P[muted]}manage${R}"
          ;;
        *)
          printf "%s" "$pad"
          ;;
      esac
      ;;
    tools)
      case "$line" in
        0)
          printf "${P[muted]}Notes${R}  ${P[muted]}Games${R}  ${P[muted]}Mount${R}  ${P[muted]}Wall${R}"
          ;;
        1)
          printf "${P[muted]}Web${R}:${P[hl]}8765${R}  ${P[muted]}AutoInstall${R}  ${P[muted]}GodMode${R}"
          ;;
        2)
          printf "${P[muted]}Stylus${R}"
          ;;
        3)
          printf "${P[muted]}%s${R}" "──────────────────────"
          ;;
        4)
          printf "${P[ok]}Enter${R}=${P[muted]}open${R}"
          ;;
        *)
          printf "%s" "$pad"
          ;;
      esac
      ;;
    ultrafocus)
      case "$line" in
        0)
          local ed="?"; command -v nvim &>/dev/null && ed="${P[ok]}nvim${R}" || ed="${P[muted]}✗${R}"
          local lc="?"; command -v rofi &>/dev/null && lc="${P[ok]}rofi${R}" || lc="${P[muted]}✗${R}"
          printf "Editor: %b  Launcher: %b" "$ed" "$lc"
          ;;
        1)
          local ff="${P[muted]}✗${R}"
          for f in "$HOME/.mozilla/firefox"/*/chrome/userChrome.css; do
            [ -f "$f" ] && ff="${P[ok]}vtabs${R}" && break
          done
          local sp="?"; command -v spicetify &>/dev/null && sp="${P[ok]}spicetfy${R}" || sp="${P[muted]}✗${R}"
          printf "Firefox: %b  Spotify: %b" "$ff" "$sp"
          ;;
        2)
          local yt="?"; command -v yt-dlp &>/dev/null && yt="${P[ok]}yt${R}" || yt="${P[muted]}✗${R}"
          local em="?"; command -v emacs &>/dev/null && em="${P[ok]}emacs${R}" || em="${P[muted]}✗${R}"
          printf "Media: %b  Notes: %b" "$yt" "$em"
          ;;
        3)
          printf "${P[muted]}%s${R}" "──────────────────────"
          ;;
        4)
          printf "${P[ok]}Enter${R}=${P[muted]}manage${R}"
          ;;
        *)
          printf "%s" "$pad"
          ;;
      esac
      ;;
    status)
      case "$line" in
        0)
          local load=$(cpu_load) temp=$(cpu_temp) freq=$(cpu_freq)
          local lcol="${P[ok]}"; [ "$load" -gt 70 ] && lcol="${P[crit]}"
          local tcol="${P[ok]}"; [ "$temp" -gt 80 ] && tcol="${P[crit]}"
          local bar_s=$((load*15/100)) bar_e=$((15-bar_s))
          local bar="${lcol}"
          for ((i=0; i<bar_s; i++)); do bar+="█"; done
          bar+="${P[muted]}"
          for ((i=0; i<bar_e; i++)); do bar+="░"; done
          bar+="${R}"
          printf "CPU ${bar} ${lcol}%3d%%${R}  ${tcol}%2d°C${R}" "$load" "$temp"
          ;;
        1)
          local mu=$(mem_used) mt=$(mem_total)
          local mp=$((mt>0 ? mu*100/mt : 0))
          local mcol="${P[ok]}"; [ "$mp" -gt 80 ] && mcol="${P[crit]}"
          local b_s=$((mp*15/100)) b_e=$((15-b_s))
          local bar="${mcol}"
          for ((i=0; i<b_s; i++)); do bar+="█"; done
          bar+="${P[muted]}"
          for ((i=0; i<b_e; i++)); do bar+="░"; done
          bar+="${R}"
          printf "MEM ${bar} ${mcol}%3d%%${R}  ${mu}/${mt}MB" "$mp"
          ;;
        2)
          local su=$(swap_used) st=$(swap_total)
          printf "Swap: ${su}/${st}MB"
          ;;
        3)
          printf "${P[muted]}Eco:${R} %b  ${P[muted]}Super:${R} %b" "$(eco_text)" "$(super_text)"
          ;;
        4)
          printf "${P[ok]}Enter${R}=${P[muted]}live view  ${P[ok]}R${R}=${P[muted]}refresh${R}"
          ;;
        *)
          printf "%s" "$pad"
          ;;
      esac
      ;;
  esac
}

# ============================================================================
# ANSI BOX ENGINE
# ============================================================================
box_h() {
  local id="$1"
  local pos="${B[$id]:-}"
  [ -z "$pos" ] && echo 0 && return
  IFS=',' read -r _ _ h _ <<< "$pos"
  echo "$h"
}

box_visible() {
  local id="$1"
  local pos="${B[$id]:-}"
  [ -z "$pos" ] && return 1
  IFS=',' read -r _ _ _ _ vis <<< "$pos"
  [ "$vis" -eq 1 ]
}

draw_header() {
  local cols="$1"
  tput cup 0 0
  local title="${P[title]}CALARCH CONTROL CENTER${R}"
  local tab=""
  local i=1
  for id in "${BOX_IDS[@]}"; do
    local vis=0
    IFS=',' read -r _ _ _ _ vis <<< "${B[$id]:-}"
    local num="${P[muted]}[${i}]${R}"
    local name="${BOX_NAMES[$((i-1))]}"
    if [ "$vis" -eq 1 ]; then
      tab+=" ${P[hl]}${num}${P[ok]}${name}${R}"
    else
      tab+=" ${P[muted]}${num}${P[muted]}${name}${R}"
    fi
    i=$((i + 1))
  done
  tab+="  ${P[muted]}[${R}${P[hl]}P${R}${P[muted]}]${R}Palette"
  tab+=" ${P[muted]}[${R}${P[hl]}.${R}${P[muted]}]${R}Menu"
  tab+=" ${P[muted]}[${R}${P[hl]}Q${R}${P[muted]}]${R}Quit"
  local line="${title}  ${tab}"
  local max=$((cols-1))
  echo -ne "${line:0:max}${R}"
}

draw_footer() {
  local cols="$1"
  tput cup $(( ${LINES:-24} - 1 )) 0
  local grace
  grace=$(grace_text)
  local grace_disp=""
  [ -n "$grace" ] && grace_disp="${P[warn]}Grace:${R} ${P[crit]}$grace${R}s  "
  local boot
  boot=$(boot_text)
  local hist_count=0
  [ -f "$HISTORY_LOG" ] && hist_count=$(wc -l < "$HISTORY_LOG" 2>/dev/null || echo 0)
  local line="${grace_disp}${P[muted]}History:${R} ${P[hl]}${hist_count}${R}  ${P[muted]}Boot:${R} ${boot}"
  local max=$((cols-1))
  echo -ne "${line:0:max}${R}"
}

draw_box() {
  local id="$1"
  local pos="${B[$id]:-}"
  [ -z "$pos" ] && return
  IFS=',' read -r x y w h vis <<< "$pos"
  [ "$vis" -eq 0 ] && return

  local idx=-1
  for i in "${!BOX_IDS[@]}"; do [ "${BOX_IDS[$i]}" = "$id" ] && idx=$i && break; done
  local title="${BOX_NAMES[$idx]:-$id}"

  tput sc

  # top border
  tput cup "$y" "$x"
  echo -ne "${P[bborder]}┌── ${P[btitle]}${title}${P[bborder]} ─"
  local rem=$((w-6-${#title}))
  for ((i=0; i<rem; i++)); do echo -ne "─"; done
  echo -ne "┐${R}"

  # content lines
  for ((i=0; i<h-2; i++)); do
    tput cup $((y+1+i)) "$x"
    echo -ne "${P[bborder]}│${R} "
    render_box_content "$id" "$i" "$x" "$w"
    tput cup $((y+1+i)) $((x+w-1))
    echo -e "${P[bborder]}│${R}"
  done

  # bottom border
  tput cup $((y+h-1)) "$x"
  echo -ne "${P[bborder]}└"
  for ((i=0; i<w-2; i++)); do echo -ne "─"; done
  echo -ne "┘${R}"

  tput rc
}

draw_all() {
  local cols=${COLUMNS:-80} lines=${LINES:-24}
  clear
  draw_header "$cols"
  for id in "${BOX_IDS[@]}"; do draw_box "$id"; done
  draw_footer "$cols"
}

redraw_all() { draw_all; }

# ============================================================================
# MOUSE HANDLING (SGR mode)
# ============================================================================
enable_mouse() {
  printf '\e[?1000h\e[?1002h\e[?1006h'
}

disable_mouse() {
  printf '\e[?1000l\e[?1002l\e[?1006l'
}

read_event() {
  EVENT=""; EVENT_TYPE=""
  local c
  # stdin dong (khong phai TTY) -> tra ve 1 de main_loop thoat, tranh busy-loop
  IFS= read -r -n1 c || return 1
  if [ "$c" != $'\e' ]; then
    EVENT="$c"; EVENT_TYPE=key
    return 0
  fi

  local seq="$c"
  IFS= read -r -n1 c; seq+="$c"
  [ "$c" != "[" ] && { EVENT="$seq"; EVENT_TYPE=key; return 0; }

  local rest=""
  while IFS= read -r -n1 -t 1 c 2>/dev/null; do
    rest+="$c"
    [[ "$c" =~ [MmABCD] ]] && break
  done
  seq+="$rest"

  EVENT="$seq"
  if [[ "$seq" =~ $'\e[''<'?[0-9]+';'[0-9]+';'[0-9]+[Mm] ]]; then
    EVENT_TYPE=mouse
  else
    EVENT_TYPE=key
  fi
}

parse_mouse() {
  local seq="$1"
  if [[ "$seq" =~ $'\e[''<'?([0-9]+)';'([0-9]+)';'([0-9]+)([Mm]) ]]; then
    local btn="${BASH_REMATCH[1]}" x="${BASH_REMATCH[2]}" y="${BASH_REMATCH[3]}" mt="${BASH_REMATCH[4]}"
    echo "$btn $x $y $mt"
  fi
}

box_at() {
  local mx="$1" my="$2"
  for id in "${BOX_IDS[@]}"; do
    local pos="${B[$id]:-}"
    [ -z "$pos" ] && continue
    IFS=',' read -r bx by bw bh bv <<< "$pos"
    [ "$bv" -eq 0 ] && continue
    if [ "$mx" -ge "$bx" ] && [ "$mx" -le "$((bx+bw-1))" ] && [ "$my" -ge "$by" ] && [ "$my" -le "$((by+bh-1))" ]; then
      echo "$id"; return
    fi
  done
}

is_title_bar() {
  local id="$1" mx="$2" my="$3"
  local pos="${B[$id]:-}"
  [ -z "$pos" ] && return 1
  IFS=',' read -r bx by bw bh bv <<< "$pos"
  [ "$my" -eq "$by" ] && [ "$mx" -ge "$bx" ] && [ "$mx" -le "$((bx+bw-1))" ]
}

handle_mouse() {
  local parsed
  parsed=$(parse_mouse "$EVENT")
  [ -z "$parsed" ] && return
  local btn mx my mt
  read -r btn mx my mt <<< "$parsed"

  if [ "$btn" -eq 0 ] && [ "$mt" = "M" ]; then
    DRAG_ID=""
    local target
    target=$(box_at "$mx" "$my")
    [ -z "$target" ] && return
    if is_title_bar "$target" "$mx" "$my"; then
      DRAG_ID="$target"
      local pos="${B[$target]}"
      IFS=',' read -r bx by _ _ _ <<< "$pos"
      DRAG_OX=$((mx - bx))
      DRAG_OY=$((my - by))
    else
      popup_box "$target"
    fi
  elif [ "$btn" -eq 32 ] && [ -n "$DRAG_ID" ] && [ "$mt" = "M" ]; then
    local new_x=$((mx - DRAG_OX))
    local new_y=$((my - DRAG_OY))
    [ "$new_x" -lt 1 ] && new_x=1
    [ "$new_y" -lt 1 ] && new_y=1
    local pos="${B[$DRAG_ID]}"
    IFS=',' read -r _ _ bw bh bv <<< "$pos"
    B[$DRAG_ID]="$new_x,$new_y,$bw,$bh,$bv"
    draw_all
  elif [ "$btn" -eq 0 ] && [ "$mt" = "m" ]; then
    if [ -n "$DRAG_ID" ]; then
      save_layout
      DRAG_ID=""
      draw_all
    fi
  fi
}

handle_key() {
  case "$EVENT" in
    [1-7])
      local idx=$((EVENT - 1))
      local id="${BOX_IDS[$idx]}"
      local pos="${B[$id]:-}"
      [ -z "$pos" ] && return
      IFS=',' read -r x y w h vis <<< "$pos"
      B[$id]="$x,$y,$w,$h,$((1-vis))"
      draw_all
      ;;
    [Rr]) draw_all ;;
    [Pp]) palette_picker ;;
    '.') dot_menu ;;
    [Qq])
      disable_mouse
      save_layout
      save_palette
      clear
      echo -e "${P[ok]}Goodbye!${R}"
      exit 0
      ;;
    $'\n') ;;
    $'\e') ;;
  esac
}

# ============================================================================
# DOT MENU
# ============================================================================
dot_menu() {
  local gstatus
  gstatus=$(grace_text)
  local gitem="Grace ($gstatus)"
  [ -z "$gstatus" ] && gitem="Grace (none)"
  local c
  c=$(tui_menu "QUICK ACTIONS" "Choose:" 12 40 4 \
    "grace"   "$gitem" \
    "history" "View change history" \
    "undo"    "Undo last change" \
    "help"    "Show keyboard shortcuts") || return
  case "$c" in
    grace)
      grace_confirm_all
      ;;
    history)
      local logfile="$HISTORY_LOG"
      if [ -f "$logfile" ]; then
        tui_tailbox "HISTORY" "$logfile" 20 70
      else
        tui_msg "HISTORY" "No history yet." 6 40
      fi
      redraw_all
      ;;
    undo)
      if tui_yn "UNDO" "Undo last change?" 7 40; then
        "$CORE" undo 2>/dev/null || true
        tui_msg "UNDO" "Done." 5 30
      fi
      redraw_all
      ;;
    help)
      tui_msg "HELP" \
        "Keyboard:\n\
         1-6   Toggle box show/hide\n\
         P     Change color palette\n\
         .     Quick actions menu\n\
         R     Refresh screen\n\
         Q     Quit\n\n\
        Mouse:\n\
         Click+drag title bar = move box\n\
         Click content = open settings" 18 50
      redraw_all
      ;;
  esac
}

grace_confirm_all() {
  local g
  g=$("$CORE" grace_status 2>/dev/null) || true
  [ -z "$g" ] && { tui_msg "GRACE" "No pending grace items." 6 40; redraw_all; return; }
  local items=()
  for entry in $g; do
    local key="${entry%:*}" remain="${entry#*:}"
    items+=("$key" "${remain}s remaining" "off")
  done
  local sel
  sel=$(tui_checklist "GRACE CONFIRM" \
    "Select items to confirm:" 14 50 "${#items[@]}" "${items[@]}") || { redraw_all; return; }
  for key in $sel; do
    "$CORE" grace_confirm "$key" 2>/dev/null || true
  done
  tui_msg "GRACE" "Confirmed: $sel" 6 40
  redraw_all
}

# ============================================================================
# POPUP DIALOGS
# ============================================================================
popup_box() {
  local id="$1"
  disable_mouse
  case "$id" in
    system)   popup_system ;;
    services) popup_services ;;
    focus)    popup_focus ;;
    profiles) popup_profiles ;;
    tools)    popup_tools ;;
    ultrafocus) popup_ultrafocus ;;
    status)   popup_status ;;
  esac
  redraw_all
  enable_mouse
}

popup_system() {
  while true; do
    local c
    c=$(tui_menu "SYSTEM SETTINGS" "Choose category:" 16 50 7 \
      "affinity" "CPU Affinity  — cores, policy, priority" \
      "super"    "Super Mode    — thresholds, governors" \
      "undervolt" "Undervolt     — CPU/GPU/Cache mV" \
      "eco"      "Eco / Charge  — battery charge limit" \
      "thermal"  "Thermal       — cstate, kernel params" \
      "display"  "Display       — scale, resolution, refresh" \
      "back"     "Back") || break
    case "$c" in
      affinity) edit_form_affinity ;;
      super)    edit_form_super ;;
      undervolt) edit_form_undervolt ;;
      eco)      edit_form_eco ;;
      thermal)  edit_form_thermal ;;
      display)  edit_form_display ;;
      back|*) break ;;
    esac
  done
}

edit_form_affinity() {
  local fields=(
    "Active cores" 1 1 "${AFFINITY_ACTIVE_CORES:-0,1}" 1 20 15 0
    "Background cores" 2 1 "${AFFINITY_BG_CORES:-2,3}" 2 20 15 0
    "Sched policy" 3 1 "${AFFINITY_ACTIVE_SCHED:-rr}" 3 20 15 0
    "Priority (1-99)" 4 1 "${AFFINITY_ACTIVE_PRIORITY:-50}" 4 20 15 0
    "IO nice active" 5 1 "${AFFINITY_ACTIVE_IONICE:-0}" 5 20 15 0
    "IO nice bg" 6 1 "${AFFINITY_BG_IONICE:-5}" 6 20 15 0
  )
  local result
  result=$(tui_form "CPU AFFINITY" \
    "Edit values (leave blank to keep current):" 12 52 6 "${fields[@]}") || return
  local keys=(AFFINITY_ACTIVE_CORES AFFINITY_BG_CORES AFFINITY_ACTIVE_SCHED AFFINITY_ACTIVE_PRIORITY AFFINITY_ACTIVE_IONICE AFFINITY_BG_IONICE)
  local i=0
  while IFS= read -r val; do
    [ -n "$val" ] && "$CORE" set "${keys[$i]}" "$val" 2>/dev/null || true
    i=$((i + 1))
  done <<< "$result"
}

edit_form_super() {
  local fields=(
    "Cool threshold %" 1 1 "${SUPER_COOL_THRESHOLD:-30}" 1 25 10 0
    "Hot threshold %" 2 1 "${SUPER_HOT_THRESHOLD:-70}" 2 25 10 0
    "Cool debounce (s)" 3 1 "${SUPER_COOL_DEBOUNCE:-10}" 3 25 10 0
    "Hot debounce (s)" 4 1 "${SUPER_HOT_DEBOUNCE:-5}" 4 25 10 0
    "Cool governor" 5 1 "${SUPER_COOL_GOVERNOR:-powersave}" 5 25 10 0
    "Hot governor" 6 1 "${SUPER_HOT_GOVERNOR:-schedutil}" 6 25 10 0
  )
  local result
  result=$(tui_form "SUPER MODE" \
    "Edit thresholds, debounce, governors:" 12 52 6 "${fields[@]}") || return
  local keys=(SUPER_COOL_THRESHOLD SUPER_HOT_THRESHOLD SUPER_COOL_DEBOUNCE SUPER_HOT_DEBOUNCE SUPER_COOL_GOVERNOR SUPER_HOT_GOVERNOR)
  local i=0
  while IFS= read -r val; do
    [ -n "$val" ] && "$CORE" set "${keys[$i]}" "$val" 2>/dev/null || true
    i=$((i + 1))
  done <<< "$result"
}

edit_form_undervolt() {
  local fields=(
    "CPU (mV)" 1 1 "${UNDERVOLT_CPU:--50}" 1 15 10 0
    "GPU (mV)" 2 1 "${UNDERVOLT_GPU:--20}" 2 15 10 0
    "Cache (mV)" 3 1 "${UNDERVOLT_CACHE:--50}" 3 15 10 0
  )
  local result
  result=$(tui_form "UNDERVOLT" \
    "Negative values = lower voltage (range -150 to 0)\nGrace period: 5 min to confirm" 10 48 3 "${fields[@]}") || return
  local keys=(UNDERVOLT_CPU UNDERVOLT_GPU UNDERVOLT_CACHE)
  local i=0
  while IFS= read -r val; do
    [ -n "$val" ] && "$CORE" set "${keys[$i]}" "$val" 2>/dev/null || true
    i=$((i + 1))
  done <<< "$result"
}

edit_form_eco() {
  local fields=("Charge limit %" 1 1 "${ECO_CHARGE_LIMIT:-80}" 1 15 10 0)
  local result
  result=$(tui_form "ECO / CHARGE" \
    "Set charge limit (0 = off, 50-100 = limit):" 8 44 1 "${fields[@]}") || return
  while IFS= read -r val; do
    [ -n "$val" ] && "$CORE" set ECO_CHARGE_LIMIT "$val" 2>/dev/null || true
  done <<< "$result"
}

edit_form_thermal() {
  local fields=(
    "Max cstate (1-10)" 1 1 "${MAX_CSTATE:-4}" 1 20 10 0
    "Kernel params" 2 1 "${KERNEL_PARAMS:-}" 2 20 50 0
  )
  local result
  result=$(tui_form "THERMAL" \
    "Edit thermal settings (kernel params need reboot):" 10 60 2 "${fields[@]}") || return
  local keys=(MAX_CSTATE KERNEL_PARAMS)
  local i=0
  while IFS= read -r val; do
    [ -n "$val" ] && "$CORE" set "${keys[$i]}" "$val" 2>/dev/null || true
    i=$((i + 1))
  done <<< "$result"
}

edit_form_display() {
  local fields=(
    "Scale" 1 1 "${DISPLAY_SCALE:-1.5}" 1 15 10 0
    "Resolution" 2 1 "${DISPLAY_RESOLUTION:-2160x1440}" 2 15 20 0
    "Refresh (Hz)" 3 1 "${DISPLAY_REFRESH:-60}" 3 15 10 0
  )
  local result
  result=$(tui_form "DISPLAY" \
    "Edit display settings:" 10 48 3 "${fields[@]}") || return
  local keys=(DISPLAY_SCALE DISPLAY_RESOLUTION DISPLAY_REFRESH)
  local i=0
  while IFS= read -r val; do
    [ -n "$val" ] && "$CORE" set "${keys[$i]}" "$val" 2>/dev/null || true
    i=$((i + 1))
  done <<< "$result"
}

popup_services() {
  bash "$SCRIPT_DIR/settings.sh" || true
}

popup_focus() {
  bash "$SCRIPT_DIR/focus.sh" || true
}

popup_profiles() {
  while true; do
    local c
    c=$(tui_menu "PROFILES" "Manage config profiles:" 12 44 4 \
      "save"   "Save current config as profile" \
      "load"   "Load a saved profile" \
      "list"   "List all profiles" \
      "back"   "Back") || break
    case "$c" in
      save)
        local name
        name=$(tui_input "SAVE PROFILE" "Profile name:" 8 44 "my-profile") || continue
        if [ -n "$name" ] && [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
          "$CORE" profile save "$name" 2>/dev/null || true
        else
          tui_msg "SAVE PROFILE" "Ten profile khong hop le (chu-cai/so/./_/-)" 6 50
          continue
        fi
        tui_msg "SAVE PROFILE" "Saved: $name" 6 40
        ;;
      load)
        local profiles=()
        local items=()
        mkdir -p "$SCRIPT_DIR/../profiles" 2>/dev/null || true
        for f in "$SCRIPT_DIR/../profiles"/*.conf; do
          [ -f "$f" ] || continue
          local name=$(basename "$f" .conf)
          profiles+=("$name")
          items+=("$name" "Load profile: $name")
        done
        if [ ${#items[@]} -eq 0 ]; then
          tui_msg "LOAD PROFILE" "No profiles found." 6 40
          continue
        fi
        items+=("back" "Back")
        local sel
        sel=$(tui_menu "LOAD PROFILE" "Select profile:" 14 44 6 "${items[@]}") || continue
        [ "$sel" = "back" ] && continue
        if tui_yn "LOAD PROFILE" "Load '$sel'?" 7 40; then
          "$CORE" profile load "$sel" 2>/dev/null || true
          tui_msg "LOAD PROFILE" "Loaded: $sel" 6 40
        fi
        ;;
      list)
        local output
        output=$("$CORE" profile list 2>/dev/null) || output="(none)"
        tui_msg "PROFILES" "Available:\n$output" 10 44
        ;;
      back|*) break ;;
    esac
  done
}

popup_tools() {
  local c
  c=$(tui_menu "TOOLS" "Choose tool:" 16 50 7 \
    "notes"    "Notes Manager (Obsidian)" \
    "games"    "Games (minetest, assaultcube, megaglest)" \
    "mount"    "Drive Manager — mount/unmount drives" \
    "wall"     "Wallpaper — chafa preview + changer" \
    "web"      "Web Dashboard (localhost:8765)" \
    "install"  "Auto Install Arch Linux" \
    "back"     "Back") || return
  case "$c" in
    notes)
      bash "$SCRIPT_DIR/notes.sh" || true
      ;;
    games)
      bash "$SCRIPT_DIR/games.sh" || true
      ;;
    mount)
      bash "$SCRIPT_DIR/mount.sh" || true
      ;;
    wall)
      bash "$SCRIPT_DIR/wallpaper.sh" || true
      ;;
    web)
      if pgrep -f "web.sh" &>/dev/null; then
        tui_msg "WEB DASHBOARD" "Running at:\nhttp://localhost:8765" 8 44
      else
        # web.sh la Python script — phai goi bang python3, khong phai bash
        nohup python3 "$SCRIPT_DIR/web.sh" >/tmp/calarch-web.log 2>&1 &
        tui_msg "WEB DASHBOARD" "Started at:\nhttp://localhost:8765" 8 44
      fi
      ;;
    install)
      bash "$SCRIPT_DIR/post-install.sh" post-install || true
      ;;
  esac
}

popup_ultrafocus() {
  while true; do
    local c
    c=$(tui_menu "ULTRAFOCUS" "Quan ly cong cu Ultrafocus:" 16 56 8 \
      "launcher" "Rofi Launcher — app menu + web search" \
      "firefox"  "Firefox — vertical tabs, privacy" \
      "kitty"    "Kitty + Zsh — terminal, shell, plugins" \
      "neovim"   "Neovim + LazyVim — editor + LSP" \
      "media"    "YouTube / Anime — terminal media player" \
      "spotify"  "Spotify + Spicetify — adblock, theme" \
      "emacs"    "Emacs Org-mode — notes, org-roam" \
      "back"     "Back") || break
    case "$c" in
      launcher) bash "$SCRIPT_DIR/launcher.sh" || true ;;
      firefox)  bash "$SCRIPT_DIR/firefox.sh" || true ;;
      kitty)    bash "$SCRIPT_DIR/kitty-ultrafocus.sh" || true ;;
      neovim)   bash "$SCRIPT_DIR/neovim.sh" || true ;;
      media)    bash "$SCRIPT_DIR/yt-video.sh" || true ;;
      spotify)  bash "$SCRIPT_DIR/spotify.sh" || true ;;
      emacs)    bash "$SCRIPT_DIR/emacs.sh" || true ;;
      back|*) break ;;
    esac
  done
}

popup_status() {
  clear
  echo -e "${P[title]}═══ CALARCH LIVE STATUS (ESC to exit) ═══${R}"
  echo ""
  local key
  while true; do
    tput home
    local load=$(cpu_load) temp=$(cpu_temp) freq=$(cpu_freq)
    local mu=$(mem_used) mt=$(mem_total)
    local su=$(swap_used) st=$(swap_total)
    local mp=$((mt>0 ? mu*100/mt : 0))
    local lcol="${P[ok]}"; [ "$load" -gt 70 ] && lcol="${P[crit]}"
    local mcol="${P[ok]}"; [ "$mp" -gt 80 ] && mcol="${P[crit]}"
    local tcol="${P[ok]}"; [ "$temp" -gt 80 ] && tcol="${P[crit]}"
    local gov=$(gov_text) uv="${UNDERVOLT_CPU:-0}/${UNDERVOLT_GPU:-0}/${UNDERVOLT_CACHE:-0}"
    local eco_s=$(eco_mode)
    local eco_disp="${P[ok]}ON ${ECO_CHARGE_LIMIT:-80}%"; [ "$eco_s" != "1" ] && eco_disp="${P[muted]}OFF${R}"
    local super_disp="${P[ok]}ACTIVE"; pgrep -f "super-mode.sh" &>/dev/null || super_disp="${P[muted]}OFF${R}"

    printf "\r${P[title]}CPU${R}  ${lcol}%3d%%${R}  ${tcol}%2d°C${R}  %sMHz  ${P[muted]}%s${R}\n" "$load" "$temp" "$freq" "$gov"
    printf "${P[title]}MEM${R}  ${mcol}%3d%%${R}  ${mu}/${mt}MB  (Swap: ${su}/${st}MB)\n" "$mp"
    printf "${P[title]}ECO${R}  %b  ${P[title]}Super${R} %b  ${P[title]}UV${R}  %smV  ${P[title]}CState${R} %s\n" "$eco_disp" "$super_disp" "$uv" "${MAX_CSTATE:-4}"
    echo ""
    echo -e "${P[muted]}Press ESC to return to dashboard${R}"
    IFS= read -sn1 -t 2 key
    [ "$key" = $'\e' ] && break
  done
}

# ============================================================================
# MAIN LOOP
# ============================================================================
main_loop() {
  enable_mouse
  draw_all
  while true; do
    read_event || exit 0
    case "$EVENT_TYPE" in
      mouse) handle_mouse ;;
      key)   handle_key ;;
    esac
  done
}

# ============================================================================
# ENTRY
# ============================================================================
trap 'disable_mouse; clear; echo "Bye."; exit 1' INT TERM
trap 'redraw_all' WINCH

"$CORE" boot_check 2>/dev/null || true
# i_am_alive phai goi sau login (khong goi ngay cung luc o day, neu khong
# boot guard khong bao gio kich hoat).

if ! tui_detect; then
  echo -e "\e[31mERROR: gum not found. Install: sudo pacman -S gum\e[0m"
  exit 1
fi

load_layout
load_palette
main_loop
