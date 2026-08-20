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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../calarch.conf"
PROFILE_DIR="$SCRIPT_DIR/../profiles"

# STATE base per-user (truoc day dat /var/lib — root-only, user thuong khong ghi duoc).
# Khi goi qua sudo, lay home cua SUDO_USER de revert cung dung state.
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  STATE_HOME=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || echo "$HOME")
  # getent co the exit 0 nhung khong in gi -> STATE_HOME rong
  [ -z "$STATE_HOME" ] && STATE_HOME="$HOME"
  HISTORY_DIR="$STATE_HOME/.local/state/calarch/history"
  HISTORY_LOG="$HISTORY_DIR/history.log"
  BOOT_COUNT_FILE="$STATE_HOME/.local/state/calarch/boot-count"
  GRACE_PENDING_DIR="$STATE_HOME/.local/state/calarch/grace-pending"
else
  HISTORY_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/calarch/history"
  HISTORY_LOG="$HISTORY_DIR/history.log"
  BOOT_COUNT_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/calarch/boot-count"
  GRACE_PENDING_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/calarch/grace-pending"
fi

# Grace dir per-user (cung STATE_HOME) — tranh /tmp/calarch-grace world-writable
# va dam bao user + sudo goi cung mot noi dung PID file.
GRACE_DIR="${HISTORY_DIR%/history}/grace"

mkdir -p "$HISTORY_DIR" "$GRACE_DIR" "$GRACE_PENDING_DIR" "$PROFILE_DIR" 2>/dev/null || true

# Khi tao state bang quyen root (qua sudo), tra quyen lai cho user thuong
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  chown -R "$SUDO_USER" "$HISTORY_DIR" "$GRACE_DIR" "$GRACE_PENDING_DIR" 2>/dev/null || true
fi

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
R='\033[0m'; D='\033[0;90m'; RED='\033[0;31m'; GR='\033[0;32m'
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
  local key="$1" val
  [ ! -f "$CONFIG_FILE" ] && return 1
  val=$(grep -E "^${key}=" "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- || true)
  [ -z "$val" ] && return 1
  # Bo cap ngoac kep neu co (config duoc ghi dang KEY="value")
  [[ "$val" == \"*\" && "${#val}" -ge 2 ]] && val="${val:1:${#val}-2}"
  printf '%s\n' "$val"
}

# set <KEY> <VAL> — validate + snapshot + ghi + apply + grace
config_set() {
  local key="$1" val="$2"
  # Tu choi key rong / khong hop le (tranh ghi dong "=..." vo nghia vao config)
  if [ -z "$key" ] || ! [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    log_e "Key khong hop le: '${key:-<empty>}'"
    return 1
  fi
  local old
  old=$(get "$key") || true

  validate "$key" "$val" || return 1

  snapshot "$key" "$old"

  if [ -f "$CONFIG_FILE" ]; then
    local newval
    newval=$(printf '%s' "$val" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    if grep -qE "^${key}=" "$CONFIG_FILE"; then
      awk -v k="${key}=" -v v="\"${newval}\"" '$0 ~ "^" k { $0=k v } 1' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
      mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    else
      printf '%s="%s"\n' "$key" "$val" >> "$CONFIG_FILE"
    fi
  else
    printf '%s="%s"\n' "$key" "$val" > "$CONFIG_FILE"
  fi

  apply "$key" "$val"
  log "$key" "$old" "$val"

  # Khi dang revert grace tu dong (CALARCH_GRACE_REVERT=1) thi KHONG mo grace moi,
  # tranh vong lap flip-flop 5 phut vo han.
  if [ -z "${PROFILE_LOADING:-}" ] && [ "${CALARCH_GRACE_REVERT:-0}" != "1" ] && is_critical "$key"; then
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
    # Bo cap ngoac kep bao quanh (config duoc ghi dang KEY="value")
    [[ "$val" == \"*\" && "${#val}" -ge 2 ]] && val="${val:1:${#val}-2}"
    $first || echo ","
    first=false
    # Escape JSON: dau \ truoc, sau do dau "
    key=${key//\\/\\\\}
    key=${key//\"/\\\"}
    val=${val//\\/\\\\}
    val=${val//\"/\\\"}
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
      if [ -z "$val" ]; then
        log_e "Loi: $key khong duoc de trong"
        return 1
      fi
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
      if [[ "$val" == *$'\n'* ]] || [[ "$val" == *$'\r'* ]]; then
        log_e "Loi: $key khong duoc chua ky tu xuong dong"
        return 1
      fi
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
        cpu=$(get UNDERVOLT_CPU) || cpu=""
        gpu=$(get UNDERVOLT_GPU) || gpu=""
        cache=$(get UNDERVOLT_CACHE) || cache=""
        for var in cpu gpu cache; do
          [ -z "${!var}" ] && { log_w "${var^^} is empty, skipping undervolt apply"; return 1; }
        done
        # intel-undervolt khong ho tro --cpu/--gpu/--cache; ghi config roi ap dung
        sudo sed -i -E "s/^(undervolt 0 )(.*)$/\1'CPU' ${cpu}/; s/^(undervolt 1 )(.*)$/\1'GPU' ${gpu}/; s/^(undervolt 2 )(.*)$/\1'CPU Cache' ${cache}/" /etc/intel-undervolt.conf 2>/dev/null || true
        sudo intel-undervolt apply 2>/dev/null && \
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
    LAUNCHER_ENGINE) log_i "Launcher engine: $val (can chay launcher.sh de ap dung)" ;;
    FIREFOX_VTABS)   log_i "Firefox vertical tabs: $val (chay firefox.sh de ap dung)" ;;
    EDITOR_ENGINE)   log_i "Editor engine: $val" ;;
    MEDIA_YT_PLAYER) log_i "Media player: $val" ;;
    SPOTIFY_THEME)   log_i "Spotify theme: $val (chay spotify.sh de ap dung)" ;;
    NOTES_ENGINE)    log_i "Notes engine: $val" ;;
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
    cp "$CONFIG_FILE" "$HISTORY_DIR/config-${ts}-$$-${RANDOM}.bak" 2>/dev/null || true
  fi
  # Cleanup: giu toi da 50 ban backup
  find "$HISTORY_DIR" -maxdepth 1 -name 'config-*.bak' -printf '%T@ %p\0' 2>/dev/null \
    | sort -rnz | tail -z -n +51 | cut -z -d' ' -f2- | xargs -0 rm -f 2>/dev/null || true
}

# ============================================================================
# SAFETY — GRACE PERIOD
# ============================================================================

grace_start() {
  local key="$1" old="$2"
  local pid_file="$GRACE_DIR/${key}.pid"
  local pending_file="$GRACE_PENDING_DIR/${key}"

  # Kill grace cu neu co
  [ -f "$pid_file" ] && kill "$(cat "$pid_file")" 2>/dev/null || true

  # Persist pending de tranh mat state khi reboot
  echo "$old" > "$pending_file"

  (
    sleep 300
    # Het 5 phut: tu dong revert. CALARCH_GRACE_REVERT=1 de config_set
    # khong mo grace moi (tranh vong lap flip-flop vo han).
    current=""
    current=$(get "$key") || true
    if [ "$current" != "$old" ]; then
      log_w "Grace period het han: revert ${key}=${old}"
      CALARCH_GRACE_REVERT=1 sudo bash "$SCRIPT_DIR/core.sh" set "$key" "$old" 2>/dev/null || true
    fi
    rm -f "$pid_file" "$pending_file"
  ) >/dev/null 2>&1 &
  local pid=$!
  echo "$pid" > "$pid_file"

  local min_sec
  min_sec=$(date '+%H:%M:%S')
  log_w "Grace period: ${key} da thay doi. Xac nhan trong 5 phut (${min_sec})!"
  log_w "  -> chay: bash lib/core.sh grace_confirm ${key}"
}

# Kiem tra va revert cac grace bi mat state do reboot
grace_recover_stale() {
  for f in "$GRACE_PENDING_DIR"/*; do
    [ -f "$f" ] || continue
    local key
    key=$(basename "$f")
    local pid_file="$GRACE_DIR/${key}.pid"
    # PID con song → grace van dang chay, bo qua. Da chet/reboot → revert
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
      continue
    fi
    rm -f "$pid_file" 2>/dev/null || true
    local old
    old=$(cat "$f" 2>/dev/null || true)
    [ -z "$old" ] && { rm -f "$f"; continue; }
    local current
    current=$(get "$key") || true
    if [ "$current" != "$old" ]; then
      log_w "Grace recover (reboot): revert ${key}=${old}"
      CALARCH_GRACE_REVERT=1 sudo bash "$SCRIPT_DIR/core.sh" set "$key" "$old" 2>/dev/null || true
    fi
    rm -f "$f"
  done
}

grace_confirm() {
  local key="$1"
  if [ "$key" = "all" ]; then
    for f in "$GRACE_DIR"/*.pid; do
      [ -f "$f" ] || continue
      local k
      k=$(basename "$f" .pid)
      kill "$(cat "$f")" 2>/dev/null || true
      rm -f "$f" "$GRACE_PENDING_DIR/$k"
      log_ok "Grace xac nhan: ${k}"
    done
    return
  fi
  local pid_file="$GRACE_DIR/${key}.pid"
  if [ -f "$pid_file" ]; then
    kill "$(cat "$pid_file")" 2>/dev/null || true
    rm -f "$pid_file" "$GRACE_PENDING_DIR/$key"
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
  grace_recover_stale

  local count=0
  [ -f "$BOOT_COUNT_FILE" ] && count=$(cat "$BOOT_COUNT_FILE" 2>/dev/null || echo 0)
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  count=$((count + 1))
  mkdir -p "$(dirname "$BOOT_COUNT_FILE")" 2>/dev/null || true
  echo "$count" > "$BOOT_COUNT_FILE" 2>/dev/null || true

  if [ "$count" -gt 2 ]; then
    local last_backup
    last_backup=$(find "$HISTORY_DIR" -maxdepth 1 -name 'config-*.bak' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
    if [ -n "$last_backup" ]; then
      log_w "Phat hien ${count} lan boot khong hoan tat! Dang rollback config..."
      cp "$last_backup" "$CONFIG_FILE"
      log_ok "Da rollback den: $(basename "$last_backup")"
    fi
  fi
  return "$((count > 2 ? 1 : 0))"
}

boot_guard_alive() {
  mkdir -p "$(dirname "$BOOT_COUNT_FILE")" 2>/dev/null || true
  echo 0 > "$BOOT_COUNT_FILE" 2>/dev/null || true
}

# ============================================================================
# HISTORY / UNDO
# ============================================================================

log() {
  local key="$1" old="$2" new="$3"
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  mkdir -p "$HISTORY_DIR" 2>/dev/null || true
  printf '%s\x1f%s\x1f%s\x1f%s\n' "$ts" "$key" "$old" "$new" >> "$HISTORY_LOG" 2>/dev/null || true
  tail -n 500 "$HISTORY_LOG" 2>/dev/null > "${HISTORY_LOG}.tmp" && mv "${HISTORY_LOG}.tmp" "$HISTORY_LOG" 2>/dev/null || true
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
  key=$(echo "$last_line" | cut -d$'\x1f' -f2 | xargs)
  old=$(echo "$last_line" | cut -d$'\x1f' -f3 | xargs)

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
  tail -n "$n" "$HISTORY_LOG" | while IFS=$'\x1f' read -r ts key old new; do
    echo -e "${D}${ts}${R} | ${CY}${key}${R} | ${RED}${old}${R} -> ${GR}${new}${R}"
  done
}

# ============================================================================
# PROFILE MANAGER
# ============================================================================

profile_save() {
  local name="$1"
  # Chan path traversal: ten profile chi cho phep [A-Za-z0-9._-]
  if [ -z "$name" ] || ! [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    log_e "Ten profile khong hop le (chi dung chu-cai, so, . _ -): '${name:-<empty>}'"
    return 1
  fi
  mkdir -p "$PROFILE_DIR" 2>/dev/null || true
  cp "$CONFIG_FILE" "$PROFILE_DIR/${name}.conf" 2>/dev/null && \
    log_ok "Profile saved: ${name}" || \
    log_e "Khong the luu profile: ${name}"
}

profile_load() {
  local name="$1"
  if [ -z "$name" ] || ! [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    log_e "Ten profile khong hop le: '${name:-<empty>}'"
    return 1
  fi
  local file="$PROFILE_DIR/${name}.conf"
  [ ! -f "$file" ] && { log_e "Profile khong ton tai: ${name}"; return 1; }

  log_i "Loading profile: ${name}"
  PROFILE_LOADING=1
  while IFS= read -r line; do
    [[ "$line" == *=* ]] || continue
    key=${line%%=*}
    val=${line#*=}
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    # Bo cap ngoac kep neu co (profile luu dung dinh dang KEY="value")
    [[ "$val" == \"*\" && "${#val}" -ge 2 ]] && val="${val:1:${#val}-2}"
    [ -z "$key" ] && continue
    config_set "$key" "$val" 2>/dev/null || true
  done < "$file"
  unset PROFILE_LOADING
  log_ok "Profile loaded: ${name}"
}

profile_list() {
  mkdir -p "$PROFILE_DIR" 2>/dev/null || true
  local files=("$PROFILE_DIR"/*.conf)
  if [ ${#files[@]} -eq 0 ] || [ ! -f "${files[0]}" ]; then
    echo "(no profiles)"
    return
  fi
  for f in "${files[@]}"; do
    local name
    name=$(basename "$f" .conf)
    echo "$name"
  done
}

profile_delete() {
  local name="$1"
  if [ -z "$name" ] || ! [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    log_e "Ten profile khong hop le: '${name:-<empty>}'"
    return 1
  fi
  local file="$PROFILE_DIR/${name}.conf"
  [ ! -f "$file" ] && { log_e "Profile khong ton tai: ${name}"; return 1; }
  rm "$file" && log_ok "Profile deleted: ${name}"
}

# ============================================================================
# API — JSON output cho web dashboard
# ============================================================================

api_status() {
  local temp freq load eco super grace
  temp=$(for z in /sys/class/thermal/thermal_zone*; do t=$(cat "$z/type" 2>/dev/null); case "$t" in x86_pkg_temp|coretemp|acpitz) cat "$z/temp" 2>/dev/null; break;; esac; done | awk '{printf "%.0f", $1/1000}' || echo "?")
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
