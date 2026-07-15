#!/bin/bash
# ============================================================================
# CORE.SH — Config engine + Safety + Profile manager
# ----------------------------------------------------------------------------
# TICH HOP:
#   config I/O   get/set/list config values
#   safety       validate, snapshot, grace period, boot guard
#   history      undo, log
#   profile      save/load/list/delete named configs
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../calarch.conf"
PROFILE_DIR="$SCRIPT_DIR/../profiles"
HISTORY_DIR="/var/lib/calarch/history"
HISTORY_LOG="$HISTORY_DIR/history.log"
BOOT_COUNT_FILE="/var/lib/calarch/boot-count"
GRACE_DIR="/tmp/calarch-grace"

mkdir -p "$HISTORY_DIR" "$GRACE_DIR" "$PROFILE_DIR" 2>/dev/null || true

# ============================================================================
# SCHEMA: validation rules cho tung key
# ============================================================================
# Format: KEY|type|min|max|enum_values
SCHEMA=(
  "AFFINITY_ACTIVE_CORES|cpu_list|||"
  "AFFINITY_BG_CORES|cpu_list|||"
  "AFFINITY_ACTIVE_SCHED|enum|||rr,other,fifo"
  "AFFINITY_ACTIVE_PRIORITY|int|1|99|"
  "AFFINITY_ACTIVE_IONICE|int|0|7|"
  "AFFINITY_BG_IONICE|int|0|7|"
  "SUPER_COOL_THRESHOLD|int|0|100|"
  "SUPER_HOT_THRESHOLD|int|0|100|"
  "SUPER_COOL_DEBOUNCE|int|1|60|"
  "SUPER_HOT_DEBOUNCE|int|1|60|"
  "SUPER_COOL_GOVERNOR|enum|||powersave,schedutil,performance,conservative,ondemand"
  "SUPER_HOT_GOVERNOR|enum|||powersave,schedutil,performance,conservative,ondemand"
  "UNDERVOLT_CPU|int|-150|0|"
  "UNDERVOLT_GPU|int|-150|0|"
  "UNDERVOLT_CACHE|int|-150|0|"
  "ECO_CHARGE_LIMIT|int|0|100|"
  "MAX_CSTATE|int|1|10|"
  "POMODORO_WORK_MINUTES|int|1|120|"
  "POMODORO_BREAK_MINUTES|int|1|30|"
  "POMODORO_CYCLES|int|1|20|"
  "KERNEL_PARAMS|str|||"
  "BLOCKER_SITES|str|||"
  "DISPLAY_SCALE|float|0.5|3.0|"
  "DISPLAY_RESOLUTION|str|||"
  "DISPLAY_REFRESH|int|30|240|"
  "LAUNCHER_ENGINE|enum|||rofi,dmenu,wofi"
  "LAUNCHER_THEME|str|||"
  "LAUNCHER_SHORTCUT|str|||"
  "FIREFOX_VTABS|enum|||yes,no"
  "FIREFOX_VTABS_ENGINE|enum|||sidebery,tree-style-tab"
  "FIREFOX_PRIVACY|enum|||strict,standard,custom"
  "EDITOR_ENGINE|enum|||neovim,emacs,vscode"
  "EDITOR_DISTRO|enum|||lazyvim,astronvim,nvchad"
  "MEDIA_YT_PLAYER|enum|||mpv,vlc"
  "MEDIA_QUALITY|enum|||720p,1080p,2160p,best"
  "SPOTIFY_THEME|str|||"
  "SPOTIFY_ADBLOCK|enum|||yes,no"
  "NOTES_ENGINE|enum|||emacs-org,obsidian"
  "MOUNT_BASE|str|||"
  "WALLPAPER_DIR|str|||"
  "WALLPAPER_ENGINE|enum|||hyprpaper,swaybg,feh"
  "WALLPAPER_MONITOR|str|||"
  "REFIND_SYNC_ESP|enum|||true,false"
)

# ============================================================================
# UTILITY
# ============================================================================
R='\033[0m'; B='\033[1m'; D='\033[0;90m'; RED='\033[0;31m'; GR='\033[0;32m'
YEL='\033[1;33m'; CY='\033[0;36m'; MG='\033[0;35m'

log_i()  { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_w()  { echo -e "${YEL}[!!]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }

has() { command -v "$1" &>/dev/null; }

# ============================================================================
# CONFIG I/O
# ============================================================================

# get <KEY> — doc gia tri tu calarch.conf
get() {
  local key="$1"
  [ ! -f "$CONFIG_FILE" ] && return 1
  grep -E "^${key}=" "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- || true
}

# set <KEY> <VAL> — validate + snapshot + ghi + apply + grace
config_set() {
  local key="$1" val="$2"
  local old
  old=$(get "$key") || true

  validate "$key" "$val" || return 1

  snapshot "$key" "$old"

  if [ -f "$CONFIG_FILE" ]; then
    if grep -qE "^${key}=" "$CONFIG_FILE"; then
      sed -i "s|^${key}=.*|${key}=${val}|" "$CONFIG_FILE"
    else
      echo "${key}=${val}" >> "$CONFIG_FILE"
    fi
  else
    echo "${key}=${val}" > "$CONFIG_FILE"
  fi

  apply "$key" "$val"
  log "$key" "$old" "$val"

  if is_critical "$key"; then
    grace_start "$key" "$old"
  fi
}

# list — in tat ca config (bo comment, bo dong trong)
list() {
  [ ! -f "$CONFIG_FILE" ] && return
  grep -vE '^\s*(#|$)' "$CONFIG_FILE" || true
}

# list_json — JSON output cho web dashboard
list_json() {
  echo "{"
  local first=true
  while IFS='=' read -r key val; do
    [ -z "$key" ] && continue
    $first || echo ","
    first=false
    printf "\"%s\": \"%s\"" "$key" "$val"
  done < <(list)
  echo ""
  echo "}"
}

# ============================================================================
# VALIDATION
# ============================================================================

# validate <KEY> <VAL> — kiem tra theo schema
validate() {
  local key="$1" val="$2"
  local rule
  rule=$(printf "%s\n" "${SCHEMA[@]}" | grep -E "^${key}\|" || true)
  [ -z "$rule" ] && return 0  # key khong co rule -> skip

  local type min max enum_str
  IFS='|' read -r _ type min max enum_str <<< "$rule"

  case "$type" in
    int)
      if ! [[ "$val" =~ ^-?[0-9]+$ ]]; then
        log_e "Loi: $key phai la so nguyen (co: $val)"
        return 1
      fi
      if [ -n "$min" ] && [ "$val" -lt "$min" ] 2>/dev/null; then
        log_e "Loi: $key toi thieu $min (co: $val)"
        return 1
      fi
      if [ -n "$max" ] && [ "$val" -gt "$max" ] 2>/dev/null; then
        log_e "Loi: $key toi da $max (co: $val)"
        return 1
      fi
      ;;
    cpu_list)
      local nproc
      nproc=$(nproc 2>/dev/null || echo 4)
      local max_core=$((nproc - 1))
      for c in ${val//,/ }; do
        if ! [[ "$c" =~ ^[0-9]+$ ]] || [ "$c" -gt "$max_core" ]; then
          log_e "Loi: $key core $c khong hop le (0-$max_core)"
          return 1
        fi
      done
      ;;
    enum)
      local valid=false
      local IFS=','
      for e in $enum_str; do
        [ "$val" = "$e" ] && { valid=true; break; }
      done
      unset IFS
      if ! $valid; then
        log_e "Loi: $key phai la 1 trong: $enum_str (co: $val)"
        return 1
      fi
      ;;
    str)
      [ -z "$val" ] && { log_e "Loi: $key khong duoc de trong"; return 1; }
      ;;
    float)
      if ! [[ "$val" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
        log_e "Loi: $key phai la so thuc (co: $val)"
        return 1
      fi
      if [ -n "$min" ] && awk "BEGIN {exit !($val < $min)}" 2>/dev/null; then
        log_e "Loi: $key toi thieu $min (co: $val)"
        return 1
      fi
      if [ -n "$max" ] && awk "BEGIN {exit !($val > $max)}" 2>/dev/null; then
        log_e "Loi: $key toi da $max (co: $val)"
        return 1
      fi
      ;;
    LAUNCHER_ENGINE)
      log_i "Launcher engine thay doi thanh: $val (can setup launcher)"
      ;;
    FIREFOX_VTABS)
      log_i "Firefox vertical tabs: $val (can chay firefox.sh de ap dung)"
      ;;
    EDITOR_ENGINE)
      log_i "Editor engine: $val"
      ;;
    MEDIA_YT_PLAYER)
      log_i "Media player: $val"
      ;;
    SPOTIFY_THEME)
      log_i "Spotify theme: $val (chay spotify.sh de ap dung)"
      ;;
    NOTES_ENGINE)
      log_i "Notes engine: $val"
      ;;
  esac
  return 0
}

# ============================================================================
# APPLY — ap dung gia tri ra he thong
# ============================================================================

apply() {
  local key="$1" val="$2"
  case "$key" in
    AFFINITY_ACTIVE_CORES|AFFINITY_BG_CORES)
      log_i "Affinity cores thay doi: can restart Affinity Engine"
      ;;
    AFFINITY_ACTIVE_SCHED)
      log_i "Scheduling policy thay doi: can restart Affinity Engine"
      ;;
    SUPER_COOL_*|SUPER_HOT_*)
      log_i "Super Mode ngưỡng thay doi: da cap nhat (can restart daemon)"
      ;;
    UNDERVOLT_*)
      if has intel-undervolt; then
        local cpu gpu cache
        cpu=$(get UNDERVOLT_CPU)
        gpu=$(get UNDERVOLT_GPU)
        cache=$(get UNDERVOLT_CACHE)
        sudo intel-undervolt apply --cpu "$cpu" --gpu "$gpu" --cache "$cache" 2>/dev/null && \
          log_ok "Undervolt ap dung: CPU ${cpu}mV / GPU ${gpu}mV / Cache ${cache}mV" || \
          log_w "Undervolt apply that bai"
      else
        log_w "intel-undervolt chua cai dat"
      fi
      ;;
    ECO_CHARGE_LIMIT)
      local p="/sys/devices/platform/panasonic/eco_mode"
      if [ -f "$p" ]; then
        local eco_val=0
        [ "$val" -gt 0 ] && [ "$val" -lt 100 ] && eco_val=1
        echo "$eco_val" | sudo tee "$p" >/dev/null 2>&1 && \
          log_ok "Eco mode: ${eco_val} (charge limit ${val}%)" || \
          log_w "Eco mode khong ap dung duoc"
      fi
      ;;
  esac
}

# is_critical — nhung key can grace period
is_critical() {
  local key="$1"
  case "$key" in
    UNDERVOLT_*|SUPER_COOL_GOVERNOR|SUPER_HOT_GOVERNOR|MAX_CSTATE) return 0 ;;
    *) return 1 ;;
  esac
}

# ============================================================================
# SAFETY — SNAPSHOT
# ============================================================================

snapshot() {
  local key="$1" old="$2"
  local ts
  ts=$(date '+%Y%m%d-%H%M%S')
  if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$HISTORY_DIR/config-${ts}.bak" 2>/dev/null || true
  fi
  # Cleanup: giu toi da 50 ban backup
  ls -t "$HISTORY_DIR"/config-*.bak 2>/dev/null | tail -n +51 | xargs rm -f 2>/dev/null || true
}

# ============================================================================
# SAFETY — GRACE PERIOD
# ============================================================================

grace_start() {
  local key="$1" old="$2"
  local pid_file="$GRACE_DIR/${key}.pid"

  # Kill grace cu neu co
  [ -f "$pid_file" ] && kill "$(cat "$pid_file")" 2>/dev/null || true

  (
    sleep 300
    # Het 5 phut: tu dong revert
    local current
    current=$(get "$key") || true
    if [ "$current" != "$old" ]; then
      log_w "Grace period het han: revert ${key}=${old}"
      sudo bash "$SCRIPT_DIR/core.sh" set "$key" "$old" 2>/dev/null || true
    fi
    rm -f "$pid_file"
  ) &
  local pid=$!
  echo "$pid" > "$pid_file"

  local min_sec
  min_sec=$(date '+%H:%M:%S')
  log_w "Grace period: ${key} da thay doi. Xac nhan trong 5 phut (${min_sec})!"
  log_w "  -> chay: bash lib/core.sh grace_confirm ${key}"
}

grace_confirm() {
  local key="$1"
  if [ "$key" = "all" ]; then
    for f in "$GRACE_DIR"/*.pid; do
      [ -f "$f" ] || continue
      local k
      k=$(basename "$f" .pid)
      kill "$(cat "$f")" 2>/dev/null || true
      rm -f "$f"
      log_ok "Grace xac nhan: ${k}"
    done
    return
  fi
  local pid_file="$GRACE_DIR/${key}.pid"
  if [ -f "$pid_file" ]; then
    kill "$(cat "$pid_file")" 2>/dev/null || true
    rm -f "$pid_file"
    log_ok "Grace xac nhan: ${key} da duoc giu nguyen"
  else
    log_w "Khong co grace pending cho ${key}"
  fi
}

grace_status() {
  local output=""
  for f in "$GRACE_DIR"/*.pid; do
    [ -f "$f" ] || continue
    local key
    key=$(basename "$f" .pid)
    local pid
    pid=$(cat "$f" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      local elapsed remain
      elapsed=$(ps -o etimes= -p "$pid" 2>/dev/null || echo 0)
      remain=$((300 - elapsed))
      [ "$remain" -lt 0 ] && remain=0
      output="$output$key:${remain} "
    else
      rm -f "$f" 2>/dev/null
    fi
  done
  echo "$output"
}

# ============================================================================
# SAFETY — BOOT GUARD
# ============================================================================

boot_guard_check() {
  local count=0
  [ -f "$BOOT_COUNT_FILE" ] && count=$(cat "$BOOT_COUNT_FILE" 2>/dev/null || echo 0)
  count=$((count + 1))
  echo "$count" > "$BOOT_COUNT_FILE"

  if [ "$count" -gt 2 ]; then
    local last_backup
    last_backup=$(ls -t "$HISTORY_DIR"/config-*.bak 2>/dev/null | head -1 || true)
    if [ -n "$last_backup" ]; then
      log_w "Phat hien ${count} lan boot khong hoan tat! Dang rollback config..."
      cp "$last_backup" "$CONFIG_FILE"
      log_ok "Da rollback den: $(basename "$last_backup")"
    fi
  fi
  return "$((count > 2 ? 1 : 0))"
}

boot_guard_alive() {
  echo 0 > "$BOOT_COUNT_FILE"
}

# ============================================================================
# HISTORY / UNDO
# ============================================================================

log() {
  local key="$1" old="$2" new="$3"
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "${ts} | ${key} | ${old} | ${new}" >> "$HISTORY_LOG"
  # Giữ tối đa 500 dòng
  tail -n 500 "$HISTORY_LOG" > "${HISTORY_LOG}.tmp" && mv "${HISTORY_LOG}.tmp" "$HISTORY_LOG" 2>/dev/null || true
}

undo() {
  if [ ! -f "$HISTORY_LOG" ]; then
    log_w "Khong co lich su thay doi"
    return
  fi
  local last_line
  last_line=$(tail -1 "$HISTORY_LOG" 2>/dev/null || true)
  [ -z "$last_line" ] && { log_w "Lich su trong"; return; }

  local key old
  key=$(echo "$last_line" | cut -d'|' -f2 | xargs)
  old=$(echo "$last_line" | cut -d'|' -f3 | xargs)

  if [ -n "$key" ] && [ -n "$old" ]; then
    log_i "Undo: ${key} = ${old}"
    config_set "$key" "$old"
    # Xoa dong cuoi khoi log de undo tiep theo duoc
    sed -i '$d' "$HISTORY_LOG" 2>/dev/null || true
  fi
}

show_log() {
  local n="${1:-10}"
  [ ! -f "$HISTORY_LOG" ] && { echo "(empty)"; return; }
  tail -n "$n" "$HISTORY_LOG" | while IFS='|' read -r ts key old new; do
    echo -e "${D}${ts}${R} | ${CY}${key}${R} | ${RED}${old}${R} -> ${GR}${new}${R}"
  done
}

# ============================================================================
# PROFILE MANAGER
# ============================================================================

profile_save() {
  local name="$1"
  [ -z "$name" ] && { log_e "Thieu ten profile"; return 1; }
  mkdir -p "$PROFILE_DIR" 2>/dev/null || true
  cp "$CONFIG_FILE" "$PROFILE_DIR/${name}.conf" 2>/dev/null && \
    log_ok "Profile saved: ${name}" || \
    log_e "Khong the luu profile: ${name}"
}

profile_load() {
  local name="$1"
  local file="$PROFILE_DIR/${name}.conf"
  [ ! -f "$file" ] && { log_e "Profile khong ton tai: ${name}"; return 1; }

  log_i "Loading profile: ${name}"
  while IFS='=' read -r key val; do
    [ -z "$key" ] && continue
    config_set "$key" "$val" 2>/dev/null || true
  done < <(grep -vE '^\s*(#|$)' "$file")
  log_ok "Profile loaded: ${name}"
}

profile_list() {
  mkdir -p "$PROFILE_DIR" 2>/dev/null || true
  local files
  files=$(ls "$PROFILE_DIR"/*.conf 2>/dev/null)
  [ -z "$files" ] && { echo "(no profiles)"; return; }
  for f in $files; do
    local name
    name=$(basename "$f" .conf)
    echo "$name"
  done
}

profile_delete() {
  local name="$1"
  local file="$PROFILE_DIR/${name}.conf"
  [ ! -f "$file" ] && { log_e "Profile khong ton tai: ${name}"; return 1; }
  rm "$file" && log_ok "Profile deleted: ${name}"
}

# ============================================================================
# API — JSON output cho web dashboard
# ============================================================================

api_status() {
  local temp freq load eco super grace
  temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.0f", $1/1000}' || echo "?")
  freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null | awk '{printf "%.2f", $1/1000000}' || echo "?")
  load=$(awk '/cpu /{printf "%d",($2+$4)*100/($2+$4+$5)}' /proc/stat 2>/dev/null || echo "?")
  eco=$(cat /sys/devices/platform/panasonic/eco_mode 2>/dev/null || echo "?")
  super=$(pgrep -f "super-mode.sh" &>/dev/null && echo "1" || echo "0")
  grace=$(grace_status)

  cat << JSON
{
  "temp": "${temp}",
  "freq": "${freq}",
  "load": "${load}",
  "eco": "${eco}",
  "super": "${super}",
  "grace": "${grace}"
}
JSON
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  local cmd="${1:-help}"

  case "$cmd" in
    get)        get "${2:-}" ;;
    set)        config_set "${2:-}" "${3:-}" ;;
    list)       list ;;
    list-json)  list_json ;;
    api)        api_status ;;
    validate)   validate "${2:-}" "${3:-}" ;;
    apply)      apply "${2:-}" "${3:-}" ;;
    grace_confirm) grace_confirm "${2:-}" ;;
    grace_status) grace_status ;;
    boot_check) boot_guard_check ;;
    i_am_alive) boot_guard_alive ;;
    undo)       undo ;;
    log)        show_log "${2:-10}" ;;
    profile)
      local action="${2:-list}"
      case "$action" in
        save)   profile_save "${3:-}" ;;
        load)   profile_load "${3:-}" ;;
        list)   profile_list ;;
        delete) profile_delete "${3:-}" ;;
        *)      echo "Usage: core.sh profile {save|load|list|delete} [name]" ;;
      esac
      ;;
    help|*)
      echo "Usage: core.sh <command> [args]"
      echo ""
      echo "Config:"
      echo "  get <KEY>                Doc gia tri config"
      echo "  set <KEY> <VAL>          Ghi + validate + apply + grace"
      echo "  list                     Liet ke config"
      echo "  list-json                JSON format"
      echo ""
      echo "Safety:"
      echo "  validate <KEY> <VAL>     Kiem tra gia tri"
      echo "  apply <KEY> <VAL>        Ap dung ra he thong"
      echo "  grace_confirm <KEY>      Xac nhan thay doi critical"
      echo "  grace_status             Kiem tra grace pending"
      echo "  boot_check               Kiem tra boot counter (goi khi start)"
      echo "  i_am_alive               Reset boot counter (goi sau khi login)"
      echo ""
      echo "History:"
      echo "  undo                     Hoan tac thay doi cuoi"
      echo "  log [n]                  Xem n thay doi gan nhat"
      echo ""
      echo "Profile:"
      echo "  profile save <name>      Luu config hien tai"
      echo "  profile load <name>      Nap config tu profile"
      echo "  profile list             Danh sach profile"
      echo "  profile delete <name>    Xoa profile"
      echo ""
      echo "Web:"
      echo "  api                      JSON status (CPU temp, freq, load...)"
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
