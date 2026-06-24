#!/bin/bash
# ============================================================================
# DASHBOARD.SH — TUI Control Center: live dashboard + settings + everything
# ----------------------------------------------------------------------------
# Thay the hoan toan start.sh cu.
# Hien thi real-time CPU temp/freq/load, Eco, Super Mode, Grace, Boot guard.
# Tich hop settings, games, focus, profiles, history.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE="$SCRIPT_DIR/core.sh"
source "$SCRIPT_DIR/tui.sh"
source "$SCRIPT_DIR/../calarch.conf" 2>/dev/null || true

# ============================================================================
# CONSTANTS
# ============================================================================
R='\033[0m'; B='\033[1m'; D='\033[0;90m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'
CY='\033[0;36m'; MG='\033[0;35m'; BL='\033[0;34m'; WH='\033[1;37m'

BAR_FULL='━'
BAR_EMPTY='━'
BAR_LEFT='┃'
BAR_RIGHT='┃'

SETTINGS_SH="$SCRIPT_DIR/settings.sh"
GAMES_SH="$SCRIPT_DIR/games.sh"
FOCUS_SH="$SCRIPT_DIR/focus.sh"
NOTES_SH="$SCRIPT_DIR/notes.sh"

# ============================================================================
# HELPERS
# ============================================================================
log_i()  { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_w()  { echo -e "${YEL}[!!]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }
has()     { command -v "$1" &>/dev/null; }

num_bar() {
  local pct=$1 w=$2
  local fill=$((pct * w / 100))
  local empty=$((w - fill))
  [ "$fill" -gt "$w" ] && fill=$w
  [ "$empty" -lt 0 ] && empty=0
  local color="${3:-$GR}"
  echo -ne "${color}"
  printf '%*s' "$fill" '' | tr ' ' "$BAR_FULL"
  echo -ne "${D}"
  printf '%*s' "$empty" '' | tr ' ' "$BAR_EMPTY"
  echo -ne "${R}"
}

menu_item() {
  local num="${MG}${1}${R}" title="${CY}${2}${R}" desc="${3:-}"
  echo -e "  ${num}  ${title}  ${D}${desc}${R}"
}

header_line() {
  local label="$1" val="$2" color="${3:-$GR}"
  echo -ne "${D}${label}${R} ${color}${val}${R}"
}

dashboard_bar() {
  local label="$1" pct="$2" color="${3:-$GR}"
  pct=$((pct > 100 ? 100 : pct < 0 ? 0 : pct))
  local bar
  bar=$(num_bar "$pct" 20 "$color")
  echo -ne " ${D}${label}${R} ${BAR_LEFT}${bar}${BAR_RIGHT} ${color}${pct}%${R}"
}

# ============================================================================
# STATUS GATHERING
# ============================================================================

cpu_temp() {
  local t=0
  [ -f /sys/class/thermal/thermal_zone0/temp ] && t=$(cat /sys/class/thermal/thermal_zone0/temp) && t=$((t/1000))
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

eco_status() {
  local v
  v=$(cat /sys/devices/platform/panasonic/eco_mode 2>/dev/null || echo "?")
  [ "$v" = "1" ] && echo -e "${GR}ON${R} 80%" || echo -e "${D}OFF${R} 100%"
}

super_status() {
  if pgrep -f "super-mode.sh" &>/dev/null; then
    echo -ne "${GR}ACTIVE${R}"
  else
    echo -ne "${D}OFF${R}"
  fi
}

affinity_status() {
  if pgrep -f "hyprland-event-monitor.sh" &>/dev/null; then
    echo -ne "${GR}ACTIVE${R}"
  else
    echo -ne "${D}OFF${R}"
  fi
}

governor_status() {
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "?"
}

grace_info() {
  local g
  g=$("$CORE" grace_status 2>/dev/null) || true
  [ -n "$g" ] && echo "$g" || echo ""
}

boot_info() {
  local c=0
  [ -f /var/lib/calarch/boot-count ] && c=$(cat /var/lib/calarch/boot-count 2>/dev/null || echo 0)
  if [ "$c" -le 2 ]; then
    echo -e "${GR}OK${R} (${c} boot)"
  else
    echo -e "${RED}ISSUE${R} (${c} boots)"
  fi
}

ov_status() {
  local temp freq load mem_used_pct
  temp=$(cpu_temp)
  freq=$(cpu_freq)
  load=$(cpu_load)
  local mu mt
  mu=$(mem_used)
  mt=$(mem_total)
  [ "$mt" -gt 0 ] && mem_used_pct=$((mu * 100 / mt)) || mem_used_pct=0

  clear
  echo ""
  echo -e "  ${WH}ARCHCAL DASHBOARD${R}  ${D}$(date '+%H:%M:%S')${R}"
  echo ""

  # CPU bar
  dashboard_bar "CPU" "$load" "$([ "$load" -gt 70 ] && echo "$RED" || echo "$GR")"
  echo -ne "  "
  header_line "Temp" "${temp}°C" "$([ "$temp" -gt 80 ] && echo "$RED" || echo "$GR")"
  echo -ne "  "
  header_line "Freq" "${freq}MHz"
  echo -ne "  "
  header_line "Gov" "$(governor_status)"
  echo ""

  # MEM bar
  dashboard_bar "MEM" "$mem_used_pct" "$BL"
  echo -ne "  ${D}Used${R} ${mu}MB / ${mt}MB"
  local swap_used swap_total
  swap_used=$(free -m 2>/dev/null | awk '/Swap:/{printf "%d", $3}')
  swap_total=$(free -m 2>/dev/null | awk '/Swap:/{printf "%d", $2}')
  [ -n "$swap_total" ] && [ "$swap_total" -gt 0 ] && echo -ne "  ${D}Swap${R} ${swap_used}MB / ${swap_total}MB"
  echo ""

  echo ""
  # Status line
  echo -e "  ${D}Eco:${R} $(eco_status)  ${D}Super:${R} $(super_status)  ${D}Affinity:${R} $(affinity_status)"
  local g
  g=$(grace_info)
  [ -n "$g" ] && echo -e "  ${YEL}⏳ Grace:${R} ${g}s  (${CY}core.sh grace_confirm <KEY>${R})"
  echo -e "  ${D}Boot guard:${R} $(boot_info)"
  echo ""
}

# ============================================================================
# MENUS
# ============================================================================

menu_system() {
  while true; do
    ov_status
    echo -e "  ${MG}=== SYSTEM SETTINGS ===${R}"
    echo ""
    echo -e "  ${MG}1${R}  ${CY}CPU Affinity${R}     ${D}cores, policy, priority${R}"
    echo -e "  ${MG}2${R}  ${CY}Super Mode${R}       ${D}thresholds, governor, debounce${R}"
    echo -e "  ${MG}3${R}  ${CY}Undervolt${R}        ${D}CPU/GPU/Cache mV${R}"
    echo -e "  ${MG}4${R}  ${CY}Eco Mode${R}         ${D}charge limit %${R}"
    echo -e "  ${MG}5${R}  ${CY}Thermal / Kernel${R} ${D}max_cstate, kernel params${R}"
    echo -e "  ${MG}6${R}  ${CY}Pomodoro${R}         ${D}work/break time, cycles${R}"
    echo -e "  ${MG}7${R}  ${CY}Blocker${R}          ${D}cac site can chan${R}"
    echo -e "  ${MG}B${R}  ${D}Back${R}"
    echo ""
    read -r -p "  Chon: " c
    case "$c" in
      1) edit_affinity ;;
      2) edit_super ;;
      3) edit_undervolt ;;
      4) edit_eco ;;
      5) edit_thermal ;;
      6) edit_pomodoro ;;
      7) edit_blocker ;;
      b|B) break ;;
    esac
  done
}

# --- Edit functions: read current -> prompt -> core.sh set -> confirm/safety ---
edit_affinity() {
  echo ""
  echo -e "${CY}--- CPU AFFINITY ---${R}"
  echo -e "${D}Enter separated by commas (vd: 0,1)${R}"
  read -r -p "  Active cores [${AFFINITY_ACTIVE_CORES:-0,1}]: " val
  [ -n "$val" ] && "$CORE" set AFFINITY_ACTIVE_CORES "$val"
  read -r -p "  Background cores [${AFFINITY_BG_CORES:-2,3}]: " val
  [ -n "$val" ] && "$CORE" set AFFINITY_BG_CORES "$val"
  read -r -p "  Active sched policy [${AFFINITY_ACTIVE_SCHED:-rr}]: " val
  [ -n "$val" ] && "$CORE" set AFFINITY_ACTIVE_SCHED "$val"
  read -r -p "  Active priority [${AFFINITY_ACTIVE_PRIORITY:-50}]: " val
  [ -n "$val" ] && "$CORE" set AFFINITY_ACTIVE_PRIORITY "$val"
  read -r -p "  Enter..."
}

edit_super() {
  echo ""
  echo -e "${CY}--- SUPER MODE ---${R}"
  read -r -p "  Cool threshold % [${SUPER_COOL_THRESHOLD:-30}]: " val
  [ -n "$val" ] && "$CORE" set SUPER_COOL_THRESHOLD "$val"
  read -r -p "  Hot threshold % [${SUPER_HOT_THRESHOLD:-70}]: " val
  [ -n "$val" ] && "$CORE" set SUPER_HOT_THRESHOLD "$val"
  read -r -p "  Cool debounce (s) [${SUPER_COOL_DEBOUNCE:-10}]: " val
  [ -n "$val" ] && "$CORE" set SUPER_COOL_DEBOUNCE "$val"
  read -r -p "  Hot debounce (s) [${SUPER_HOT_DEBOUNCE:-5}]: " val
  [ -n "$val" ] && "$CORE" set SUPER_HOT_DEBOUNCE "$val"
  read -r -p "  Cool governor [${SUPER_COOL_GOVERNOR:-powersave}]: " val
  [ -n "$val" ] && "$CORE" set SUPER_COOL_GOVERNOR "$val"
  read -r -p "  Hot governor [${SUPER_HOT_GOVERNOR:-schedutil}]: " val
  [ -n "$val" ] && "$CORE" set SUPER_HOT_GOVERNOR "$val"
  read -r -p "  Enter..."
}

edit_undervolt() {
  echo ""
  echo -e "${RED}--- UNDERVOLT (mV, am = giam dien ap) ---${R}"
  echo -e "${YEL}Can than: gia tri am qua lon co the gay treo may!${R}"
  echo -e "${D}Grace period 5 phut se tu dong revert neu khong xac nhan.${R}"
  echo ""
  read -r -p "  CPU [${UNDERVOLT_CPU:--50}]: " val
  [ -n "$val" ] && "$CORE" set UNDERVOLT_CPU "$val"
  read -r -p "  GPU [${UNDERVOLT_GPU:--20}]: " val
  [ -n "$val" ] && "$CORE" set UNDERVOLT_GPU "$val"
  read -r -p "  Cache [${UNDERVOLT_CACHE:--50}]: " val
  [ -n "$val" ] && "$CORE" set UNDERVOLT_CACHE "$val"
  # Confirm grace
  local g
  g=$("$CORE" grace_status)
  [ -n "$g" ] && echo -e "${YEL}Grace pending: ${g}${R}"
  read -r -p "  Enter..."
}

edit_eco() {
  echo ""
  read -r -p "  Charge limit % [${ECO_CHARGE_LIMIT:-80}] (0=tat): " val
  [ -n "$val" ] && "$CORE" set ECO_CHARGE_LIMIT "$val"
  read -r -p "  Enter..."
}

edit_thermal() {
  echo ""
  echo -e "${CY}--- THERMAL ---${R}"
  read -r -p "  Max cstate [${MAX_CSTATE:-4}]: " val
  [ -n "$val" ] && "$CORE" set MAX_CSTATE "$val"
  echo -e "${D}Kernel params (can reboot de ap dung):${R}"
  echo -e "${D}  ${KERNEL_PARAMS}${R}"
  read -r -p "  Enter..."
}

edit_pomodoro() {
  echo ""
  read -r -p "  Work minutes [${POMODORO_WORK_MINUTES:-25}]: " val
  [ -n "$val" ] && "$CORE" set POMODORO_WORK_MINUTES "$val"
  read -r -p "  Break minutes [${POMODORO_BREAK_MINUTES:-5}]: " val
  [ -n "$val" ] && "$CORE" set POMODORO_BREAK_MINUTES "$val"
  read -r -p "  Cycles [${POMODORO_CYCLES:-4}]: " val
  [ -n "$val" ] && "$CORE" set POMODORO_CYCLES "$val"
  read -r -p "  Enter..."
}

edit_blocker() {
  echo ""
  echo -e "${D}Current sites: ${BLOCKER_SITES}${R}"
  read -r -p "  Sites (comma-separated, bo trong de bo qua): " val
  [ -n "$val" ] && "$CORE" set BLOCKER_SITES "$val"
  read -r -p "  Enter..."
}

# ============================================================================
# PROFILE MENU
# ============================================================================

menu_profiles() {
  while true; do
    ov_status
    echo -e "  ${MG}=== PROFILES ===${R}"
    echo ""
    echo -e "  ${MG}1${R}  ${CY}Save current${R}     ${D}luu config hien tai thanh profile${R}"
    echo -e "  ${MG}2${R}  ${CY}Load profile${R}     ${D}ap dung profile co san${R}"
    echo -e "  ${MG}3${R}  ${CY}List profiles${R}    ${D}xem danh sach${R}"
    echo -e "  ${MG}4${R}  ${CY}Delete profile${R}   ${D}xoa 1 profile${R}"
    echo -e "  ${MG}B${R}  ${D}Back${R}"
    echo ""
    read -r -p "  Chon: " c
    case "$c" in
      1)
        read -r -p "  Ten profile: " name
        [ -n "$name" ] && "$CORE" profile save "$name"
        read -r -p "  Enter..."
        ;;
      2)
        echo ""
        local profiles
        profiles=$("$CORE" profile list)
        if [ "$profiles" = "(no profiles)" ]; then
          echo -e "${D}Chua co profile nao.${R}"
        else
          echo -e "${D}Profiles:${R}"
          for p in $profiles; do
            echo "  - $p"
          done
          echo ""
          read -r -p "  Chon profile de load: " name
          [ -n "$name" ] && "$CORE" profile load "$name"
        fi
        read -r -p "  Enter..."
        ;;
      3)
        echo ""
        local profiles
        profiles=$("$CORE" profile list)
        if [ "$profiles" = "(no profiles)" ]; then
          echo -e "${D}Chua co profile nao.${R}"
        else
          echo -e "${D}Profiles:${R}"
          for p in $profiles; do
            echo "  - $p"
          done
        fi
        read -r -p "  Enter..."
        ;;
      4)
        read -r -p "  Ten profile de xoa: " name
        [ -n "$name" ] && "$CORE" profile delete "$name"
        read -r -p "  Enter..."
        ;;
      b|B) break ;;
    esac
  done
}

# ============================================================================
# SERVICES  (settings.sh)
# ============================================================================

menu_services() {
  if [ -f "$SETTINGS_SH" ]; then
    bash "$SETTINGS_SH"
  else
    log_e "Missing $SETTINGS_SH"
    read -r -p "  Enter..."
  fi
}

# ============================================================================
# FOCUS
# ============================================================================

menu_focus() {
  if [ -f "$FOCUS_SH" ]; then
    bash "$FOCUS_SH"
  else
    log_e "Missing $FOCUS_SH"
    read -r -p "  Enter..."
  fi
}

# ============================================================================
# GAMES
# ============================================================================

menu_games() {
  if [ -f "$GAMES_SH" ]; then
    bash "$GAMES_SH"
  else
    log_e "Missing $GAMES_SH"
    read -r -p "  Enter..."
  fi
}

# ============================================================================
# HISTORY
# ============================================================================

menu_history() {
  while true; do
    ov_status
    echo -e "  ${MG}=== HISTORY ===${R}"
    echo ""
    echo -e "  ${MG}1${R}  ${CY}View log${R}         ${D}10 thay doi gan nhat${R}"
    echo -e "  ${MG}2${R}  ${CY}Undo${R}             ${D}hoan tac thay doi cuoi${R}"
    echo -e "  ${MG}B${R}  ${D}Back${R}"
    echo ""
    read -r -p "  Chon: " c
    case "$c" in
      1)
        echo ""
        "$CORE" log 10
        read -r -p "  Enter..."
        ;;
      2)
        echo ""
        "$CORE" undo
        read -r -p "  Enter..."
        ;;
      b|B) break ;;
    esac
  done
}

# ============================================================================
# WEB
# ============================================================================

menu_web() {
  echo ""
  if pgrep -f "dashboard-web.sh" &>/dev/null; then
    log_ok "Web dashboard dang chay tai: ${GR}http://localhost:8765${R}"
    read -r -p "  [Enter] quay lai... "
  else
    log_i "Khoi dong web dashboard..."
    nohup bash "$SCRIPT_DIR/web.sh" >/tmp/calarch-web.log 2>&1 &
    sleep 1
    log_ok "Web dashboard: ${GR}http://localhost:8765${R}"
    read -r -p "  [Enter] quay lai... "
  fi
}

# ============================================================================
# MAIN LOOP
# ============================================================================

confirm_grace_all() {
  local g
  g=$("$CORE" grace_status)
  [ -z "$g" ] && { log_i "Khong co grace pending."; read -r -p "  Enter..."; return; }
  "$CORE" grace_confirm all 2>/dev/null || true
  log_ok "Da xac nhan tat ca grace."
  read -r -p "  Enter..."
}

main_loop() {
  while true; do
    ov_status
    echo ""
    echo -e "  ${MG}1${R}  ${CY}System${R}        ${D}CPU Affinity | Super Mode | Undervolt | Eco | Thermal${R}"
    echo -e "  ${MG}2${R}  ${CY}Services${R}      ${D}Docker | KVM | Ollama | Maintenance${R}"
    echo -e "  ${MG}3${R}  ${CY}Profiles${R}      ${D}Save | Load | Delete${R}"
    echo -e "  ${MG}4${R}  ${CY}Focus${R}         ${D}Pomodoro | Website Blocker${R}"
    echo -e "  ${MG}5${R}  ${CY}Web${R}           ${D}Mo dashboard tren trinh duyet${R}"
    echo -e "  ${MG}6${R}  ${CY}Games${R}         ${D}minetest | assaultcube | megaglest${R}"
    echo -e "  ${MG}7${R}  ${CY}History${R}       ${D}Xem log | Undo${R}"
    echo -e "  ${MG}C${R}  ${CY}Confirm Grace${R} ${D}Xac nhan thay doi critical (undervolt...)${R}"
    echo -e "  ${MG}0${R}  ${D}Exit${R}"
    echo ""
    read -r -p "  Chon: " c
    case "$c" in
      1) menu_system ;;
      2) menu_services ;;
      3) menu_profiles ;;
      4) menu_focus ;;
      5) menu_web ;;
      6) menu_games ;;
      7) menu_history ;;
      c|C) confirm_grace_all ;;
      0|q|Q) clear; echo -e "${GR}Goodbye!${R}"; exit 0 ;;
    esac
  done
}

# ============================================================================
# ENTRY
# ============================================================================

# First-boot mode
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "first-boot" ]; then
  [ -f "$SCRIPT_DIR/install.sh" ] && bash "$SCRIPT_DIR/install.sh"
  exit 0
fi

# Boot guard check
"$CORE" boot_check 2>/dev/null || true
"$CORE" i_am_alive 2>/dev/null || true

# Safety check
if ! tui_detect; then
  echo -e "${RED}ERROR: Can dialog hoac whiptail${R}"
  echo "  sudo pacman -S dialog"
  exit 1
fi

has pacman || { log_e "Not Arch Linux"; exit 1; }

# Start main loop
main_loop
