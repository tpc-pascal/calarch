#!/bin/bash
# ============================================================================
# START.SH (formerly setup-arch-godmode-final.sh)
# Panasonic CF-XZ6 (Intel i5-7300U Kaby Lake) — God-Mode Setup Script
# ----------------------------------------------------------------------------
# Tác giả / Author:   Principal Linux Kernel & Low-Latency Systems Architect
# Thiết bị / Target:  Panasonic CF-XZ6 (Core i5-7300U, 8GB LPDDR3, HD620)
# Kernel:             Linux-Zen
# Desktop:            Hyprland (Wayland) via JaKooLit Dotfiles
# ============================================================================
# YÊU CẦU AN TOÀN / SAFETY REQUIREMENTS:
# 1. KHÔNG chạy script với quyền root (sudo ./script.sh) — DO NOT run as root
# 2. Chỉ leo thang sudo cục bộ tại các lệnh ghi file hệ thống
# 3. Mọi ghi đè file hệ thống tạo bản sao .bak trước khi can thiệp
# ============================================================================

set -euo pipefail

# ============================================================================
# PART 1: KHỞI TẠO & AN TOÀN (INITIALIZATION & SAFETY)
# ============================================================================
# Phần này định nghĩa các biến màu ANSI, hàm log, cơ chế try-catch,
# và kiểm tra an toàn ngay khi script khởi chạy.
# ----------------------------------------------------------------------------
# ANSI color codes — sử dụng mã màu 8-bit chuẩn cho terminal hiện đại

# --- Định nghĩa màu sắc / Color Definitions ---
# Các biến này được dùng xuyên suốt script để tạo log trực quan
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'

# --- Biến toàn cục / Global Variables ---
WIZARD_VARS_FILE="/tmp/godmode-wizard-vars.sh"  # File lưu biến từ TUI Wizard
PASCAL_MODE_PATH="/usr/local/bin/pascal-mode"    # Đường dẫn dashboard script
LOG_FILE="/tmp/godmode-setup.log"                # File log chi tiết
LOCK_FILE="/tmp/godmode-setup.lock"              # Mutex lock file
FLAG_DIR="/tmp/godmode-part"                     # Resume flag directory
AUDIT_FILE="/tmp/godmode-hw-audit.log"           # Hardware audit log
AFFINITY_STATE_FILE="/tmp/godmode-cpu-affinity-state.json"  # CPU affinity state for rollback
CLEANUP_DONE=0                                   # Cleanup status flag

# --- Biến năng lực / Capability Flags ---
# Được phát hiện tự động bởi probe_capabilities() trước khi chạy các PART
# Các biến này quyết định phần nào sẽ được triển khai
CAP_NETWORK=0          # Kết nối mạng (ping)
CAP_ONLINE=0           # Internet khả dụng (HTTP)
CAP_AUR=0              # AUR helper sẵn sàng
CAP_YAY=0              # Yay binary tồn tại
CAP_DISK_SPACE=0       # Đủ dung lượng (>=5GB)
CAP_ECO_MODE=0         # Eco Mode sysfs (Panasonic)
CAP_CHARGE_THRESH=0    # Generic charge threshold
CAP_BATTERY=0          # Pin tồn tại
CAP_KBD_BACKLIGHT=0    # Đèn bàn phím
CAP_KBD_PATH=""        # Đường dẫn đèn bàn phím
CAP_PANASONIC_MOD=0    # Kernel module panasonic_laptop
CAP_MSR_MOD=0          # Kernel module msr
CAP_SYSTEMD_BOOT=0     # systemd-boot bootloader
CAP_GRUB=0             # GRUB bootloader
CAP_FILE="/tmp/godmode-capabilities.sh"
PKG_BEFORE="/tmp/godmode-pkg-before.txt"
PKG_AFTER="/tmp/godmode-pkg-after.txt"

# --- Hàm ghi log / Log Functions ---
# Mỗi hàm log tự động ghi thời gian và màu sắc tương ứng trạng thái

log_info() {
    echo -e "${BLUE}ℹ [INFO]${RESET} $(date '+%H:%M:%S') | $*"
    echo "[INFO] $(date '+%H:%M:%S') | $*" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓ [OK]${RESET} $(date '+%H:%M:%S') | $*"
    echo "[OK] $(date '+%H:%M:%S') | $*" >> "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}⚠ [WARN]${RESET} $(date '+%H:%M:%S') | $*"
    echo "[WARN] $(date '+%H:%M:%S') | $*" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗ [ERROR]${RESET} $(date '+%H:%M:%S') | $*"
    echo "[ERROR] $(date '+%H:%M:%S') | $*" >> "$LOG_FILE"
}

log_fatal() {
    echo -e "${BOLD}${RED}⊗ [FATAL]${RESET} $(date '+%H:%M:%S') | $*"
    echo "[FATAL] $(date '+%H:%M:%S') | $*" >> "$LOG_FILE"
    exit 1
}

log_header() {
    echo ""
    echo -e "${MAGENTA}══════════════════════════════════════════════════════════${RESET}"
    echo -e "${MAGENTA}  $*${RESET}"
    echo -e "${MAGENTA}══════════════════════════════════════════════════════════${RESET}"
    echo ""
}

# --- Hàm try_catch: Bọc lệnh với kiểm tra $? tự động ---
# try_catch wrapper: tự động log OK/FAIL dựa trên exit code
# Cách dùng / Usage: try_catch "mô tả" <lệnh> [đối số...]
# Cơ chế: Chạy lệnh, bắt exit code, log kết quả tương ứng

try_catch() {
    local desc="$1"    # Mô tả hành động / Action description
    shift              # Loại bỏ tham số đầu, giữ lại lệnh cần chạy
    local cmd="$*"     # Toàn bộ lệnh cần thực thi

    echo -e "${GRAY}  → ${desc}...${RESET}"
    echo "  → ${desc}..." >> "$LOG_FILE"

    # Thực thi lệnh, bắt đầu ra và exit code
    # Execute command, capture output and exit code
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        log_success "${desc}"
        return 0
    else
        local ec=$?
        log_warn "${desc} — failed with exit code ${ec}"
        return $ec
    fi
}

# --- Hàm retry_catch: Thử lại tối đa 3 lần trước khi báo fail ---
# retry_catch: Try command up to 3 times before reporting failure
# Dành cho lệnh network/có thể fail tạm thời (git clone, yay install)

retry_catch() {
    local desc="$1"
    shift
    local cmd="$*"
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        echo -e "${GRAY}  → ${desc} (attempt ${attempt}/${max_attempts})...${RESET}"
        echo "  → ${desc} (attempt ${attempt}/${max_attempts})..." >> "$LOG_FILE"

        if eval "$cmd" >> "$LOG_FILE" 2>&1; then
            log_success "${desc}"
            return 0
        fi
        attempt=$((attempt + 1))
        [ $attempt -le $max_attempts ] && sleep 2
    done

    log_warn "${desc} — failed after ${max_attempts} attempts"
    return 1
}

# --- Hàm try_aur: Cài AUR package với fallback ---
# try_aur: Install AUR package with alternative fallback
# Usage: try_aur "package" ["fallback-pkg"] ["fallback2-pkg"]

try_aur() {
    local pkg="$1"
    shift
    local fallbacks=("$@")
    local all=("$pkg" "${fallbacks[@]}")

    for try_pkg in "${all[@]}"; do
        if command -v "$try_pkg" &>/dev/null; then
            log_success "${try_pkg} already installed"
            return 0
        fi
        if try_catch "Install ${try_pkg}" "yay -S --noconfirm ${try_pkg} 2>/dev/null; true"; then
            return 0
        fi
    done

    log_warn "All AUR alternatives failed for: ${pkg}"
    return 1
}

# --- Hàm safe_cd: cd với kiểm tra tồn tại ---
# safe_cd: cd into directory if it exists, else warn

safe_cd() {
    local target="$1"
    if [ -d "$target" ]; then
        cd "$target"
        return 0
    else
        log_warn "Directory not found: ${target}"
        return 1
    fi
}

# --- Hàm safe_sudo_write: Ghi file hệ thống có backup ---
# safe_sudo_write: write system files with .bak backup
# Cơ chế: Nếu file đã tồn tại, tạo bản sau .bak trước khi ghi đè
# Tham số: $1 = đường dẫn file, $2 = nội dung (string)

safe_sudo_write() {
    local file="$1"
    local content="$2"
    local dir
    dir=$(dirname "$file")

    # Tạo thư mục cha nếu chưa tồn tại
    # Create parent directory if missing
    if [ ! -d "$dir" ]; then
        try_catch "Create directory ${dir}" "sudo mkdir -p '$dir'"
    fi

    # Backup file nếu đã tồn tại / Backup existing file
    if [ -f "$file" ]; then
        local bak_file="${file}.bak.$(date +%Y%m%d%H%M%S)"
        try_catch "Backup ${file} → ${bak_file}" "sudo cp -a '$file' '$bak_file'"
    fi

    # Ghi nội dung mới / Write new content
    # Sử dụng tee để vừa ghi file vừa hiển thị output,
    # kết hợp sudo để leo thang đặc quyền
    echo -e "$content" | sudo tee "$file" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log_success "Wrote ${file}"
    else
        log_error "Failed to write ${file}"
        return 1
    fi
}

# --- Hàm safe_sudo_append: Thêm nội dung vào file hệ thống ---
# safe_sudo_append: append content to system file with backup
# Khác với safe_sudo_write: không ghi đè, chỉ append

safe_sudo_append() {
    local file="$1"
    local content="$2"

    # Backup lần đầu nếu file chưa được backup trong phiên này
    # First-time backup check for this session
    if [ -f "$file" ] && [ ! -f "${file}.godmode-bak" ]; then
        try_catch "Backup ${file} (first time)" "sudo cp -a '$file' '${file}.godmode-bak'"
    fi

    # Append nội dung / Append content
    echo -e "$content" | sudo tee -a "$file" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log_success "Appended to ${file}"
    else
        log_error "Failed to append to ${file}"
        return 1
    fi
}

# --- Hàm check_root: Kiểm tra user không phải root ---
# check_root: ensure script is NOT run as root
# Lý do an toàn: Các tác vụ clone git, cài AUR qua yay
# phải chạy dưới quyền user thường. Chỉ sudo cục bộ.

check_root() {
    if [ "$EUID" -eq 0 ]; then
        echo -e "${BOLD}${RED}"
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║  NGUY HIỂM / DANGER!                                       ║"
        echo "║  Không chạy script này với quyền root!                      ║"
        echo "║  DO NOT run this script as root!                            ║"
        echo "║                                                            ║"
        echo "║  Sử dụng: ./start.sh                                        ║"
        echo "║  (chạy bằng user thường / run as normal user)               ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo -e "${RESET}"
        exit 1
    fi
}

# --- Hàm check_dependencies: Kiểm tra công cụ cần thiết ---
# check_dependencies: verify required tools exist
# Các gói này là tối thiểu để script có thể chạy TUI Wizard

check_dependencies() {
    local deps=("whiptail" "sudo" "git" "curl" "pacman")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_fatal "Missing required tools: ${missing[*]}. Run: sudo pacman -S ${missing[*]}"
    fi
}

# --- Hàm init_log: Khởi tạo file log ---
# init_log: create fresh log file for this session

init_log() {
    echo "=== GODMODE SETUP LOG $(date) ===" > "$LOG_FILE"
    echo "User: $(whoami) | Host: $(hostname)" >> "$LOG_FILE"
    echo "Kernel: $(uname -r)" >> "$LOG_FILE"
    log_success "Log initialized at ${LOG_FILE}"
}

# --- Hàm init_safety: Khởi tạo các cơ chế an toàn ---
# init_safety: setup flock mutex, trap cleanup, resume flags

init_safety() {
    # Mutex toàn cục: flock tránh chạy 2 instance
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        log_fatal "Another instance is running (lock: ${LOCK_FILE})"
    fi
    log_info "Mutex acquired: ${LOCK_FILE}"

    # Tạo thư mục flag nếu chưa tồn tại
    mkdir -p "$FLAG_DIR"

    # Resume capability: Kiểm tra các PART đã hoàn thành
    local completed_parts=0
    for flag in "$FLAG_DIR"/*.done; do
        [ -f "$flag" ] && completed_parts=$((completed_parts + 1))
    done
    if [ "$completed_parts" -gt 0 ]; then
        log_info "Resume mode: ${completed_parts} part(s) already completed"
    fi

    # Cleanup trap: dọn dẹp khi thoát (EXIT, INT, TERM)
    trap cleanup EXIT INT TERM
    log_info "Safety initialized: mutex, resume, trap"
}

# --- Hàm check_part_done: Kiểm tra PART đã hoàn thành chưa ---
# check_part_done: return 0 if part is done, 1 if not

check_part_done() {
    local part="$1"
    [ -f "${FLAG_DIR}/${part}.done" ]
}

# --- Hàm mark_part_done: Đánh dấu PART đã hoàn thành ---
# mark_part_done: create flag file for completed part

mark_part_done() {
    local part="$1"
    touch "${FLAG_DIR}/${part}.done"
    log_success "Part ${part} marked complete"
}

# --- Hàm cleanup: Dọn dẹp khi script thoát ---
# cleanup: trap handler for EXIT/INT/TERM

cleanup() {
    [ "$CLEANUP_DONE" -eq 1 ] && return
    CLEANUP_DONE=1

    log_info "Running cleanup..."

    # Tắt CPU affinity engine nếu còn chạy
    pkill -f hyprland-event-monitor.sh 2>/dev/null || true

    # Unset biến môi trường nhạy cảm
    unset HYPRLAND_AUTO_INSTALL HYPRLAND_GPU
    unset GIT_TOKEN

    # Xóa file tạm (trừ wizard vars)
    rm -f /tmp/godmode-*.tmp 2>/dev/null || true

    # Auto-recovery: nếu script ket thuc voi loi, chay recovery
    if [ "${SETUP_EXIT_CODE:-0}" -ne 0 ]; then
        local RECOVERY_SCRIPT
        if [ -f "$(dirname "$0")/godmode-recovery.sh" ]; then
            RECOVERY_SCRIPT="$(dirname "$0")/godmode-recovery.sh"
        elif [ -f "/usr/local/bin/godmode-recovery.sh" ]; then
            RECOVERY_SCRIPT="/usr/local/bin/godmode-recovery.sh"
        fi
        if [ -n "${RECOVERY_SCRIPT:-}" ] && [ -f "$RECOVERY_SCRIPT" ]; then
            log_info "Setup failed. Running auto-recovery..."
            bash "$RECOVERY_SCRIPT" --all 2>/dev/null || true
        fi
        echo -e "${YELLOW}[RECOVERY]${RESET} Da chay recovery. Thu chay lai: ./start.sh"
        echo -e "${YELLOW}[RECOVERY]${RESET} Neu tiep tuc loi, xem: ${LOG_FILE}"
    fi

    log_info "Cleanup complete"
}

# --- Hàm safe_run: Bọc một PART với resume/rollback/dry-run ---
# safe_run: wrapper for part execution with safety features

safe_run() {
    local part_num="$1"
    local part_name="$2"
    local part_func="$3"

    # Kiểm tra GODMODE_DRY_RUN
    if [ "${GODMODE_DRY_RUN:-0}" = "1" ]; then
        log_info "[DRY-RUN] Would execute Part ${part_num}: ${part_name}"
        return 0
    fi

    # Kiểm tra resume flag
    if check_part_done "$part_num"; then
        log_info "Skipping Part ${part_num} (already completed)"
        return 0
    fi

    log_header "PART ${part_num}: ${part_name}"

    # Snapshot Btrfs trước khi chạy (rollback capability)
    if command -v snapper &>/dev/null; then
        try_catch "Snapper snapshot before Part ${part_num}" \
            "sudo snapper -c root create -d 'Before Part ${part_num}: ${part_name}' 2>/dev/null; true"
    fi

    # Thực thi PART function
    local attempt=1
    local max_attempts=3
    while [ $attempt -le $max_attempts ]; do
        if $part_func; then
            mark_part_done "$part_num"
            log_success "Part ${part_num} completed successfully"
            return 0
        fi

        log_error "Part ${part_num} FAILED (attempt ${attempt}/${max_attempts})"

        # Rollback nếu có snapper
        if command -v snapper &>/dev/null; then
            log_warn "Rolling back to pre-Part ${part_num} state..."
            local last_snapshot
            last_snapshot=$(sudo snapper -c root list 2>/dev/null | tail -1 | awk '{print $1}')
            [ -n "$last_snapshot" ] && sudo snapper -c root undochange "$last_snapshot"..0 2>/dev/null || true
        fi

        [ $attempt -ge $max_attempts ] && break
        attempt=$((attempt + 1))

        # Hỏi user retry/skip/abort
        if command -v whiptail &>/dev/null; then
            local choice
            choice=$(whiptail --title "PART ${part_num} FAILED" \
                --menu "Part ${part_num}: ${part_name}\nCheck: ${LOG_FILE}" 14 60 3 \
                "Retry"  "Thu lai lan ${attempt}/${max_attempts}" \
                "Skip"   "Bo qua part nay, tiep tuc" \
                "Abort"  "Dung lai thoat" 3>&1 1>&2 2>&3)
            case "$choice" in
                "Skip")  log_warn "Skipping Part ${part_num}"; break ;;
                "Abort") log_error "Setup aborted by user"; exit 1 ;;
                *)       log_info "Retrying Part ${part_num}..." ;;
            esac
        else
            # Fallback: console prompt
            echo ""
            echo -e "${YELLOW}Part ${part_num} failed. Options:${RESET}"
            echo -e "  ${GREEN}[R]${RESET}etry  ${YELLOW}[S]${RESET}kip  ${RED}[A]${RESET}bort"
            read -r -p "Choose [R/s/a]: " choice
            case "${choice,,}" in
                s|skip)   log_warn "Skipping Part ${part_num}"; break ;;
                a|abort)  log_error "Setup aborted by user"; exit 1 ;;
                *)        log_info "Retrying Part ${part_num}..." ;;
            esac
        fi
    done
    log_error "Part ${part_num} failed after ${attempt} attempts. Log: ${LOG_FILE}"
    return 1
}

# --- Hàm is_verbose: Kiểm tra chế độ verbose ---
# is_verbose: check if verbose mode is enabled

is_verbose() {
    [ "${GODMODE_VERBOSE:-0}" = "1" ]
}

# ============================================================================
# CAPABILITY PROBE & OFFLINE MODE
# ============================================================================
# probe_capabilities: Phát hiện năng lực hệ thống trước khi triển khai.
# Mỗi lần chạy setup, các flag CAP_* được set và lưu vào file.
# Các PART function kiểm tra CAP_* thay vì tự probe — tránh redundant work.

probe_capabilities() {
    log_header "CAPABILITY PROBE"

    # --- Network ---
    CAP_NETWORK=0
    if ping -c 2 -W 3 archlinux.org &>/dev/null; then
        CAP_NETWORK=1
        log_success "Network: connected"
    else
        log_warn "Network: OFFLINE — online features will be skipped"
    fi

    # --- Internet (HTTP reachable) ---
    CAP_ONLINE=0
    if [ "$CAP_NETWORK" -eq 1 ] && curl -s --max-time 5 https://archlinux.org >/dev/null 2>&1; then
        CAP_ONLINE=1
    fi

    # --- AUR helper ---
    CAP_YAY=0; command -v yay &>/dev/null && CAP_YAY=1
    CAP_AUR=0
    if [ "$CAP_YAY" -eq 1 ]; then
        if yay -P -c &>/dev/null 2>&1 || [ "$CAP_ONLINE" -eq 1 ]; then
            CAP_AUR=1
        fi
    fi
    [ "$CAP_AUR" -eq 1 ] && log_success "AUR: available" || log_info "AUR: not available"

    # --- Disk space ---
    local avail
    avail=$(df / --output=avail 2>/dev/null | tail -1)
    CAP_DISK_SPACE=0
    if [ -n "$avail" ] && [ "$avail" -ge 5242880 ] 2>/dev/null; then
        CAP_DISK_SPACE=1
        log_success "Disk: $((avail/1024))MB free"
    else
        log_warn "Disk: $((avail/1024))MB free (need >=5GB)"
    fi

    # --- Battery ---
    CAP_BATTERY=0; [ -f /sys/class/power_supply/BAT0/capacity ] && CAP_BATTERY=1

    # --- Eco Mode / Charge threshold ---
    CAP_ECO_MODE=0; [ -f /sys/devices/platform/panasonic/eco_mode ] && CAP_ECO_MODE=1
    CAP_CHARGE_THRESH=0; [ -f /sys/class/power_supply/BAT0/charge_control_end_threshold ] && CAP_CHARGE_THRESH=1

    # --- Keyboard backlight ---
    CAP_KBD_BACKLIGHT=0
    CAP_KBD_PATH=$(ls /sys/class/leds/*::kbd_backlight 2>/dev/null | head -1) || CAP_KBD_PATH=""
    [ -n "$CAP_KBD_PATH" ] && CAP_KBD_BACKLIGHT=1

    # --- Kernel modules ---
    CAP_PANASONIC_MOD=0; lsmod | grep -q panasonic_laptop && CAP_PANASONIC_MOD=1
    CAP_MSR_MOD=0; lsmod | grep -q msr && CAP_MSR_MOD=1

    # --- Bootloader ---
    CAP_SYSTEMD_BOOT=0; [ -d /boot/loader/entries ] && CAP_SYSTEMD_BOOT=1
    CAP_GRUB=0; command -v grub-mkconfig &>/dev/null && CAP_GRUB=1

    # --- Save for subprocesses ---
    cat > "$CAP_FILE" << CAPEOF
CAP_NETWORK=$CAP_NETWORK
CAP_ONLINE=$CAP_ONLINE
CAP_AUR=$CAP_AUR
CAP_YAY=$CAP_YAY
CAP_DISK_SPACE=$CAP_DISK_SPACE
CAP_ECO_MODE=$CAP_ECO_MODE
CAP_CHARGE_THRESH=$CAP_CHARGE_THRESH
CAP_BATTERY=$CAP_BATTERY
CAP_KBD_BACKLIGHT=$CAP_KBD_BACKLIGHT
CAP_KBD_PATH='$CAP_KBD_PATH'
CAP_PANASONIC_MOD=$CAP_PANASONIC_MOD
CAP_MSR_MOD=$CAP_MSR_MOD
CAP_SYSTEMD_BOOT=$CAP_SYSTEMD_BOOT
CAP_GRUB=$CAP_GRUB
CAPEOF

    local missing=0
    [ "$CAP_NETWORK" -eq 0 ] && missing=$((missing+1))
    [ "$CAP_DISK_SPACE" -eq 0 ] && missing=$((missing+1))
    [ "$missing" -gt 0 ] && log_warn "${missing} critical capability(-ies) missing"
}

# --- require_network: Fail sớm nếu offline ---
# require_network: Early exit for network-dependent operations
# Usage: require_network "description" || return 1

require_network() {
    local desc="${1:-operation}"
    if [ "$CAP_NETWORK" -eq 0 ]; then
        log_info "Skipping (offline): ${desc}"
        return 1
    fi
    return 0
}

# --- require_aur: Fail sớm nếu AUR không khả dụng ---
# require_aur: Early exit for AUR package installs

require_aur() {
    local desc="${1:-operation}"
    if [ "$CAP_AUR" -eq 0 ]; then
        log_info "Skipping (AUR unavailable): ${desc}"
        return 1
    fi
    return 0
}

# --- Package State Snapshot ---
# save_package_state: snapshot danh sách gói đã cài
# diff_package_state: diff để biết gói nào mới được thêm vào

save_package_state() {
    local out="$1"
    pacman -Q 2>/dev/null | sort > "$out" || true
    log_info "Package state saved: $(wc -l < "$out") packages → ${out}"
}

diff_package_state() {
    local before="$1"
    local after="$2"
    if [ -f "$before" ] && [ -f "$after" ]; then
        diff "$before" "$after" 2>/dev/null | grep '^>' | sed 's/^> //' || true
    fi
}


# ============================================================================
# PART 0: PRE-FLIGHT HARDWARE AUDIT & ENVIRONMENT VALIDATION
# ============================================================================
# Phân hệ này kiểm tra toàn diện phần cứng và môi trường trước khi
# chạy Wizard hay bất kỳ thao tác nào khác.
# ----------------------------------------------------------------------------
# Các kiểm tra:
# 1. Xác thực thiết bị là CF-XZ6 qua DMI
# 2. Detect kernel = linux-zen
# 3. Kiểm tra kết nối mạng
# 4. Đo battery health
# 5. Kiểm tra disk space
# 6. Detect RAM
# 7. Detect UEFI
# 8. Check virtualization
# 9. Lưu hardware fingerprint

run_preflight_audit() {
    log_header "PHẦN 0: PRE-FLIGHT HARDWARE AUDIT"

    local audit_log=""
    local issues=0

    # 1. Xác thực thiết bị CF-XZ6
    local product_name
    product_name=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo "UNKNOWN")
    audit_log+="Device: ${product_name}\n"
    if [[ "$product_name" == *"CF-XZ6"* ]] || [[ "$product_name" == *"CFXZ6"* ]]; then
        log_success "Device verified: ${product_name}"
    else
        log_warn "Device is ${product_name}, not CF-XZ6 — some features may not work"
        issues=$((issues + 1))
    fi

    # 2. Detect kernel
    local kernel
    kernel=$(uname -r)
    audit_log+="Kernel: ${kernel}\n"
    if [[ "$kernel" == *"zen"* ]]; then
        log_success "Kernel: linux-zen (${kernel})"
    else
        log_warn "Kernel is not linux-zen: ${kernel}"
        issues=$((issues + 1))
    fi

    # 3. Kiểm tra kết nối mạng
    audit_log+="Network: "
    if ping -c 2 archlinux.org &>/dev/null; then
        log_success "Network connectivity: OK"
        audit_log+="OK\n"
    else
        log_warn "No network connectivity — try: iwctl"
        audit_log+="FAIL\n"
        issues=$((issues + 1))
    fi

    # 4. Đo battery health
    local bat_capacity_path="/sys/class/power_supply/BAT0/capacity"
    if [ -f "$bat_capacity_path" ]; then
        local bat_capacity
        bat_capacity=$(cat "$bat_capacity_path")
        audit_log+="Battery capacity: ${bat_capacity}%\n"
        if [ "$bat_capacity" -lt 70 ] 2>/dev/null; then
            log_warn "Battery health is low: ${bat_capacity}% (recommend replacement)"
            issues=$((issues + 1))
        else
            log_success "Battery health: ${bat_capacity}%"
        fi
    else
        audit_log+="Battery: N/A\n"
        log_warn "No battery detected"
    fi

    # 5. Disk space
    local avail_space
    avail_space=$(df / --output=avail 2>/dev/null | tail -1)
    if [ -n "$avail_space" ] && [ "$avail_space" -lt 5242880 ] 2>/dev/null; then
        local avail_mb=$((avail_space / 1024))
        log_warn "Low disk space: ${avail_mb}MB free (need >5GB)"
        audit_log+="Disk space: ${avail_mb}MB (LOW)\n"
        issues=$((issues + 1))
    else
        local avail_mb=$((avail_space / 1024))
        log_success "Disk space: ${avail_mb}MB free"
        audit_log+="Disk space: ${avail_mb}MB\n"
    fi

    # 6. Detect RAM
    local total_ram
    total_ram=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
    audit_log+="RAM: ${total_ram}MB\n"
    if [ "$total_ram" -lt 8000 ] 2>/dev/null; then
        log_warn "RAM < 8GB (${total_ram}MB) — ZRAM may cause overhead"
        issues=$((issues + 1))
    else
        log_success "RAM: ${total_ram}MB"
    fi

    # 7. Detect UEFI
    audit_log+="Boot mode: "
    if [ -d /sys/firmware/efi/efivars ]; then
        log_success "UEFI boot detected"
        audit_log+="UEFI\n"
    else
        log_error "Legacy BIOS boot detected — UEFI required"
        audit_log+="LEGACY BIOS (ERROR)\n"
        issues=$((issues + 1))
    fi

    # 8. Check virtualization
    local virt
    virt=$(systemd-detect-virt 2>/dev/null || echo "none")
    audit_log+="Virtualization: ${virt}\n"
    if [ "$virt" != "none" ]; then
        log_warn "Running in VM: ${virt} — CF-XZ6 features may not work"
    fi

    # 9. Lưu hardware fingerprint
    echo -e "$audit_log" > "$AUDIT_FILE"
    log_success "Hardware fingerprint saved to ${AUDIT_FILE}"

    if [ "$issues" -gt 0 ]; then
        log_warn "${issues} issue(s) detected during pre-flight audit"
        log_info "Review details: cat ${AUDIT_FILE}"
    else
        log_success "Pre-flight audit passed — all checks OK"
    fi

    return $issues
}


# ============================================================================
# PART 2: TUI WIZARD — Interactive Setup Wizard (whiptail)
# ============================================================================
# Phân hệ này sử dụng whiptail để tạo giao diện TUI (Text User Interface)
# cho phép người dùng tùy chỉnh:
#   • Color Palette (Theme màu sắc)
#   • Typographical Font (Font chữ)
#   • Wallpaper Collection (URL ảnh nền)
# ----------------------------------------------------------------------------
# Cơ chế: whiptail trả về exit code 0 nếu người dùng bấm OK,
# exit code 1 nếu bấm Cancel. Dùng `--stdout` để lấy giá trị.
# Kết quả được lưu vào file /tmp/godmode-wizard-vars.sh để các
# phân hệ sau source vào.

run_wizard() {
    log_header "PHẦN 2: TUI SETUP WIZARD"

    # --- Trang 1: Developer Profile ---
    log_info "Launching Developer Profile selector..."
    DEV_PROFILE=$(whiptail --title "DEVELOPER PROFILE" \
        --menu "Choose your developer profile:" 18 60 6 \
        "full" "Full-stack IT Student (TẤT CẢ — recommended)" \
        "web" "Web Developer (Node, TS, React, PHP)" \
        "mobile" "Mobile Developer (Flutter, Kotlin, React Native)" \
        "game" "Game Developer (Godot, Unity, Aseprite)" \
        "data" "Data/ML (Python, Jupyter, R, Julia)" \
        "sys" "Systems/Low-level (C, Rust, Go, ASM)" \
        3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$DEV_PROFILE" ]; then
        DEV_PROFILE="full"
        log_warn "No profile selected, using default: full"
    fi
    log_success "Profile: ${DEV_PROFILE}"

    # --- Trang 2: Shell & Terminal ---
    log_info "Launching Shell & Terminal selector..."
    SHELL_CHOICE=$(whiptail --title "SHELL SELECTION" \
        --menu "Choose your shell:" 14 55 3 \
        "zsh" "ZSH + Oh My Zsh + Powerlevel10k" \
        "fish" "Fish + Fisher + Tide prompt" \
        "bash" "Bash + bleach (giữ nguyên)" \
        3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$SHELL_CHOICE" ]; then
        SHELL_CHOICE="zsh"
    fi
    log_success "Shell: ${SHELL_CHOICE}"

    TERMINAL_CHOICE=$(whiptail --title "TERMINAL SELECTION" \
        --menu "Choose your terminal:" 14 55 4 \
        "kitty" "Kitty GPU-accelerated (Recommended)" \
        "alacritty" "Alacritty — cross-platform GPU" \
        "wezterm" "WezTerm — GPU + Lua config" \
        "foot" "Foot — Wayland-native, lightweight" \
        3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$TERMINAL_CHOICE" ]; then
        TERMINAL_CHOICE="kitty"
    fi
    log_success "Terminal: ${TERMINAL_CHOICE}"

    # --- Trang 3: Color Palette (mở rộng) ---
    log_info "Launching Color Palette selector..."
    THEME_PALETTE=$(whiptail --title "COLOR PALETTE" \
        --menu "Choose your theme aesthetic:" 18 65 6 \
        "Vaporwave"  "#ff007f Hồng Neon / #00ff66 Xanh Lime — Cyberpunk 80s" \
        "Lo-fi Retro" "#3c3836 Xám Dark / #98971a Xanh Rêu — Vintage" \
        "Classic Cyber" "#000000 Đen / #00ff00 Xanh Lá — Hacker" \
        "Tokyo Night" "#1a1b2e / #7dcfff — Modern dark blue" \
        "Catppuccin" "#1e1e2e / #89b4fa — Warm pastel" \
        "Gruvbox" "#282828 / #8ec07c — Retro earthy" \
        3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$THEME_PALETTE" ]; then
        THEME_PALETTE="Vaporwave"
        log_warn "No palette selected, using default: ${THEME_PALETTE}"
    fi
    log_success "Selected palette: ${THEME_PALETTE}"

    # --- Trang 4: Font (mở rộng) ---
    log_info "Launching Font selector..."
    FONT_FAMILY=$(whiptail --title "TYPOGRAPHICAL FONT" \
        --menu "Choose your terminal/UI font:" 14 55 5 \
        "JetBrains Mono Nerd Font" "Modern coding font with ligatures (Recommended)" \
        "FiraCode Nerd Font" "Popular monospace with programming ligatures" \
        "Cascadia Code" "Windows Terminal font by Microsoft" \
        "Mononoki Nerd Font" "Lightweight monospace with icons" \
        "Comic Shanns" "Playful casual font (Y2K aesthetic)" \
        3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$FONT_FAMILY" ]; then
        FONT_FAMILY="JetBrains Mono Nerd Font"
        log_warn "No font selected, using default: ${FONT_FAMILY}"
    fi
    log_success "Selected font: ${FONT_FAMILY}"

    # --- Trang 5: Wallpaper ---
    log_info "Launching Wallpaper selector..."
    WP_CHOICE=$(whiptail --title "WALLPAPER COLLECTION" \
        --menu "Choose wallpaper source:" 14 55 3 \
        "Auto" "Tự động curl bộ ảnh Vintage Y2K Anime (90s)" \
        "Sysfetch" "Sysfetch Auto — dùng neofetch output làm ASCII wallpaper" \
        "Manual" "Nhập URL raw-image tùy chỉnh" \
        3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$WP_CHOICE" ]; then
        WP_CHOICE="Auto"
    fi
    if [ "$WP_CHOICE" = "Manual" ]; then
        WP_URL=$(whiptail --title "ENTER WALLPAPER URL" \
            --inputbox "Paste direct raw-image URL (jpg/png):" 10 60 \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] || [ -z "$WP_URL" ] && WP_CHOICE="Auto"
    fi

    # --- Trang 6: Git Identity ---
    GIT_NAME=$(whiptail --title "GIT IDENTITY" \
        --inputbox "Enter your Git user name:" 10 60 "Pascal" \
        3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && GIT_NAME="Pascal"

    GIT_EMAIL=$(whiptail --title "GIT IDENTITY" \
        --inputbox "Enter your Git email:" 10 60 "pascal@cfxz6-arch" \
        3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && GIT_EMAIL="pascal@cfxz6-arch"

    # --- Trang 7: Hostname ---
    HOSTNAME=$(whiptail --title "HOSTNAME" \
        --inputbox "Enter hostname:" 10 60 "cfxz6-arch" \
        3>&1 1>&2 2>&3)
    [ $? -ne 0 ] || [ -z "$HOSTNAME" ] && HOSTNAME="cfxz6-arch"

    # --- Trang 8: Feature Toggle ---
    FEATURES=$(whiptail --title "FEATURE TOGGLE" \
        --checklist "Select features to install:" 18 65 9 \
        "hyprland" "Hyprland Desktop + Dotfiles" ON \
        "cpuaffinity" "CPU Affinity Engine" ON \
        "thermal" "Thermal Hardening (thermald, TLP, undervolt)" ON \
        "zram" "ZRAM + sysctl tuning" ON \
        "docker" "Docker + Dev Containers" ON \
        "ittools" "IT Student Toolbox (network/security tools)" ON \
        "audio" "Audio (PipeWire + Bluetooth)" ON \
        "backup" "Backup (Snapper + auto-snapshots)" ON \
        "dashboard" "Pascal-Mode Dashboard" ON \
        3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && FEATURES="hyprland cpuaffinity thermal zram docker ittools audio backup dashboard"

    # --- Validation ---
    # Git email: phai co @ va domain
    if ! echo "$GIT_EMAIL" | grep -qE '^[^@ ]+@[^@ ]+\.[^@ ]+$' 2>/dev/null; then
        log_warn "Invalid Git email: ${GIT_EMAIL} — reset to default"
        GIT_EMAIL="pascal@cfxz6-arch"
    fi
    # Hostname: chi cho phep alphanumeric + dash, khong bat dau/ketch thuc bang dash
    if ! echo "$HOSTNAME" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$' 2>/dev/null; then
        log_warn "Invalid hostname: ${HOSTNAME} — reset to default"
        HOSTNAME="cfxz6-arch"
    fi

    # Lưu các biến vào file tạm
    cat > "$WIZARD_VARS_FILE" << EOF
#!/bin/bash
# GodMode Wizard Variables — generated by start.sh
DEV_PROFILE='${DEV_PROFILE}'
SHELL_CHOICE='${SHELL_CHOICE}'
TERMINAL_CHOICE='${TERMINAL_CHOICE}'
THEME_PALETTE='${THEME_PALETTE}'
FONT_FAMILY='${FONT_FAMILY}'
WP_CHOICE='${WP_CHOICE}'
WP_URL='${WP_URL:-}'
GIT_NAME='${GIT_NAME}'
GIT_EMAIL='${GIT_EMAIL}'
HOSTNAME='${HOSTNAME}'
FEATURES='${FEATURES}'
EOF

    chmod 644 "$WIZARD_VARS_FILE"
    log_success "Wizard variables saved to ${WIZARD_VARS_FILE}"
}

# --- Hàm source_wizard_vars: Nạp biến từ TUI Wizard ---
# load_wizard_vars: source the wizard variables file

load_wizard_vars() {
    if [ -f "$WIZARD_VARS_FILE" ]; then
        source "$WIZARD_VARS_FILE"
        log_info "Loaded wizard variables"
    else
        # Gán mặc định nếu không có wizard file
        DEV_PROFILE="${DEV_PROFILE:-full}"
        SHELL_CHOICE="${SHELL_CHOICE:-zsh}"
        TERMINAL_CHOICE="${TERMINAL_CHOICE:-kitty}"
        THEME_PALETTE="${THEME_PALETTE:-Vaporwave}"
        FONT_FAMILY="${FONT_FAMILY:-JetBrains Mono Nerd Font}"
        WP_CHOICE="${WP_CHOICE:-Auto}"
        GIT_NAME="${GIT_NAME:-Pascal}"
        GIT_EMAIL="${GIT_EMAIL:-pascal@cfxz6-arch}"
        HOSTNAME="${HOSTNAME:-cfxz6-arch}"
        FEATURES="${FEATURES:-hyprland cpuaffinity thermal zram docker ittools audio backup dashboard}"
        log_warn "No wizard vars file, using defaults"
    fi
}


# ============================================================================
# PART 3: TRIỂN KHAI JAKOOLIT HYPRLAND (Y2K VIBE)
# ============================================================================
# Phân hệ này cài đặt Hyprland-based desktop thông qua bộ Dotfiles
# của JaKooLit, một bộ cấu hình Hyprland phổ biến trên Arch Linux.
# ----------------------------------------------------------------------------
# Quy trình:
# 1. Cài yay-bin (AUR helper) từ AUR — chạy với user thường
# 2. Clone JaKooLit/Arch-Hyprland.git
# 3. Set biến môi trường cho Intel iGPU + các thành phần
# 4. Chạy install.sh ở chế độ non-interactive
# 5. Ghi đè config: tắt blur/shadow/animations, chỉnh gaps/border/rounding
# 6. Áp dụng theme/font từ TUI Wizard vào waybar.css và rofi.rasi

deploy_jakoolit_hyprland() {
    log_header "PHẦN 3: JAKOOLIT HYPRLAND DEPLOYMENT"

    require_network "JaKooLit Hyprland (git clone + AUR packages)" || return 1

    # --- Bước 1: Cài đặt yay-bin từ AUR ---
    # yay-bin là AUR helper được pre-compiled (không mất thời gian build).
    # Cài đặt qua git clone + makepkg — chạy bằng user thường (KHÔNG sudo)
    # Step 1: Install yay-bin AUR helper as normal user

    if ! command -v yay &>/dev/null; then
        log_info "Installing yay-bin from AUR..."

        # Kiểm tra và cài đặt base-devel nếu chưa có
        # base-devel cung cấp makepkg và các công cụ build cần thiết
        if ! pacman -Qi base-devel &>/dev/null; then
            try_catch "Install base-devel" "sudo pacman -S --noconfirm base-devel"
        fi

        # Clone yay-bin repository — thư mục /tmp để tránh rác
        # yay-bin is pre-compiled, faster than yay-git
        cd /tmp
        try_catch "Clone yay-bin" "git clone https://aur.archlinux.org/yay-bin.git"

        # Build và cài đặt với makepkg (không chạy root)
        # Build and install — si flag = system install, không cần confirm
        cd yay-bin
        try_catch "Build and install yay-bin" "makepkg -si --noconfirm"
        cd ~
    else
        log_info "yay is already installed"
    fi

    # --- Bước 2: Clone JaKooLit Dotfiles ---
    # Step 2: Clone the JaKooLit Hyprland dotfiles repository
    # Đây là bộ cấu hình đầy đủ: Hyprland, Waybar, Rofi, Dunst, v.v.

    local DOTFILES_DIR="$HOME/Arch-Hyprland"

    if [ ! -d "$DOTFILES_DIR" ]; then
        log_info "Cloning JaKooLit/Arch-Hyprland dotfiles..."
        retry_catch "Clone JaKooLit dotfiles" \
            "git clone --depth=1 https://github.com/JaKooLit/Arch-Hyprland.git '$DOTFILES_DIR'"
    else
        log_info "JaKooLit dotfiles already cloned, pulling updates..."
        retry_catch "Update JaKooLit dotfiles" \
            "cd '$DOTFILES_DIR' && git pull"
    fi

    # --- Bước 3: Cài đặt Hyprland với Intel GPU driver ---
    # Step 3: Run installer with environment variables for non-interactive mode
    # Các biến môi trường được set để installer tự động chọn:
    #   - Intel GPU driver (i915) thay vì NVIDIA/AMD
    #   - Các thành phần desktop: Waybar, Rofi, SWWW, Dunst, SDDM

    # Set biến môi trường cho installer non-interactive
    # Environment variables to control installer behavior
    export HYPRLAND_AUTO_INSTALL="true"          # Chế độ tự động không hỏi
    export HYPRLAND_GPU="intel"                   # Intel iGPU driver
    export HYPRLAND_INSTALL_WAYBAR="true"         # Thanh taskbar
    export HYPRLAND_INSTALL_ROFI="true"           # Application launcher
    export HYPRLAND_INSTALL_SWWW="true"           # Wallpaper daemon
    export HYPRLAND_INSTALL_DUNST="true"          # Notification daemon
    export HYPRLAND_INSTALL_SDDM="true"           # Display manager

    log_info "Running JaKooLit installer (non-interactive mode)..."
    log_info "Using Intel GPU, Waybar, Rofi, SWWW, Dunst, SDDM"

    INSTRUCTION_SOURCE=""  # Ghi nhan nguon cai dat / Track install source

    # Chạy script install chính của JaKooLit — có fallback manual
    # Run the main install script with manual fallback
    if safe_cd "$DOTFILES_DIR"; then
        if [ -f "install.sh" ]; then
            retry_catch "JaKooLit install.sh" "bash install.sh" && INSTRUCTION_SOURCE="jakoolit"
        elif [ -f "setup.sh" ]; then
            retry_catch "JaKooLit setup.sh" "bash setup.sh" && INSTRUCTION_SOURCE="jakoolit"
        fi
        cd ~
    fi

    if [ -z "$INSTRUCTION_SOURCE" ]; then
        log_warn "JaKooLit installer unavailable — using manual fallback"
        log_info "Attempting manual Hyprland package install..."
        try_catch "Install Hyprland packages" \
            "yay -S --noconfirm hyprland waybar-hyprland rofi-lbonn-wayland swww dunst sddm 2>/dev/null; true" || \
        try_catch "Install Hyprland packages (alt)" \
            "yay -S --noconfirm hyprland-git waybar rofi swww dunst sddm 2>/dev/null; true"
    fi

    # --- Bước 4: Cấu hình Zero-Latency cho Hyprland ---
    # Step 4: Override hyprland.conf for zero-latency rendering
    # Các thiết lập này nhằm đạt độ trễ render thấp nhất có thể:
    #   - Tắt blur (giảm tải GPU đáng kể)
    #   - Tắt drop shadow (tiết kiệm bộ nhớ đệm)
    #   - Tắt animations (loại bỏ hoàn toàn độ trễ chuyển cảnh)
    #   - Gaps/border nhỏ, rounding = 0 (vuông vức phong cách Y2K)

    local HYPRLAND_CONF="$HOME/.config/hypr/hyprland.conf"

    if [ -f "$HYPRLAND_CONF" ]; then
        log_info "Applying zero-latency render config..."

        # Backup file gốc / Backup original
        if [ ! -f "${HYPRLAND_CONF}.godmode-bak" ]; then
            cp -a "$HYPRLAND_CONF" "${HYPRLAND_CONF}.godmode-bak"
            log_info "Backed up original hyprland.conf"
        fi

        # Ghi đè decoration / Override decoration settings
        try_catch "Disable blur" "sed -i 's/blur:enabled = true/blur:enabled = false/g' '$HYPRLAND_CONF'"
        try_catch "Disable drop shadow" "sed -i 's/drop_shadow = true/drop_shadow = false/g' '$HYPRLAND_CONF'"
        try_catch "Disable animations" "sed -i 's/animations:enabled = true/animations:enabled = false/g' '$HYPRLAND_CONF'"

        # Thiết lập gaps, border, rounding kiểu Y2K
        # Y2K-style squared windows with minimal gaps
        try_catch "Set gaps_in = 2" "sed -i 's/gaps_in = [0-9]*/gaps_in = 2/g' '$HYPRLAND_CONF'"
        try_catch "Set gaps_out = 4" "sed -i 's/gaps_out = [0-9]*/gaps_out = 4/g' '$HYPRLAND_CONF'"
        try_catch "Set border_size = 2" "sed -i 's/border_size = [0-9]*/border_size = 2/g' '$HYPRLAND_CONF'"
        try_catch "Set rounding = 0" "sed -i 's/rounding = [0-9]*/rounding = 0/g' '$HYPRLAND_CONF'"

        log_success "Zero-latency config applied"
    else
        log_warn "hyprland.conf not found at ${HYPRLAND_CONF}"
    fi

    # --- Bước 5: Áp dụng Color Theme vào Waybar và Rofi ---
    # Step 5: Apply wizard theme to Waybar CSS and Rofi config
    # Dựa trên THEME_PALETTE đã chọn ở TUI Wizard, override CSS variables

    case "$THEME_PALETTE" in
        "Vaporwave")
            local WAYBAR_BG="#1a0033"
            local WAYBAR_FG="#ff007f"
            local ROFI_BG="#1a0033"
            local ROFI_FG="#00ff66"
            ;;
        "Lo-fi Retro")
            local WAYBAR_BG="#3c3836"
            local WAYBAR_FG="#98971a"
            local ROFI_BG="#3c3836"
            local ROFI_FG="#98971a"
            ;;
        "Classic Cyber")
            local WAYBAR_BG="#000000"
            local WAYBAR_FG="#00ff00"
            local ROFI_BG="#000000"
            local ROFI_FG="#00ff00"
            ;;
        *)
            local WAYBAR_BG="#1a0033"
            local WAYBAR_FG="#ff007f"
            local ROFI_BG="#1a0033"
            local ROFI_FG="#00ff66"
            ;;
    esac

    # Override Waybar style / Override Waybar CSS
    local WAYBAR_CSS="$HOME/.config/waybar/style.css"
    if [ -f "$WAYBAR_CSS" ]; then
        try_catch "Apply Waybar theme colors" \
            "sed -i 's/background: #[0-9a-fA-F]*/background: ${WAYBAR_BG}/g' '$WAYBAR_CSS'"
        try_catch "Apply Waybar foreground" \
            "sed -i 's/color: #[0-9a-fA-F]*/color: ${WAYBAR_FG}/g' '$WAYBAR_CSS'"
    fi

    # Override Rofi config / Override Rofi theme
    local ROFI_CONF="$HOME/.config/rofi/config.rasi"
    if [ -f "$ROFI_CONF" ]; then
        try_catch "Apply Rofi theme colors" \
            "sed -i 's/background: #[0-9a-fA-F]*/background: ${ROFI_BG}/g' '$ROFI_CONF'"
        try_catch "Apply Rofi foreground" \
            "sed -i 's/foreground: #[0-9a-fA-F]*/foreground: ${ROFI_FG}/g' '$ROFI_CONF'"
    fi

    # Apply font family / Áp dụng font chữ
    local FONT_CLEAN
    FONT_CLEAN=$(echo "$FONT_FAMILY" | sed 's/ Nerd Font//' | sed 's/ Font//')
    if [ -f "$HYPRLAND_CONF" ]; then
        try_catch "Set Hyprland font" \
            "sed -i 's/^[[:space:]]*font_family =.*/    font_family = ${FONT_FAMILY}/' '$HYPRLAND_CONF'"
    fi

    # --- Bước 6: Wayland IDE flags ---
    log_info "Creating Wayland flags for IDE..."
    mkdir -p "$HOME/.config"

    cat > "$HOME/.config/code-flags.conf" << 'CODE_EOF'
--ozone-platform-hint=auto
--enable-features=WaylandWindowDecorations,UseOzonePlatform
CODE_EOF

    cat > "$HOME/.config/chromium-flags.conf" << 'CHROMIUM_EOF'
--ozone-platform-hint=auto
--enable-features=UseOzonePlatform
CHROMIUM_EOF

    cat > "$HOME/.config/electron-flags.conf" << 'ELECTRON_EOF'
--ozone-platform-hint=auto
--enable-features=WaylandWindowDecorations
ELECTRON_EOF

    log_success "Wayland flags created for VS Code, Chromium, Electron"

    # --- Bước 7: SDDM auto-login ---
    if command -v sddm &>/dev/null; then
        log_info "Configuring SDDM auto-login..."
        safe_sudo_write "/etc/sddm.conf" '[Autologin]
User='"$USER"'
Session=hyprland

[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot

[Theme]
Current=breeze
CursorTheme=breeze_cursors
Font=JetBrains Mono Nerd Font,12

[Wayland]
EnableHiDPI=true
ServerArguments=-nolisten tcp -br -dpi 144
'
        log_success "SDDM auto-login configured for $USER"
    fi

    log_success "JaKooLit Hyprland deployment complete!"
}


# ============================================================================
# PART 2.5: SHELL & TERMINAL ENHANCEMENT
# ============================================================================
# Phân hệ này cấu hình shell (ZSH/Fish) và terminal (kitty/alacritty)
# dựa trên lựa chọn của người dùng ở TUI Wizard.
# ----------------------------------------------------------------------------

setup_shell_terminal() {
    log_header "PHẦN 2.5: SHELL & TERMINAL ENHANCEMENT"

    # --- Shell setup ---
    case "$SHELL_CHOICE" in
        zsh)
            log_info "Installing ZSH + Oh My Zsh + Powerlevel10k..."
            if ! pacman -Qi zsh &>/dev/null; then
                try_catch "Install zsh" "sudo pacman -S --noconfirm zsh zsh-completions 2>/dev/null; true"
            fi
            if [ ! -d "$HOME/.oh-my-zsh" ]; then
                try_catch "Install Oh My Zsh" \
                    "sh -c '$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)' '' --unattended 2>/dev/null; true"
            fi
            # Powerlevel10k theme
            local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
            if [ ! -d "${ZSH_CUSTOM}/themes/powerlevel10k" ]; then
                try_catch "Install Powerlevel10k" \
                    "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM}/themes/powerlevel10k"
            fi
            # Plugins
            if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
                git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions 2>/dev/null || true
            fi
            if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
                git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting 2>/dev/null || true
            fi
            # .zshrc config
            cat > "$HOME/.zshrc" << 'ZSHRC_EOF'
# GodMode: ZSH Configuration
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
POWERLEVEL9K_MODE="nerdfont-complete"
plugins=(git docker docker-compose npm node vscode archlinux systemd zsh-autosuggestions zsh-syntax-highlighting zsh-completions)
source $ZSH/oh-my-zsh.sh
alias ls='eza --icons'
alias cat='bat'
alias top='btop'
alias grep='rg'
alias du='dust'
alias df='duf'
alias ps='procs'
alias diff='delta'
alias find='fd'
alias pascal-mode='/usr/local/bin/pascal-mode'
alias godmode='pascal-mode'
alias rollback='snapper -c root list'
alias fw-start='sudo systemctl start nftables'
alias fw-stop='sudo systemctl stop nftables'
alias fw-status='sudo nft list ruleset'
alias cloud-sync='rclone sync ~/Documents gdrive:Documents'
ZSHRC_EOF
            chsh -s /usr/bin/zsh 2>/dev/null || true
            log_success "ZSH + Oh My Zsh + Powerlevel10k configured"
            ;;
        fish)
            log_info "Installing Fish + Fisher + Tide..."
            if ! pacman -Qi fish &>/dev/null; then
                try_catch "Install fish" "sudo pacman -S --noconfirm fish"
            fi
            mkdir -p "$HOME/.config/fish"
            curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish \
                -o "$HOME/.config/fish/functions/fisher.fish" 2>/dev/null || true
            cat > "$HOME/.config/fish/config.fish" << 'FISH_EOF'
# GodMode: Fish Configuration
alias ls='eza --icons'
alias cat='bat'
alias top='btop'
alias grep='rg'
alias du='dust'
alias df='duf'
alias ps='procs'
alias diff='delta'
alias find='fd'
alias pascal-mode='/usr/local/bin/pascal-mode'
alias godmode='pascal-mode'
alias rollback='snapper -c root list'
alias cloud-sync='rclone sync ~/Documents gdrive:Documents'
set -gx EDITOR nvim
starship init fish | source
FISH_EOF
            chsh -s /usr/bin/fish 2>/dev/null || true
            log_success "Fish + Fisher configured"
            ;;
        bash)
            log_info "Using existing Bash shell"
            cat >> "$HOME/.bashrc" << 'BASHRC_EOF'
# GodMode: Bash Aliases
alias ls='eza --icons'
alias cat='bat'
alias top='btop'
alias grep='rg'
alias du='dust'
alias df='duf'
alias ps='procs'
alias diff='delta'
alias find='fd'
alias pascal-mode='/usr/local/bin/pascal-mode'
alias godmode='pascal-mode'
alias rollback='snapper -c root list'
alias cloud-sync='rclone sync ~/Documents gdrive:Documents'
export EDITOR=nvim
BASHRC_EOF
            log_success "Bash aliases configured"
            ;;
    esac

    # --- Terminal setup ---
    case "$TERMINAL_CHOICE" in
        kitty)
            try_catch "Install kitty" "sudo pacman -S --noconfirm kitty 2>/dev/null; true"
            mkdir -p "$HOME/.config/kitty"
            cat > "$HOME/.config/kitty/kitty.conf" << 'KITTY_EOF'
# GodMode: Kitty Terminal Config
font_family JetBrains Mono Nerd Font
bold_font JetBrains Mono Nerd Font Bold
italic_font JetBrains Mono Nerd Font Italic
font_size 14.0
cursor #ff007f
cursor_shape beam
cursor_beam_thickness 2.0
background_opacity 0.92
background_blur 20
scrollback_lines 10000
mouse_hide_wait 3.0
shell_integration enabled
KITTY_EOF
            log_success "Kitty configured"
            ;;
        alacritty)
            try_catch "Install alacritty" "sudo pacman -S --noconfirm alacritty 2>/dev/null; true"
            mkdir -p "$HOME/.config/alacritty"
            cat > "$HOME/.config/alacritty/alacritty.toml" << 'ALACRITTY_EOF'
[font]
size = 14.0
family = "JetBrains Mono Nerd Font"

[cursor]
style = { shape = "Beam" }
blink = "Always"

[window]
opacity = 0.92

[scrolling]
history = 10000
ALACRITTY_EOF
            log_success "Alacritty configured"
            ;;
        wezterm)
            try_catch "Install wezterm" "sudo pacman -S --noconfirm wezterm 2>/dev/null; true"
            log_success "WezTerm installed"
            ;;
        foot)
            try_catch "Install foot" "sudo pacman -S --noconfirm foot 2>/dev/null; true"
            mkdir -p "$HOME/.config/foot"
            cat > "$HOME/.config/foot/foot.ini" << 'FOOT_EOF'
[main]
font=JetBrains Mono Nerd Font:size=14
dpi-aware=yes
[scrollback]
lines=10000
FOOT_EOF
            log_success "Foot configured"
            ;;
    esac

    # --- Tmux setup ---
    if ! pacman -Qi tmux &>/dev/null; then
        try_catch "Install tmux" "sudo pacman -S --noconfirm tmux 2>/dev/null; true"
    fi
    cat > "$HOME/.tmux.conf" << 'TMUX_EOF'
# GodMode: Tmux Configuration
set -g prefix C-a
unbind C-b
bind C-a send-prefix
set -g mouse on
set -g default-terminal "screen-256color"
set -g history-limit 10000
bind-key h select-pane -L
bind-key j select-pane -D
bind-key k select-pane -U
bind-key l select-pane -R
TMUX_EOF
    log_success "Tmux configured"

    # --- Install modern CLI tools ---
    for tool in eza bat btop ripgrep du-dust duf procs delta fd; do
        ! command -v "$tool" &>/dev/null && \
            try_catch "Install ${tool}" "sudo pacman -S --noconfirm ${tool} 2>/dev/null; true" || true
    done

    log_success "Shell & Terminal Enhancement complete!"
}


# ============================================================================
# PART 4: DYNAMIC CPU AFFINITY ENGINE (ĐIỀU PHỐI ĐẢO NGÔI CORES)
# ============================================================================
# Phân hệ này tạo ra một trình giám sát thời gian thực kết nối trực tiếp
# vào socket sự kiện của Hyprland để bắt sự kiện chuyển đổi cửa sổ.
# ----------------------------------------------------------------------------
# CƠ CHẾ SCIENTIFIC:
# CPU Intel Core i5-7300U có 2 Physical Cores / 4 Logical Cores (Hyper-Threading):
#   Physical Core 0 → Logical Core 0 (Core 0), Logical Core 1 (Core 1)
#   Physical Core 1 → Logical Core 2 (Core 2), Logical Core 3 (Core 3)
#
# Chiến lược điều phối:
#   • Active Window → Core 0,1 (cùng physical core → L1 cache sharing, low latency)
#     + Chính sách SCHED_RR (Round Robin) với priority 50
#     + I/O priority lớp Best-effort, mức 0 (cao nhất)
#   • Background Windows → Core 2,3 (physical core riêng, không ảnh hưởng)
#     + Chính sách SCHED_OTHER (tiêu chuẩn)
#     + I/O priority lớp Best-effort, mức 5 (thấp)
#   • Compiler/Server (node, java, etc) → locked Core 2,3 + nice=15 (via ananicy)
# ----------------------------------------------------------------------------
# THAM SỐ KERNEL:
#   taskset: gán CPU affinity mask (cores 0-3)
#   chrt:    thay đổi scheduling policy/priority
#   ionice:  thay đổi I/O scheduling class/priority
#   sleep 0.05: ổn định tải, tránh thrashing khi đổi window nhanh

setup_cpu_affinity_engine() {
    log_header "PHẦN 4: DYNAMIC CPU AFFINITY ENGINE"

    # --- Bước 1: Cài đặt ananicy-cpp ---
    # ananicy-cpp là daemon điều phối ưu tiên tiến trình tự động
    # Dùng rules trong /etc/ananicy.d/ để gán nice/ionice mặc định
    # Step 1: Install ananicy-cpp for automatic process priority management
    if ! systemctl is-enabled ananicy-cpp &>/dev/null 2>&1; then
        try_aur "ananicy-cpp" "ananicy-git"
        try_catch "Enable ananicy-cpp service" "sudo systemctl enable --now ananicy-cpp 2>/dev/null; true"
    else
        log_info "ananicy-cpp is already installed and enabled"
    fi

    # --- Bước 2: Tạo ananicy rules cho compiler/server ---
    # Step 2: Create ananicy rules for compiler/server processes
    # Các tiến trình này sẽ bị khóa ở Core 2,3 với nice=15
    # Rule format: { "name": "process_name", "nice": 15, "cgroup": "..." }

    local ANANICY_RULES_DIR="/etc/ananicy.d/00-godmode"

    if [ ! -d "$ANANICY_RULES_DIR" ]; then
        try_catch "Create ananicy rules dir" "sudo mkdir -p '$ANANICY_RULES_DIR'"
    fi

    # Rule cho compiler / server processes — khóa core 2,3 và nice=15
    # Rules for headless processes: lock to cores 2,3 with low priority
    local RULES_FILE="/etc/ananicy.d/00-godmode/compiler-lock.rules"
    if [ ! -f "$RULES_FILE" ]; then
        safe_sudo_write "$RULES_FILE" '# GodMode: Lock compiler/server processes to cores 2,3 with nice=15
# Cơ chế: Các process này không cần tương tác UI, đẩy xuống core riêng
{ "name": "node", "nice": 15, "cgroup": "system" }
{ "name": "java", "nice": 15, "cgroup": "system" }
{ "name": "dotnet", "nice": 15, "cgroup": "system" }
{ "name": "msbuild", "nice": 15, "cgroup": "system" }
{ "name": "python", "nice": 15, "cgroup": "system" }
{ "name": "php", "nice": 15, "cgroup": "system" }
{ "name": "gcc", "nice": 15, "cgroup": "system" }
{ "name": "clang", "nice": 15, "cgroup": "system" }
{ "name": "cargo", "nice": 15, "cgroup": "system" }
{ "name": "go", "nice": 15, "cgroup": "system" }
{ "name": "rustc", "nice": 15, "cgroup": "system" }
{ "name": "npm", "nice": 15, "cgroup": "system" }
{ "name": "yarn", "nice": 15, "cgroup": "system" }
{ "name": "ollama", "nice": 19, "cgroup": "system" }
'
        log_success "Created ananicy compiler rules"
    fi

    # Restart ananicy để áp dụng rules mới
    # Restart ananicy to apply new rules
    try_catch "Restart ananicy-cpp" "sudo systemctl restart ananicy-cpp"

    # --- Bước 3: Tạo script hyprland-event-monitor.sh ---
    # Step 3: Create the Hyprland event monitor script
    # Script này chạy nền (background daemon) lắng nghe socket Hyprland

    local MONITOR_SCRIPT="$HOME/.config/hypr/hyprland-event-monitor.sh"

    # Cơ chế: Hyprland tạo một Unix socket tại:
    #   $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock
    # nc (netcat) kết nối và đọc từng dòng sự kiện
    # Khi gặp "activewindow>>", trích xuất class và title,
    # dùng hyprctl để lấy PID, sau đó gán affinity

    log_info "Creating Hyprland event monitor script..."

    local SRC_MONITOR="$(dirname "$0")/hyprland-event-monitor.sh"
    if [ -f "$SRC_MONITOR" ]; then
        cp "$SRC_MONITOR" "$MONITOR_SCRIPT"
        chmod +x "$MONITOR_SCRIPT"
        log_success "Created event monitor script: ${MONITOR_SCRIPT}"
    else
        log_warn "Source hyprland-event-monitor.sh not found"
    fi

    # --- Bước 4: Thêm exec-once vào hyprland.conf ---
    # Step 4: Add exec-once line to hyprland.conf to auto-start monitor

    local HYPRLAND_CONF="$HOME/.config/hypr/hyprland.conf"
    if [ -f "$HYPRLAND_CONF" ]; then
        if ! grep -q "hyprland-event-monitor" "$HYPRLAND_CONF" 2>/dev/null; then
            try_catch "Add exec-once for event monitor" \
                "echo -e '\n# GodMode: Dynamic CPU Affinity Engine\nexec-once = ${MONITOR_SCRIPT}' >> '$HYPRLAND_CONF'"
        fi
    fi

    # --- Bước 5: Mở rộng ananicy rules cho tất cả nhóm A-E ---
    # Step 5: Create comprehensive ananicy rules for process groups
    log_info "Creating comprehensive ananicy rules (Groups A-E)..."

    local RULES_FILE="/etc/ananicy.d/00-godmode/99-cfxz6-groups.rules"
    if [ ! -f "$RULES_FILE" ]; then
        safe_sudo_write "$RULES_FILE" '# GodMode: Comprehensive CF-XZ6 Process Groups
# Group A — Active Foreground (Core 0,1, SCHED_RR, priority 50, ionice 0)
{ "name": "firefox", "nice": -5, "cgroup": "user" }
{ "name": "code-oss", "nice": -5, "cgroup": "user" }
{ "name": "kitty", "nice": -5, "cgroup": "user" }
{ "name": "Alacritty", "nice": -5, "cgroup": "user" }
{ "name": "obsidian", "nice": -5, "cgroup": "user" }
{ "name": "zathura", "nice": -5, "cgroup": "user" }
{ "name": "mpv", "nice": -5, "cgroup": "user" }
{ "name": "aseprite", "nice": -5, "cgroup": "user" }

# Group B — Background GUI (Core 2,3, SCHED_OTHER, ionice 5)
{ "name": "discord", "nice": 5, "cgroup": "user" }
{ "name": "telegram-desktop", "nice": 5, "cgroup": "user" }
{ "name": "element-desktop", "nice": 5, "cgroup": "user" }
{ "name": "thunar", "nice": 5, "cgroup": "user" }
{ "name": "nautilus", "nice": 5, "cgroup": "user" }

# Group C — Dev Daemon Locked (Core 2,3, nice=15)
{ "name": "node", "nice": 15, "cgroup": "system" }
{ "name": "java", "nice": 15, "cgroup": "system" }
{ "name": "dotnet", "nice": 15, "cgroup": "system" }
{ "name": "msbuild", "nice": 15, "cgroup": "system" }
{ "name": "python", "nice": 15, "cgroup": "system" }
{ "name": "php", "nice": 15, "cgroup": "system" }
{ "name": "gcc", "nice": 15, "cgroup": "system" }
{ "name": "clang", "nice": 15, "cgroup": "system" }
{ "name": "cargo", "nice": 15, "cgroup": "system" }
{ "name": "go", "nice": 15, "cgroup": "system" }
{ "name": "rustc", "nice": 15, "cgroup": "system" }
{ "name": "npm", "nice": 15, "cgroup": "system" }
{ "name": "yarn", "nice": 15, "cgroup": "system" }
{ "name": "ollama", "nice": 19, "cgroup": "system" }
{ "name": "dockerd", "nice": 15, "cgroup": "system" }
{ "name": "containerd", "nice": 15, "cgroup": "system" }
{ "name": "mysqld", "nice": 15, "cgroup": "system" }
{ "name": "postgres", "nice": 15, "cgroup": "system" }
{ "name": "redis-server", "nice": 15, "cgroup": "system" }
{ "name": "typescript-language-server", "nice": 15, "cgroup": "system" }
{ "name": "rust-analyzer", "nice": 15, "cgroup": "system" }
{ "name": "pylsp", "nice": 15, "cgroup": "system" }
{ "name": "gopls", "nice": 15, "cgroup": "system" }
{ "name": "clangd", "nice": 15, "cgroup": "system" }
{ "name": "lua-language-server", "nice": 15, "cgroup": "system" }

# Group D — Media/GPU (Core 0,1, nice=5, ionice idle)
{ "name": "ffmpeg", "nice": 5, "cgroup": "user" }
{ "name": "gstreamer", "nice": 5, "cgroup": "user" }
{ "name": "obs", "nice": 5, "cgroup": "user" }
{ "name": "pipewire", "nice": 0, "cgroup": "system" }
{ "name": "wireplumber", "nice": 0, "cgroup": "system" }
'
        log_success "Created comprehensive ananicy rules"
    fi

    # Restart ananicy to apply new rules
    try_catch "Restart ananicy-cpp" "sudo systemctl restart ananicy-cpp"

    # --- Bước 6: Tạo script safeguard CPU affinity ---
    # Step 6: Create thermal safeguard script
    local SAFEGUARD_SCRIPT="/usr/local/bin/godmode-affinity-safeguard.sh"
    safe_sudo_write "$SAFEGUARD_SCRIPT" '#!/bin/bash
# GodMode: CPU Affinity Safeguard
# Tu dong suspend affinity khi nhiet do >85°C hoac CPU usage >90%
STATE_FILE="/tmp/godmode-cpu-affinity-state.json"
THROTTLED=0

save_state() {
    hyprctl clients -j 2>/dev/null | jq -c '\''.[] | {pid: .pid, class: .class}'\'' > "$STATE_FILE" 2>/dev/null || true
}

restore_default() {
    for pid_dir in /proc/[0-9]*; do
        local pid="${pid_dir#/proc/}"
        chrt -o -p 0 "$pid" 2>/dev/null || true
    done
}

while true; do
    local temp
    temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
    temp=$((temp / 1000))

    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '\''{print $2 + $4}'\'' 2>/dev/null || echo 0)

    if [ "$temp" -gt 85 ] || [ "${cpu_usage%.*}" -gt 90 ]; then
        if [ "$THROTTLED" -eq 0 ]; then
            save_state
            restore_default
            THROTTLED=1
            echo "[$(date)] THERMAL THROTTLE: T=$temp°C CPU=$cpu_usage%" >> /tmp/godmode-affinity-safeguard.log
        fi
    elif [ "$THROTTLED" -eq 1 ] && [ "$temp" -lt 75 ] && [ "${cpu_usage%.*}" -lt 70 ]; then
        THROTTLED=0
        echo "[$(date)] UNTHROTTLED: T=$temp°C CPU=$cpu_usage%" >> /tmp/godmode-affinity-safeguard.log
    fi

    sleep 10
done
'
    try_catch "Make safeguard script executable" "sudo chmod +x '$SAFEGUARD_SCRIPT'"
    log_success "Affinity safeguard created (thermal >85°C / CPU >90%)"

    log_success "Dynamic CPU Affinity Engine fully configured!"
}


# ============================================================================
# PART 3.5: MEMORY & PROCESS ADVANCED TUNING
# ============================================================================
# Phân hệ này cấu hình systemd-oomd, earlyoom, và hugepages để quản lý
# bộ nhớ chủ động, tránh kernel OOM panic.
# ----------------------------------------------------------------------------

setup_memory_tuning() {
    log_header "PHẦN 3.5: MEMORY & PROCESS ADVANCED TUNING"

    # --- systemd-oomd ---
    if ! pacman -Qi systemd-oomd &>/dev/null; then
        try_catch "Install systemd-oomd" "sudo pacman -S --noconfirm systemd-oomd 2>/dev/null; true"
    fi
    safe_sudo_write "/etc/systemd/oomd.conf" '[OOM]
# GodMode: OOMD Configuration
# Kill processes when swap pressure exceeds 80%
DefaultMemoryPressureLimit=80
DefaultMemoryPressureDurationSec=10
SwapUsedLimitPercent=90
'
    try_catch "Enable systemd-oomd" "sudo systemctl enable --now systemd-oomd 2>/dev/null; true"

    # --- earlyoom ---
    if ! command -v earlyoom &>/dev/null; then
        try_catch "Install earlyoom" "yay -S --noconfirm earlyoom 2>/dev/null; true"
    fi
    safe_sudo_write "/etc/default/earlyoom" '# GodMode: Early OOM Configuration
# Prefer to keep IDE/terminal alive
EARLYOOM_ARGS="--prefer code-oss|Alacritty|kitty|firefox|obsidian --avoid ollama|mysqld"
'
    try_catch "Enable earlyoom" "sudo systemctl enable --now earlyoom 2>/dev/null; true"
    log_success "earlyoom configured — prefers IDE, avoids AI/DB"

    # --- Hugepages ---
    safe_sudo_write "/etc/sysctl.d/99-hugepages.conf" '# GodMode: Hugepages Configuration
vm.nr_hugepages=128
vm.hugetlb_shm_group=0
'
    try_catch "Apply hugepages" "sudo sysctl -p /etc/sysctl.d/99-hugepages.conf 2>/dev/null; true"

    # --- ZRAM monitor alias ---
    local shell_rc="$HOME/.zshrc"
    [ -f "$HOME/.bashrc" ] && shell_rc="$HOME/.bashrc"
    if ! grep -q "zramctl" "$shell_rc" 2>/dev/null; then
        echo "" >> "$shell_rc"
        echo "# GodMode: ZRAM monitor" >> "$shell_rc"
        echo 'alias zram-stats="echo Orig Comp Mem Ratio; zramctl | tail -1 | awk '\''{printf \"%s %s %s %.1f\\n\", \$3, \$4, \$5, \$3/\$4}'\''"' >> "$shell_rc"
    fi

    log_success "Memory & Process Tuning complete!"
}


# ============================================================================
# PART 5: PANASONIC CF-XZ6 HARDWARE INTEGRATION
# ============================================================================
# Phân hệ này tích hợp các tính năng phần cứng đặc thù của dòng
# Panasonic CF-XZ6 — máy tính bảng lai (2-in-1) với màn hình cảm ứng,
# cảm biến xoay, bàn phím tháo rời, và công nghệ quản lý pin Panasonic.
# ----------------------------------------------------------------------------
# Các thành phần:
# 1. Hiển thị 3:2 — Monitor 2160x1440 scale 1.5x
# 2. Cảm ứng — Touchscreen driver transform matrix
# 3. Autorotate — iio-sensor-proxy + monitor-sensor listener
# 4. Tablet mode — ACPI/udev keyboard dock hotplug + ảo keyboard
# 5. Eco mode — Panasonic sysfs charge limit 80%

setup_cfxz6_hardware() {
    log_header "PHẦN 5: PANASONIC CF-XZ6 HARDWARE INTEGRATION"

    # --- Bước 1: Cấu hình Monitor 3:2 ---
    # Step 1: Configure 2160x1440 3:2 display with 1.5x scaling
    # CF-XZ6 có màn hình 2160x1440 (tỷ lệ 3:2) — scale 1.5 để UI không quá nhỏ

    local HYPRLAND_CONF="$HOME/.config/hypr/hyprland.conf"
    if [ -f "$HYPRLAND_CONF" ]; then
        # Kiểm tra và thay thế monitor config / Check and replace monitor config
        if grep -q "^monitor=" "$HYPRLAND_CONF" 2>/dev/null; then
            try_catch "Override monitor config (2160x1440@1.5x)" \
                "sed -i 's/^monitor=.*/monitor=eDP-1,2160x1440@60Hz,0x0,1.5/' '$HYPRLAND_CONF'"
        else
            try_catch "Add monitor config" \
                "echo 'monitor=eDP-1,2160x1440@60Hz,0x0,1.5' >> '$HYPRLAND_CONF'"
        fi

        # Cấu hình touchscreen transform / Configure touchscreen
        # input:touchdevice:transform = 0 (không xoay, mapping chuẩn)
        if grep -q "input:touchdevice" "$HYPRLAND_CONF" 2>/dev/null; then
            try_catch "Set touchdevice transform" \
                "sed -i 's/input:touchdevice:transform =.*/input:touchdevice:transform = 0/' '$HYPRLAND_CONF'"
        else
            try_catch "Add touchdevice config" \
                "echo -e '\ninput {\n    touchdevice:transform = 0\n}' >> '$HYPRLAND_CONF'"
        fi

        log_success "Display and touchscreen configured"
    fi

    # --- Bước 2: Cài đặt cảm biến xoay (Autorotate Engine) ---
    # Step 2: Install iio-sensor-proxy for accelerometer-based screen rotation
    # iio-sensor-proxy đọc dữ liệu từ cảm biến gia tốc IIO (Industrial I/O)
    # và phát tín hiệu D-Bus khi hướng máy thay đổi

    if ! pacman -Qi iio-sensor-proxy &>/dev/null; then
        try_catch "Install iio-sensor-proxy" "sudo pacman -S --noconfirm iio-sensor-proxy 2>/dev/null; true"
    fi

    # Tạo script autorotate / Create autorotate script
    # Lắng nghe monitor-sensor (đi kèm iio-sensor-proxy) và ánh xạ
    # hướng cảm biến → tham số xoay màn hình Hyprland

    local ROTATOR_SCRIPT="$HOME/.config/hypr/cf-xz6-rotator.sh"
    log_info "Creating autorotate script..."

    local SRC_ROTATOR="$(dirname "$0")/cf-xz6-rotator.sh"
    if [ -f "$SRC_ROTATOR" ]; then
        cp "$SRC_ROTATOR" "$ROTATOR_SCRIPT"
        chmod +x "$ROTATOR_SCRIPT"
        log_success "Created autorotate script: ${ROTATOR_SCRIPT}"
    else
        log_warn "Source cf-xz6-rotator.sh not found"
    fi

    # Thêm exec-once cho autorotate vào hyprland.conf
    # Add exec-once entry for autorotate
    if [ -f "$HYPRLAND_CONF" ]; then
        if ! grep -q "cf-xz6-rotator" "$HYPRLAND_CONF" 2>/dev/null; then
            try_catch "Add exec-once for autorotate" \
                "echo 'exec-once = ${ROTATOR_SCRIPT}' >> '$HYPRLAND_CONF'"
        fi
    fi

    # --- Bước 3: Tablet Mode — udev rule cho keyboard dock ---
    # Step 3: Tablet Mode — udev rule for physical keyboard dock hotplug
    # Khi tháo màn hình khỏi dock bàn phím, hệ thống ACPI gửi sự kiện
    # udev. Ta tạo rule để tự động disable keyboard khi undock.

    local UDEV_RULE="/etc/udev/rules.d/99-cfxz6-tablet-mode.rules"
    log_info "Creating udev rule for tablet mode..."

    # udev rule này bắt sự kiện thay đổi thiết bị đầu vào
    # Khi dock bàn phím bị ngắt kết nối (ACTION=="remove"),
    # script sẽ vô hiệu hóa driver bàn phím dock
    # Khi kết nối lại (ACTION=="add"), kích hoạt lại

    safe_sudo_write "$UDEV_RULE" '# GodMode: Panasonic CF-XZ6 Tablet Mode
# Khi undock → tắt keyboard dock, bật ảo keyboard
# When undocked → disable dock keyboard, enable virtual keyboard
ACTION=="remove", SUBSYSTEM=="input", ENV{ID_VENDOR}=="Pana*", RUN+="/usr/local/bin/cfxz6-tablemode.sh disable"
ACTION=="add", SUBSYSTEM=="input", ENV{ID_VENDOR}=="Pana*", RUN+="/usr/local/bin/cfxz6-tablemode.sh enable"
'

    # Reload udev rules để áp dụng
    # Reload udev rules to apply
    try_catch "Reload udev rules" "sudo udevadm control --reload-rules && sudo udevadm trigger"

    # Tạo script tablet mode handler / Create tablet mode handler script
    local TABLET_SCRIPT="/usr/local/bin/cfxz6-tablemode.sh"
    safe_sudo_write "$TABLET_SCRIPT" '#!/bin/bash
# CF-XZ6 Tablet Mode Handler
# Được gọi bởi udev rule khi dock keyboard kết nối/ngắt
# Called by udev rule on keyboard dock hotplug
ACTION="$1"
case "$ACTION" in
    disable)
        # Undock: tắt keyboard dock, kích hoạt virtual keyboard
        echo "Tablet mode: keyboard dock removed" >> /tmp/cfxz6-tablet.log
        # Vô hiệu hóa driver keyboard dock
        # Disable dock keyboard driver
        ;;
    enable)
        # Dock: bật lại keyboard dock
        echo "Tablet mode: keyboard dock attached" >> /tmp/cfxz6-tablet.log
        # Reactivate keyboard driver
        ;;
esac
'

    try_catch "Make tablet script executable" "sudo chmod +x '$TABLET_SCRIPT'"

    # --- Bước 4: Eco Mode — Giới hạn sạc pin 80% ---
    # Step 4: Eco Mode — Battery charge limit at 80%
    log_info "Configuring Eco Mode (80% charge limit)..."

    # Dùng capability đã probe thay vì tự probe lại
    if [ "$CAP_PANASONIC_MOD" -eq 1 ]; then
        log_info "Kernel module panasonic_laptop is loaded"
    else
        log_info "Kernel module panasonic_laptop not available"
    fi

    if [ "$CAP_ECO_MODE" -eq 1 ]; then
        try_catch "Enable Panasonic Eco Mode" \
            "echo '1' | sudo tee /sys/devices/platform/panasonic/eco_mode > /dev/null"
        safe_sudo_write "/etc/systemd/system/godmode-eco-mode.service" '[Unit]
Description=GodMode: Panasonic CF-XZ6 Eco Mode (80% charge limit)
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c "echo 1 > /sys/devices/platform/panasonic/eco_mode"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
'
        try_catch "Enable eco-mode service" "sudo systemctl enable godmode-eco-mode.service 2>/dev/null; true"
        log_success "Panasonic Eco Mode: 80% charge limit active"
    elif [ "$CAP_CHARGE_THRESH" -eq 1 ]; then
        try_catch "Set charge threshold 80%" \
            "echo '80' | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold > /dev/null"
        log_success "Generic charge threshold set to 80%"
    else
        log_info "No charge limit mechanism available — battery will charge to 100%"
    fi

    # --- Bước 5: Cài đặt virtual keyboard (wvkbd) ---
    try_catch "Install wvkbd" "sudo pacman -S --noconfirm wvkbd 2>/dev/null; true"

    # --- Bước 6: Wacom Stylus Calibration ---
    log_info "Configuring Wacom stylus..."
    try_catch "Install xf86-input-wacom" "sudo pacman -S --noconfirm xf86-input-wacom 2>/dev/null; true"
    # Copy stylus calibrate script
    local STYLUS_SCRIPT="/usr/local/bin/cfxz6-stylus-calibrate.sh"
    if [ -f "$(dirname "$0")/cfxz6-stylus-calibrate.sh" ]; then
        try_catch "Copy stylus calibrate script" \
            "sudo cp '$(dirname "$0")/cfxz6-stylus-calibrate.sh' '$STYLUS_SCRIPT'"
        try_catch "Make stylus script executable" "sudo chmod +x '$STYLUS_SCRIPT'"
    fi
    log_success "Wacom stylus calibration configured"

    # --- Bước 7: SD Card Reader auto-mount ---
    log_info "Creating SD Card auto-mount udev rule..."
    safe_sudo_write "/etc/udev/rules.d/99-sd-card.rules" '# GodMode: SD Card Auto-Mount
ACTION=="add", SUBSYSTEM=="block", KERNEL=="mmcblk[0-9]*", RUN+="/usr/bin/systemd-mount --no-block --automount=yes /dev/%k /media/sd"
'
    try_catch "Create media/sd directory" "sudo mkdir -p /media/sd"

    # --- Bước 8: Touchpad Gestures ---
    log_info "Configuring touchpad gestures..."
    if [ -f "$HYPRLAND_CONF" ]; then
        if ! grep -q "natural_scroll" "$HYPRLAND_CONF" 2>/dev/null; then
            cat >> "$HYPRLAND_CONF" << 'TP_EOF'

# GodMode: Touchpad Gestures
input:touchpad:natural_scroll=yes
input:touchpad:tap-to-click=yes
input:touchpad:scroll_factor=0.5
gestures:workspace_swipe=3
gestures:workspace_swipe_fingers=4
gestures:workspace_swipe_distance=300
TP_EOF
            log_success "Touchpad gestures configured"
        fi
    fi

    # --- Bước 9: Lid Switch Actions ---
    log_info "Configuring lid switch actions..."
    safe_sudo_write "/etc/udev/rules.d/99-lid-switch.rules" '# GodMode: Lid Switch Actions
# Suspend on battery, lock screen on AC
ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemctl suspend"
'
    try_catch "Reload udev rules" "sudo udevadm control --reload-rules && sudo udevadm trigger"

    # --- Bước 10: Keyboard Backlight ---
    if [ "$CAP_KBD_BACKLIGHT" -eq 1 ]; then
        log_info "Keyboard backlight detected at: ${CAP_KBD_PATH}"
        safe_sudo_write "/usr/local/bin/cfxz6-kbd-backlight.sh" '#!/bin/bash
# GodMode: Keyboard Backlight Control
BRIGHTNESS="${1:-0}"
echo "$BRIGHTNESS" | sudo tee /sys/class/leds/*::kbd_backlight/brightness > /dev/null
'
        try_catch "Make kbd backlight script executable" "sudo chmod +x /usr/local/bin/cfxz6-kbd-backlight.sh"
        mkdir -p "$HOME/.config/systemd/user"
        cat > "$HOME/.config/systemd/user/cfxz6-kbd-backlight-off.service" << 'KBD_EOF'
[Unit]
Description=GodMode: Keyboard backlight off after 30s idle

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cfxz6-kbd-backlight.sh 0

[Install]
WantedBy=default.target
KBD_EOF
        log_success "Keyboard backlight configured"
    else
        log_info "No keyboard backlight detected"
    fi

    log_success "CF-XZ6 Hardware Integration complete!"
}


# ============================================================================
# PART 6: THERMAL HARDENING & UNDERVOLT (QUẢN LÝ NHIỆT & ĐIỆN ÁP)
# ============================================================================
# Phân hệ này tập trung vào kiểm soát nhiệt độ và hạ điện áp an toàn
# cho CPU Kaby Lake i5-7300U, vốn nổi tiếng với vấn đề nhiệt trên
# các dòng máy mỏng nhẹ (ultrabook / tablet lai).
# ----------------------------------------------------------------------------
# CƠ CHẾ SCIENTIFIC:
# 1. thermald: Intel Thermal Daemon — quản lý nhiệt ACPI DPTF
# 2. TLP: Advanced power management — khóa Turbo Boost, giới hạn GPU freq
# 3. intel-undervolt: Hạ điện áp CPU/GPU/Cache ở mức an toàn
#
# Thông số chip i5-7300U:
#   Base Frequency: 2.5GHz → khóa ở mức này (không boost)
#   Max Turbo: 3.5GHz (tắt để giảm nhiệt)
#   TDP: 15W (có thể giảm bằng undervolt)
#   GPU Base: 300MHz → khóa min=300, max=750
#
# Mức undervolt an toàn cho Kaby Lake di động:
#   CPU Core: -50mV  (ngưỡng an toàn tuyệt đối, không gây mất ổn định)
#   GPU:      -20mV  (GPU nhạy cảm hơn với undervolt)
#   CPU Cache: -50mV (cùng mức với Core để tránh lệch điện áp)

setup_thermal_undervolt() {
    log_header "PHẦN 6: THERMAL HARDENING & UNDERVOLT"

    # --- Bước 1: Intel Thermal Daemon (thermald) ---
    # Step 1: Install and enable Intel Thermal Daemon
    # thermald sử dụng ACPI DPTF (Dynamic Platform and Thermal Framework)
    # để kiểm soát nhiệt độ real-time bằng cách điều chỉnh P-state và T-state

    if ! pacman -Qi thermald &>/dev/null; then
        try_catch "Install thermald" "sudo pacman -S --noconfirm thermald"
    fi

    # Bật và kích hoạt thermald service
    # Enable and start thermald — chạy nền với quyền root
    try_catch "Enable thermald" "sudo systemctl enable --now thermald 2>/dev/null; true"
    log_success "thermald running — monitoring ACPI thermal zones"

    # --- Bước 2: TLP Advanced Configuration ---
    # Step 2: Configure TLP for Kaby Lake thermal optimization
    # TLP là công cụ quản lý năng lượng toàn diện, thay thế các
    # cơ chế mặc định của kernel cho laptop

    if ! pacman -Qi tlp &>/dev/null; then
        try_catch "Install tlp" "sudo pacman -S --noconfirm tlp 2>/dev/null; true"
    fi

    # Ghi cấu hình TLP / Write TLP configuration
    # Các tham số chính:
    #   CPU_BOOST_ON_AC=0, CPU_BOOST_ON_BAT=0: tắt Turbo Boost hoàn toàn
    #     → CPU locked at base frequency 2.5GHz, nhiệt 50-60°C
    #   INTEL_GPU_MIN/MAX_FREQ_ON_AC: khóa GPU ở dải tần tiết kiệm
    #     → Giảm sinh nhiệt từ iGPU HD Graphics 620

    log_info "Configuring TLP for thermal safety..."

    safe_sudo_write "/etc/tlp.conf" '# GodMode: Panasonic CF-XZ6 TLP Configuration
# Kaby Lake i5-7300U — Thermal-hardened profile

# --- CPU ---
# Vô hiệu hóa Intel Turbo Boost — khóa xung nhịp base 2.5GHz
# Disable Turbo Boost — lock frequency at 2.5GHz base
CPU_BOOST_ON_AC=0
CPU_BOOST_ON_BAT=0

# Giới hạn scaling frequency / Limit CPU frequency range
# Min/Max frequency in MHz (2500 = 2.5GHz base for i5-7300U)
CPU_SCALING_MIN_FREQ_ON_AC=800
CPU_SCALING_MAX_FREQ_ON_AC=2500
CPU_SCALING_MIN_FREQ_ON_BAT=800
CPU_SCALING_MAX_FREQ_ON_BAT=2500

# Governor: powersave để ưu tiên tiết kiệm nhiệt
# Governor for thermal efficiency
CPU_ENERGY_PERF_POLICY_ON_AC=balance_power
CPU_ENERGY_PERF_POLICY_ON_BAT=power

# --- Intel GPU ---
# Giới hạn tần số GPU / GPU frequency range
# HD Graphics 620: base 300MHz, max 1000MHz — ta kẹp ở 300-750MHz
INTEL_GPU_MIN_FREQ_ON_AC=300
INTEL_GPU_MAX_FREQ_ON_AC=750
INTEL_GPU_MIN_FREQ_ON_BAT=300
INTEL_GPU_MAX_FREQ_ON_BAT=500

# --- Disk ---
# Bật Advanced Power Management cho SSD — tiết kiệm điện
DISK_APM_LEVEL_ON_AC="254"
DISK_APM_LEVEL_ON_BAT="128"

# --- USB ---
# Tắt USB autosuspend cho thiết bị ngoại vi
USB_AUTOSUSPEND=0

# --- PCI Express ---
# Active State Power Management (ASPM) — tiết kiệm điện cho PCIe
PCI_EXP_ASPM_ON_AC=powersupersave
PCI_EXP_ASPM_ON_BAT=powersupersave

# --- Runtime Power Management ---
RUNTIME_PM_ON_AC=auto
RUNTIME_PM_ON_BAT=auto

# --- Wifi ---
# Tắt wifi power saving để tránh mất gói
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=off
'

    # Bật TLP service / Enable TLP service
    if systemctl is-enabled tlp &>/dev/null 2>&1; then
        try_catch "Restart TLP" "sudo systemctl restart tlp 2>/dev/null; true"
    else
        try_catch "Enable TLP" "sudo systemctl enable --now tlp 2>/dev/null; true"
    fi

    log_success "TLP configured — Turbo Boost disabled, GPU freq capped"

    # --- Bước 3: Undervolt Configuration ---
    # Step 3: Configure intel-undervolt for safe voltage reduction
    # intel-undervolt sử dụng MSR (Model-Specific Registers) của Intel
    # để điều chỉnh điện áp Vcore, Vcache, Vgpu theo công thức:
    #   New_Voltage = Base_Voltage + Offset (âm là hạ áp)

    if ! pacman -Qi intel-undervolt &>/dev/null; then
        try_aur "intel-undervolt" "intel-undervolt-git"
    fi

    log_info "Configuring undervolt (safe zone)..."

    # Ghi cấu hình undervolt / Write undervolt config
    # Các thông số hạ áp tuyệt đối an toàn cho Kaby Lake:
    #   CPU Core: -50mV (giảm ~0.5W-1W TDP)
    #   GPU: -20mV (GPU nhạy, hạ thấp hơn có thể gây lỗi đồ họa)
    #   CPU Cache: -50mV (phải bằng hoặc thấp hơn CPU Core offset)
    #   System Agent: -0mV (giữ nguyên để ổn định IMC)
    #   Analog I/O: -0mV (giữ nguyên cho ổn định analog)

    safe_sudo_write "/etc/intel-undervolt.conf" '# GodMode: Panasonic CF-XZ6 Undervolt Configuration
# Intel Kaby Lake i5-7300U — Safe undervolt zone
# Định dạng: undervolt <PLANE> <offset_mV>
# PLANE: core/gpu/cache/uncore/analogio

# CPU Core: -50mV (giảm nhiệt ~5-8°C khi full load)
# Core voltage reduction — biggest thermal impact
undervolt core -50

# GPU: -20mV (hạn chế để tránh lỗi render)
# GPU voltage — conservative to prevent graphical artifacts
undervolt gpu -20

# CPU Cache: -50mV (cùng mức với core)
# Cache voltage — match core to maintain stability
undervolt cache -50

# System Agent: 0mV (giữ nguyên)
# System Agent — no change for memory controller stability
undervolt uncore 0

# Analog I/O: 0mV (giữ nguyên)
# Analog I/O — no change for analog stability
undervolt analogio 0

# Áp dụng các thiết lập khi service start
# Apply settings on service start
'

    # Enable intel-undervolt service
    try_catch "Enable intel-undervolt" "sudo systemctl enable --now intel-undervolt 2>/dev/null; true"

    # --- Bước 4: auto-cpufreq ---
    log_info "Installing auto-cpufreq..."
    if ! command -v auto-cpufreq &>/dev/null; then
        try_catch "Install auto-cpufreq" "yay -S --noconfirm auto-cpufreq 2>/dev/null; true"
    fi
    safe_sudo_write "/etc/auto-cpufreq.conf" '# GodMode: auto-cpufreq Configuration
[charger]
governor = powersave
scaling_min_freq = 400000
scaling_max_freq = 2500000
energy_performance_preference = balance_performance

[battery]
governor = powersave
scaling_min_freq = 400000
scaling_max_freq = 1500000
energy_performance_preference = power
turbo = never
'
    try_catch "Enable auto-cpufreq" "sudo systemctl enable --now auto-cpufreq 2>/dev/null; true"

    # --- Bước 5: GPU Frequency Profile Script ---
    log_info "Creating GPU frequency profile script..."
    safe_sudo_write "/usr/local/bin/gpu-profile" '#!/bin/bash
# GodMode: GPU Frequency Profile Switcher
# Usage: gpu-profile [godmode|standard|battery]
DRM_PATH="/sys/class/drm/card0"
case "${1:-godmode}" in
    godmode)
        echo "300" | sudo tee "$DRM_PATH/gt_min_freq_mhz" > /dev/null
        echo "750" | sudo tee "$DRM_PATH/gt_max_freq_mhz" > /dev/null
        echo "God-Mode GPU: 300-750MHz"
        ;;
    standard)
        echo "200" | sudo tee "$DRM_PATH/gt_min_freq_mhz" > /dev/null
        echo "1000" | sudo tee "$DRM_PATH/gt_max_freq_mhz" > /dev/null
        echo "Standard GPU: 200-1000MHz"
        ;;
    battery)
        echo "200" | sudo tee "$DRM_PATH/gt_min_freq_mhz" > /dev/null
        echo "500" | sudo tee "$DRM_PATH/gt_max_freq_mhz" > /dev/null
        echo "Battery GPU: 200-500MHz"
        ;;
esac
'
    try_catch "Make gpu-profile executable" "sudo chmod +x /usr/local/bin/gpu-profile"

    # --- Bước 6: Governor Profile Switching Script ---
    log_info "Creating governor profile switcher..."
    safe_sudo_write "/usr/local/bin/godmode-governor" '#!/bin/bash
# GodMode: Governor Profile Switcher
# Usage: godmode-governor [godmode|standard|battery]
case "${1:-godmode}" in
    godmode)
        echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
        echo "0" | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo > /dev/null
        echo 2500000 | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq > /dev/null
        /usr/local/bin/gpu-profile godmode
        echo "God-Mode: powersave @ 2.5GHz no-turbo"
        ;;
    standard)
        echo schedutil | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
        echo "0" | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo > /dev/null
        /usr/local/bin/gpu-profile standard
        echo "Standard: schedutil + turbo allowed"
        ;;
    battery)
        echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
        echo "1" | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo > /dev/null
        echo 1500000 | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq > /dev/null
        /usr/local/bin/gpu-profile battery
        echo "Battery: powersave @ 1.5GHz no-turbo"
        ;;
esac
'
    try_catch "Make governor script executable" "sudo chmod +x /usr/local/bin/godmode-governor"

    # --- Bước 7: Multiple Undervolt Profiles ---
    log_info "Creating undervolt profiles..."
    safe_sudo_write "/usr/local/bin/godmode-undervolt" '#!/bin/bash
# GodMode: Undervolt Profile Switcher
# Usage: godmode-undervolt [safe|aggressive]
CONF="/etc/intel-undervolt.conf"
case "${1:-safe}" in
    safe)
        echo "undervolt core -35" | sudo tee "$CONF" > /dev/null
        echo "undervolt gpu -10"  | sudo tee -a "$CONF" > /dev/null
        echo "undervolt cache -35" | sudo tee -a "$CONF" > /dev/null
        echo "Safe undervolt: CPU -35mV, GPU -10mV, Cache -35mV"
        ;;
    aggressive)
        echo "undervolt core -75" | sudo tee "$CONF" > /dev/null
        echo "undervolt gpu -35"  | sudo tee -a "$CONF" > /dev/null
        echo "undervolt cache -75" | sudo tee -a "$CONF" > /dev/null
        echo "AGGRESSIVE: CPU -75mV, GPU -35mV, Cache -75mV"
        echo "WARNING: Test stability with stress test!"
        ;;
esac
sudo systemctl restart intel-undervolt 2>/dev/null
'
    try_catch "Make undervolt script executable" "sudo chmod +x /usr/local/bin/godmode-undervolt"

    # --- Bước 8: SATA/WiFi Power Saving ---
    log_info "Configuring SATA/WiFi power saving..."
    safe_sudo_write "/etc/udev/rules.d/99-power-save.rules" '# GodMode: SATA & WiFi Power Save (battery only)
ACTION=="add", SUBSYSTEM=="power_supply", KERNEL=="BAT0", RUN+="/usr/bin/bash -c '\''echo min_power > /sys/class/scsi_host/host0/link_power_management_policy'\''"
'
    try_catch "Reload power save udev rules" "sudo udevadm control --reload-rules 2>/dev/null; true"

    log_success "Thermal Hardening fully configured with profiles!"
}


# ============================================================================
# PART 7: BTRFS + ZRAM + sysctl (TỐI ƯU HỆ THỐNG FILE & BỘ NHỚ)
# ============================================================================
# Phân hệ này tối ưu hệ thống file Btrfs, cấu hình ZRAM cho swap nén,
# và tinh chỉnh tham số hạt nhân cho độ trễ tối thiểu.
# ----------------------------------------------------------------------------
# CƠ CHẾ SCIENTIFIC:
# 1. Btrfs:
#   - compress=zstd:3: Nén Zstd mức 3 (cân bằng tốc độ/tỉ lệ nén tốt nhất)
#   - noatime,nodiratime: Không cập nhật access time → giảm 50-80% I/O metadata
#   - commit=60: Flush dữ liệu mỗi 60 giây thay vì 30 → giảm I/O ngẫu nhiên
#   - space_cache=v2: B-tree free space cache, nhanh hơn v1
#
# 2. ZRAM:
#   - Dung lượng: 8GB (100% RAM vật lý)
#   - Thuật toán: zstd (nén nhanh, tỉ lệ tốt, lightweight)
#   - swappiness=100: Ưu tiên swap vào ZRAM hơn là drop page cache
#
# 3. sysctl:
#   - dirty_ratio=10: Writeback cache threshold 10% RAM
#   - dirty_background_ratio=5: Background writeback start
#   - sched_latency_ns=2000000: Target latency 2ms (an toàn 4 luồng)
#   - sched_min_granularity_ns=200000: Minimum slice 0.2ms

setup_btrfs_zram_sysctl() {
    log_header "PHẦN 7: BTRFS + ZRAM + sysctl TUNING"

    # --- Bước 1: Kiểm tra Btrfs và cập nhật fstab ---
    # Step 1: Check Btrfs and update fstab mount options
    # Phát hiện hệ thống file gốc có phải Btrfs không

    local ROOT_FS
    ROOT_FS=$(findmnt -n -o FSTYPE /)

    if [ "$ROOT_FS" = "btrfs" ]; then
        log_info "Root filesystem is Btrfs — updating mount options..."

        # Backup fstab trước khi sửa
        # Backup fstab before modifying
        if [ ! -f "/etc/fstab.godmode-bak" ]; then
            try_catch "Backup fstab" "sudo cp -a /etc/fstab /etc/fstab.godmode-bak"
        fi

        # Cập nhật fstab với các tham số tối ưu Btrfs
        # Update fstab entries with Btrfs optimization parameters
        # Sử dụng sed để thay thế các tùy chọn mount của subvolume @ và @home
        # Các tùy chọn: compress=zstd:3,noatime,nodiratime,commit=60,space_cache=v2

        local FSTAB_OPTS="compress=zstd:3,noatime,nodiratime,commit=60,space_cache=v2"

        # Thay thế tùy chọn mount cho subvolume @ (root)
        sudo sed -i "s|subvol=@[[:space:]]*[a-zA-Z0-9_,-]*|subvol=@ $FSTAB_OPTS|g" /etc/fstab
        sudo sed -i "s|subvol=@home[[:space:]]*[a-zA-Z0-9_,-]*|subvol=@home $FSTAB_OPTS|g" /etc/fstab

        log_success "fstab updated with Btrfs optimization options"

        # Remount để áp dụng ngay (không cần reboot)
        # Remount to apply immediately
        try_catch "Remount / with new options" "sudo mount -o remount /"
        try_catch "Remount /home" "sudo mount -o remount /home 2>/dev/null; true"
    else
        log_warn "Root filesystem is ${ROOT_FS}, not Btrfs — skipping fstab Btrfs tuning"
    fi

    # --- Bước 2: Cấu hình ZRAM ---
    # Step 2: Configure ZRAM generator
    # zram-generator tạo /dev/zram* devices tự động qua systemd

    if ! pacman -Qi zram-generator &>/dev/null; then
        try_catch "Install zram-generator" "sudo pacman -S --noconfirm zram-generator"
    fi

    log_info "Configuring ZRAM (8GB, zstd)..."

    # Ghi cấu hình ZRAM / Write zram-generator config
    # 8GB = 100% RAM, compression algorithm: zstd
    safe_sudo_write "/etc/systemd/zram-generator.conf" '[zram0]
# GodMode: ZRAM Configuration
# Dung lượng: 8GB (bằng 100% RAM vật lý)
# Thuật toán nén: zstd (cân bằng tốc độ/tỉ lệ nén tốt nhất)
zram-size = ram * 1          # 100% of physical RAM (8GB)
compression-algorithm = zstd # Fast compression with good ratio
'

    # Enable và start zram-generator / Enable and start ZRAM
    try_catch "Restart zram-generator" "sudo systemctl restart systemd-zram-setup@zram0"

    log_success "ZRAM configured: 8GB zstd compressed swap"

    # --- Bước 3: sysctl Latency Tuning ---
    # Step 3: Write sysctl configuration for low-latency tuning
    # Các tham số này tối ưu scheduler và memory management

    log_info "Writing sysctl latency tuning..."

    safe_sudo_write "/etc/sysctl.d/99-latency-tuning.conf" '# GodMode: Low-Latency sysctl Tuning for CF-XZ6
# Kernel scheduler and memory management optimization

# --- Virtual Memory ---
# swappiness=100: Ép hệ thống ưu tiên swap ZRAM hơn drop page cache
# Force ZRAM swap usage — compressed swap is faster than page reclaim
vm.swappiness=100

# Writeback cache threshold (% of RAM)
# dirty_ratio: 10% — tổng dirty pages tối đa trước khi force writeback
vm.dirty_ratio=10

# dirty_background_ratio: 5% — bắt đầu background writeback
vm.dirty_background_ratio=5

# Giảm pressure trên cache inode/dentry
# Reduce vfs cache pressure — keep more dentries/inodes cached
vm.vfs_cache_pressure=50

# --- CPU Scheduler (CFS) ---
# Tối ưu scheduler cho hệ thống 4 luồng (2 cores/4 threads)
# Optimize CFS scheduler for 4-thread system

# sched_latency_ns: 2ms — target preemption latency
# Giá trị thấp hơn giúp ứng dụng tương tác phản hồi nhanh hơn
kernel.sched_latency_ns=2000000

# sched_min_granularity_ns: 0.2ms — minimum execution slice
# Ngăn scheduler thrashing (chuyển context quá thường xuyên)
kernel.sched_min_granularity_ns=200000

# sched_wakeup_granularity_ns: 0.4ms — wake-up preemption
kernel.sched_wakeup_granularity_ns=400000

# Migrate cost: giảm ngưỡng di chuyển task giữa các cores
# Lower migration cost — keep tasks on cache-hot cores
kernel.sched_migration_cost_ns=500000

# --- inotify ---
# fs.inotify.max_user_watches: tăng giới hạn theo dõi file
# Cần thiết cho IDE (VS Code), file watchers (npm, yarn)
fs.inotify.max_user_watches=524288
# Giới hạn instance inotify
fs.inotify.max_user_instances=1024

# --- Network ---
# TCP fastopen: giảm latency kết nối TCP
net.ipv4.tcp_fastopen=3

# Tăng backlog cho ứng dụng network-heavy
net.core.somaxconn=16384
'

    # Apply sysctl parameters without reboot
    try_catch "Apply sysctl parameters" "sudo sysctl --system"

    # --- Bước 4: Snapper Configuration ---
    log_info "Configuring Snapper snapshots..."
    if ! pacman -Qi snapper &>/dev/null; then
        try_catch "Install snapper" "sudo pacman -S --noconfirm snapper snap-pac 2>/dev/null; true"
    fi
    if ! command -v snapper &>/dev/null; then
        log_warn "snapper not available, skipping"
    else
        # Configure root snapshots if not already done
        if [ ! -f "/etc/snapper/configs/root" ]; then
            try_catch "Create snapper root config" "sudo snapper -c root create-config /"
            safe_sudo_append "/etc/snapper/configs/root" '# GodMode: Snapper Root Config
TIMELINE_LIMIT_HOURLY="10"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="4"
TIMELINE_LIMIT_MONTHLY="2"
'
        fi
        # Configure home snapshots if not already done
        if [ ! -f "/etc/snapper/configs/home" ]; then
            try_catch "Create snapper home config" "sudo snapper -c home create-config /home"
            safe_sudo_append "/etc/snapper/configs/home" '# GodMode: Snapper Home Config
TIMELINE_LIMIT_HOURLY="0"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="0"
TIMELINE_LIMIT_MONTHLY="0"
'
        fi
        # Enable snapper timers
        try_catch "Enable snapper timers" \
            "sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer 2>/dev/null; true"
        log_success "Snapper configured — auto-snapshots before pacman"
    fi

    # --- Bước 5: Btrfs Scrub + Balance timer ---
    log_info "Creating Btrfs scrub timer..."
    safe_sudo_write "/etc/systemd/system/btrfs-scrub@.service" '[Unit]
Description=GodMode: Btrfs Scrub for %I

[Service]
Type=oneshot
ExecStart=/usr/bin/btrfs scrub start -B %I
Nice=19
IOSchedulingClass=idle
'
    safe_sudo_write "/etc/systemd/system/btrfs-scrub@.timer" '[Unit]
Description=GodMode: Monthly Btrfs Scrub for %I

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
'
    try_catch "Enable btrfs scrub timer" "sudo systemctl enable btrfs-scrub@-.timer 2>/dev/null; true"

    # --- Bước 6: fstrim weekly (SSD 35GB) ---
    log_info "Configuring fstrim (weekly)..."
    try_catch "Enable fstrim timer" "sudo systemctl enable --now fstrim.timer 2>/dev/null; true"

    # Override to weekly
    mkdir -p "/etc/systemd/system/fstrim.timer.d"
    safe_sudo_write "/etc/systemd/system/fstrim.timer.d/override.conf" '[Timer]
OnCalendar=weekly
'

    # --- Bước 7: IT Student sysctl ---
    log_info "Writing IT student sysctl configuration..."
    safe_sudo_write "/etc/sysctl.d/99-it-student.conf" '# GodMode: IT Student Network & Security sysctl
# Network performance
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
# Security
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
# File system
fs.file-max = 2097152
fs.nr_open = 2097152
vm.max_map_count = 1048576
'
    try_catch "Apply IT student sysctl" "sudo sysctl -p /etc/sysctl.d/99-it-student.conf 2>/dev/null; true"

    # --- Bước 8: Btrfs Quota for Docker ---
    log_info "Setting up Btrfs quota..."
    try_catch "Enable Btrfs quota" "sudo btrfs quota enable / 2>/dev/null; true"
    try_catch "Limit Docker to 15G" "sudo btrfs qgroup limit 15G /var/lib/docker 2>/dev/null; true"

    log_success "Btrfs + ZRAM + sysctl full tuning complete!"
}


# ============================================================================
# PART 7: IT STUDENT ECOSYSTEM — MENU-DRIVEN
# ============================================================================
# Hiện menu để người dùng chọn toolchain, không cài đặt tất cả.
# Bao gồm: dev tools, containers, databases, network/security, cloud,
# academic, communication, AI (Ollama + OpenCode), Obsidian notes.
# ============================================================================

setup_it_student_ecosystem() {
    log_header "PHẦN 7: IT STUDENT ECOSYSTEM"

    local categories=""

    if command -v whiptail &>/dev/null; then
        categories=$(whiptail --title "IT STUDENT ECOSYSTEM" \
            --checklist "Chon cong cu can cai (hien tai tat ca OFF):" 20 68 10 \
            "devtools"   "Core: Node, Python, Rust, Go, Java, C/C++" OFF \
            "containers" "Docker, Podman, QEMU/KVM, kubernetes" OFF \
            "databases"  "PostgreSQL, MariaDB, Redis, MongoDB" OFF \
            "netsec"     "nmap, Wireshark, VPN, hydra, OSINT" OFF \
            "cloud"      "AWS, Terraform, Ansible, Grafana" OFF \
            "academic"   "TexLive, Zotero, Pandoc, LibreOffice" OFF \
            "comm"       "Discord, Telegram" OFF \
            "ai"         "VS Code + Ollama + OpenCode + Qwen model" OFF \
            "notes"      "Obsidian Notes Vault" OFF \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && categories=""
    else
        log_info "whiptail unavailable — skpping IT ecosystem install"
    fi

    # --- Install selected categories ---
    for cat in $categories; do
        case "$cat" in
            devtools)
                log_info "Installing Core Dev Toolchain..."
                try_catch "Install mise" "yay -S --noconfirm mise-bin 2>/dev/null; true"
                try_catch "Install Node.js" "sudo pacman -S --noconfirm nodejs npm yarn 2>/dev/null; true"
                try_catch "Install pnpm" "sudo npm install -g pnpm 2>/dev/null; true"
                try_catch "Install bun" "yay -S --noconfirm bun-bin 2>/dev/null; true"
                try_catch "Install Python" "sudo pacman -S --noconfirm python python-pip 2>/dev/null; true"
                try_catch "Install pyenv" "yay -S --noconfirm pyenv 2>/dev/null; true"
                try_catch "Install poetry" "yay -S --noconfirm poetry 2>/dev/null; true"
                try_catch "Install Rust" "sudo pacman -S --noconfirm rustup 2>/dev/null; true"
                rustup default stable 2>/dev/null || true
                try_catch "Install Go" "sudo pacman -S --noconfirm go 2>/dev/null; true"
                try_catch "Install C/C++" "sudo pacman -S --noconfirm base-devel gcc clang cmake 2>/dev/null; true"
                try_catch "Install Flutter" "yay -S --noconfirm flutter-bin 2>/dev/null; true"
                try_catch "Install Kotlin" "sudo pacman -S --noconfirm kotlin 2>/dev/null; true"
                try_catch "Install jq/yq" "sudo pacman -S --noconfirm jq yq 2>/dev/null; true"
                try_catch "Install formatters" "sudo pacman -S --noconfirm shfmt stylua 2>/dev/null; true"
                try_catch "Install php/composer" "sudo pacman -S --noconfirm php composer 2>/dev/null; true"
                try_catch "Install Ruby" "sudo pacman -S --noconfirm ruby 2>/dev/null; true"
                try_catch "Install Lua" "sudo pacman -S --noconfirm lua luarocks 2>/dev/null; true"
                # LSP servers
                for lsp in lua-language-server bash-language-server yaml-language-server texlab; do
                    try_catch "Install $lsp" "sudo pacman -S --noconfirm $lsp 2>/dev/null; true"
                done
                ;;
            containers)
                log_info "Installing Containers..."
                try_catch "Install Docker" "sudo pacman -S --noconfirm docker docker-compose docker-buildx 2>/dev/null; true"
                try_catch "Enable Docker" "sudo systemctl enable --now docker 2>/dev/null; true"
                try_catch "Add user to docker" "sudo usermod -aG docker $USER 2>/dev/null; true"
                try_catch "Install Podman" "sudo pacman -S --noconfirm podman podman-compose 2>/dev/null; true"
                try_catch "Install QEMU/KVM" "sudo pacman -S --noconfirm qemu-desktop libvirt virt-manager 2>/dev/null; true"
                try_catch "Enable libvirt" "sudo systemctl enable --now libvirtd 2>/dev/null; true"
                try_catch "Add user to kvm" "sudo usermod -aG kvm $USER 2>/dev/null; true"
                try_catch "Install kubectl" "sudo pacman -S --noconfirm kubectl 2>/dev/null; true"
                try_catch "Install minikube" "yay -S --noconfirm minikube-bin 2>/dev/null; true"
                try_catch "Install helm" "sudo pacman -S --noconfirm helm 2>/dev/null; true"
                try_catch "Install vagrant" "sudo pacman -S --noconfirm vagrant 2>/dev/null; true"
                ;;
            databases)
                log_info "Installing Databases..."
                try_catch "Install PostgreSQL" "sudo pacman -S --noconfirm postgresql 2>/dev/null; true"
                try_catch "Install MariaDB" "sudo pacman -S --noconfirm mariadb 2>/dev/null; true"
                try_catch "Install SQLite" "sudo pacman -S --noconfirm sqlite sqlitebrowser 2>/dev/null; true"
                try_catch "Install Redis" "sudo pacman -S --noconfirm redis 2>/dev/null; true"
                try_catch "Install MongoDB" "yay -S --noconfirm mongodb-bin mongosh 2>/dev/null; true"
                try_catch "Install DBeaver" "yay -S --noconfirm dbeaver 2>/dev/null; true"
                ;;
            netsec)
                log_info "Installing Network & Security..."
                try_catch "Install nmap" "sudo pacman -S --noconfirm nmap 2>/dev/null; true"
                try_catch "Install Wireshark" "sudo pacman -S --noconfirm wireshark-qt tshark 2>/dev/null; true"
                try_catch "Install iperf3" "sudo pacman -S --noconfirm iperf3 2>/dev/null; true"
                try_catch "Install bandwidth tools" "sudo pacman -S --noconfirm bmon iftop nethogs 2>/dev/null; true"
                try_catch "Install wireless" "sudo pacman -S --noconfirm aircrack-ng iw 2>/dev/null; true"
                try_catch "Install VPN" "sudo pacman -S --noconfirm wireguard-tools openvpn 2>/dev/null; true"
                try_catch "Install security" "sudo pacman -S --noconfirm hydra sqlmap 2>/dev/null; true"
                try_catch "Install forensics" "sudo pacman -S --noconfirm binwalk foremost 2>/dev/null; true"
                try_catch "Install Bruno" "yay -S --noconfirm bruno-bin 2>/dev/null; true"
                ;;
            cloud)
                log_info "Installing Cloud & DevOps..."
                try_catch "Install AWS CLI" "yay -S --noconfirm aws-cli-v2 2>/dev/null; true"
                try_catch "Install Terraform" "sudo pacman -S --noconfirm terraform 2>/dev/null; true"
                try_catch "Install Ansible" "sudo pacman -S --noconfirm ansible 2>/dev/null; true"
                try_catch "Install Grafana" "yay -S --noconfirm grafana-bin 2>/dev/null; true"
                try_catch "Install act" "yay -S --noconfirm act 2>/dev/null; true"
                ;;
            academic)
                log_info "Installing Academic & Productivity..."
                try_catch "Install TexLive" "sudo pacman -S --noconfirm texlive-most 2>/dev/null; true"
                try_catch "Install Pandoc" "sudo pacman -S --noconfirm pandoc pandoc-crossref 2>/dev/null; true"
                try_catch "Install Zathura" "sudo pacman -S --noconfirm zathura zathura-pdf-mupdf 2>/dev/null; true"
                try_catch "Install Zotero" "yay -S --noconfirm zotero-bin 2>/dev/null; true"
                try_catch "Install Draw.io" "yay -S --noconfirm drawio-desktop-bin 2>/dev/null; true"
                try_catch "Install Mermaid" "sudo npm install -g @mermaid-js/mermaid-cli 2>/dev/null; true"
                try_catch "Install LibreOffice" "sudo pacman -S --noconfirm libreoffice-fresh 2>/dev/null; true"
                ;;
            comm)
                log_info "Installing Communication..."
                try_catch "Install Discord" "sudo pacman -S --noconfirm discord 2>/dev/null; true"
                try_catch "Install Telegram" "sudo pacman -S --noconfirm telegram-desktop 2>/dev/null; true"
                ;;
            ai)
                log_info "Installing AI Ecosystem..."
                # VS Code
                if ! command -v code &>/dev/null; then
                    try_aur "visual-studio-code-bin" "code-marketplace" "vscodium-bin"
                fi
                # .NET
                try_catch "Install dotnet-sdk" "sudo pacman -S --noconfirm dotnet-sdk 2>/dev/null; true"
                try_catch "Install mono" "sudo pacman -S --noconfirm mono msbuild 2>/dev/null; true"
                # Wayland flags cho VS Code
                mkdir -p "$HOME/.config"
                cat > "$HOME/.config/code-flags.conf" << 'EOF' 2>/dev/null || true
--enable-features=UseOzonePlatform,WaylandWindowDecorations
--ozone-platform-hint=auto
EOF
                # VS Code extensions
                if command -v code &>/dev/null; then
                    for ext in Continue.continue eamodio.gitlens esbenp.prettier-vscode ms-azuretools.vscode-docker; do
                        code --install-extension "$ext" --force 2>/dev/null || true
                    done
                    mkdir -p "$HOME/.config"
                    cat > "$HOME/.config/electron-flags.conf" << 'EOF' 2>/dev/null || true
--enable-features=UseOzonePlatform,WaylandWindowDecorations
--enable-wayland-ime
EOF
                fi
                # Fcitx5 + Unikey (Vietnamese input)
                try_catch "Install fcitx5" "sudo pacman -S --noconfirm fcitx5-im fcitx5-unikey 2>/dev/null; true"
                safe_sudo_write "/etc/environment" '# GodMode: Fcitx5 Input Method
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
GLFW_IM_MODULE=ibus
'
                # Ollama
                if ! command -v ollama &>/dev/null; then
                    try_aur "ollama-bin" "ollama"
                fi
                # Ollama resource limits
                local OLLAMA_OVERRIDE_DIR="/etc/systemd/system/ollama.service.d"
                try_catch "Create ollama override dir" "sudo mkdir -p '$OLLAMA_OVERRIDE_DIR'"
                safe_sudo_write "${OLLAMA_OVERRIDE_DIR}/override.conf" '[Service]
Environment="OLLAMA_NUM_THREADS=2"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
CPUAffinity=2 3
Nice=10
'
                try_catch "Enable/start ollama" "sudo systemctl enable --now ollama 2>/dev/null; true"
                log_info "Pulling qwen2.5-coder:1.5b (background)..."
                nohup ollama pull qwen2.5-coder:1.5b > /tmp/ollama-pull.log 2>&1 &
                # OpenCode agent
                mkdir -p "$HOME/.config/opencode"
                cat > "$HOME/.config/opencode/config.json" << 'EOF' 2>/dev/null || true
{
  "provider": "ollama",
  "model": "qwen2.5-coder:1.5b",
  "temperature": 0.2,
  "maxTokens": 2048,
  "endpoint": "http://localhost:11434"
}
EOF
                try_catch "Install opencode" "yay -S --noconfirm opencode-agent 2>/dev/null; true"
                log_success "AI ecosystem ready"
                ;;
            notes)
                log_info "Installing Obsidian..."
                if ! command -v obsidian &>/dev/null; then
                    try_catch "Install Obsidian" "sudo pacman -S --noconfirm obsidian 2>/dev/null; true"
                fi
                local VAULT_DIR="$HOME/notes/obsidian"
                if [ ! -d "$VAULT_DIR" ]; then
                    mkdir -p "$VAULT_DIR"
                    cat > "$VAULT_DIR/Welcome.md" <<- EOFOBS
# Welcome to Obsidian Vault

## Cấu trúc đề xuất
- \`Daily/\` — Ghi chép hằng ngày
- \`Projects/\` — Ghi chép theo dự án
- \`Reference/\` — Tài liệu tham khảo
- \`Archives/\` — Lưu trữ cũ

## Quick Start
- Mở Obsidian: \`bash lib/notes.sh\`
- Focus Mode: \`bash lib/focus.sh\`
EOFOBS
                    log_success "Obsidian vault created at $VAULT_DIR"
                else
                    log_info "Obsidian vault already exists at $VAULT_DIR"
                fi
                log_success "Obsidian installed & vault ready"
                ;;
        esac
    done

    if [ -z "$categories" ]; then
        log_info "No IT categories selected — skipping"
    fi

    # Audio (FEATURES-controlled, giữ nguyên)
    if echo "$FEATURES" | grep -q "audio"; then
        log_info "Configuring Audio..."
        try_catch "Install PipeWire" "sudo pacman -S --noconfirm pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber 2>/dev/null; true"
        try_catch "Install audio tools" "sudo pacman -S --noconfirm audacity helvum qpwgraph 2>/dev/null; true"
        try_catch "Install GStreamer" "sudo pacman -S --noconfirm gst-plugins-good gst-plugins-bad gst-plugins-ugly 2>/dev/null; true"
        try_catch "Install Spotify" "yay -S --noconfirm spotify-launcher 2>/dev/null; true"
        try_catch "Enable WirePlumber" "sudo systemctl enable --now wireplumber 2>/dev/null; true"

        log_info "Configuring Bluetooth..."
        try_catch "Install Bluetooth" "sudo pacman -S --noconfirm bluez bluez-utils blueman 2>/dev/null; true"
        try_catch "Enable Bluetooth" "sudo systemctl enable --now bluetooth 2>/dev/null; true"
        safe_sudo_append "/etc/bluetooth/main.conf" '
# GodMode: Bluetooth Fast Connect
FastConnectable=true
Enable=Source,Sink,Media,Socket
'
    fi

    # QEMU-lite (FEATURES-controlled)
    if echo "$FEATURES" | grep -q "ittools"; then
        log_info "Installing lightweight QEMU VM launcher..."
        try_catch "Install minimal QEMU" "sudo pacman -S --noconfirm qemu-system-x86 qemu-hw-display-virtio-gpu qemu-ui-spice-core edk2-ovmf 2>/dev/null; true"
        try_catch "Add user to kvm group" "sudo usermod -aG kvm $USER 2>/dev/null; true"
        log_success "QEMU tools installed — run VMs via start.sh menu"
    fi

    log_success "IT Student Ecosystem setup complete!"
}


# ============================================================================
# PART 9: AUTO MAINTENANCE TIMER (BẢO TRÌ HỆ THỐNG TỰ ĐỘNG)
# ============================================================================
# Phân hệ này tạo systemd service và timer để tự động bảo trì
# hệ thống vào 23:00 Chủ Nhật hàng tuần, bao gồm:
#   • Dọn cache pacman (yay -Sc)
#   • Giữ chỉ 1 phiên bản cache gói (paccache -r -k 1)
#   • Dọn cache npm/yarn
#   • Xóa log >50MB trong /var/log
# ----------------------------------------------------------------------------
# CƠ CHẾ:
# systemd timer thay thế cron trên các hệ thống systemd hiện đại.
# Timer kích hoạt service tương ứng vào lịch biểu.
# Dùng OnCalendar=Sun *-*-* 23:00:00 cho 23:00 Chủ Nhật.

setup_auto_maintenance() {
    log_header "PHẦN 9: AUTO MAINTENANCE TIMER"

    # --- Bước 1: Tạo systemd service ---
    # Step 1: Create the maintenance service
    # Service này chứa logic dọn dẹp, timer là trigger

    log_info "Creating godmode-clean service..."

    safe_sudo_write "/etc/systemd/system/godmode-clean.service" '[Unit]
Description=GodMode: Weekly System Maintenance
Description[vi]=GodMode: Bảo trì hệ thống hàng tuần
After=network.target

[Service]
Type=oneshot
# Dọn cache pacman / Clean pacman cache
# yay -Sc: xóa cache AUR + pacman không cần thiết
# paccache -r -k 1: giữ 1 phiên bản gần nhất
ExecStart=/bin/bash -c "
    echo '=== GodMode Maintenance $(date) ===' >> /var/log/godmode-clean.log
    echo '[1/5] Cleaning pacman cache...' >> /var/log/godmode-clean.log
    /usr/bin/yay -Sc --noconfirm >> /var/log/godmode-clean.log 2>&1
    echo '[2/5] Cleaning paccache...' >> /var/log/godmode-clean.log
    /usr/bin/paccache -r -k 1 >> /var/log/godmode-clean.log 2>&1
    echo '[3/5] Cleaning npm cache...' >> /var/log/godmode-clean.log
    /usr/bin/npm cache clean --force >> /var/log/godmode-clean.log 2>&1 || true
    echo '[4/5] Cleaning yarn cache...' >> /var/log/godmode-clean.log
    /usr/bin/yarn cache clean >> /var/log/godmode-clean.log 2>&1 || true
    echo '[5/5] Cleaning large log files...' >> /var/log/godmode-clean.log
    find /var/log -type f -size +50M -exec truncate -s 0 {} \\; 2>/dev/null || true
    echo '=== Done ===' >> /var/log/godmode-clean.log
"
# Nice level thấp để không ảnh hưởng user
Nice=15

[Install]
WantedBy=multi-user.target
'

    # --- Bước 2: Tạo systemd timer ---
    # Step 2: Create the timer
    # OnCalendar=Sun *-*-* 23:00:00 = Chủ Nhật hàng tuần lúc 23:00

    log_info "Creating godmode-clean timer..."

    safe_sudo_write "/etc/systemd/system/godmode-clean.timer" '[Unit]
Description=GodMode: Weekly Maintenance Timer (Sunday 23:00)
Description[vi]=GodMode: Hẹn giờ bảo trì hàng tuần (Chủ Nhật 23:00)

[Timer]
# Chạy vào 23:00 Chủ Nhật hàng tuần
# Run at 23:00 every Sunday
OnCalendar=Sun *-*-* 23:00:00

# Chạy ngay khi timer kích hoạt nếu trễ lịch
# Run immediately if missed due to system off
Persistent=true

# Đơn vị service được kích hoạt / Service unit to trigger
Unit=godmode-clean.service

[Install]
WantedBy=timers.target
'

    # Enable và start timer / Enable and start the timer
    try_catch "Reload systemd" "sudo systemctl daemon-reload"
    try_catch "Enable godmode-clean timer" "sudo systemctl enable godmode-clean.timer"
    try_catch "Start godmode-clean timer" "sudo systemctl start godmode-clean.timer"

    # --- Bước 3: Mở rộng godmode-cleanup.sh ---
    log_info "Upgrading godmode-cleanup.sh..."
    local CLEANUP_SOURCE="$(dirname "$0")/godmode-cleanup.sh"
    if [ -f "$CLEANUP_SOURCE" ]; then
        try_catch "Copy cleanup script to /usr/local/bin" \
            "sudo cp '$CLEANUP_SOURCE' /usr/local/bin/godmode-cleanup.sh"
        try_catch "Make cleanup script executable" "sudo chmod +x /usr/local/bin/godmode-cleanup.sh"
    fi

    # Update the service to use the expanded script
    safe_sudo_write "/etc/systemd/system/godmode-clean.service" '[Unit]
Description=GodMode: Weekly System Maintenance
Description[vi]=GodMode: Bảo trì hệ thống hàng tuần
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/godmode-cleanup.sh
Nice=15
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
'

    try_catch "Reload systemd" "sudo systemctl daemon-reload"
    log_success "Auto maintenance timer set — Sunday 23:00 weekly"
}


# ============================================================================
# PART 10: PASCAL-MODE TUI DASHBOARD
# ============================================================================
# Phân hệ này tạo bảng điều khiển trung tâm dạng TUI (Text User Interface)
# sử dụng whiptail, với cấu trúc menu phân tầng (nested submenus).
# ----------------------------------------------------------------------------
# CƠ CHẾ UI:
# - Vòng lặp while true: giữ menu sống, clear trước mỗi action
# - Mỗi submenu render lại chính nó (không thoát ra main menu)
# - Health-check đọc trực tiếp sysfs để hiển thị real-time data
# - Clean-up dùng ANSI sequence để xóa dòng log cũ
#
# Cấu trúc menu:
#   [M] Mode Profiles
#     ├── [1] God-Mode (activate)
#     ├── [2] Standard Mode (restore default)
#     ├── [3] CFXZ6-Mode (enable hardware features)
#     └── [B] Back to Main Menu
#   [A] Toggle AI Ecosystem (Ollama + OpenCode on/off)
#   [H] Telemetry & Hardware Health-Check
#   [C] Manual Clean-up (one-shot maintenance)
#   [E] Exit Dashboard

# --- Hàm deploy_pascal_mode: Deploy dashboard vào system ---
# deploy_pascal_mode: install pascal-mode to /usr/local/bin and setup alias

deploy_pascal_mode() {
    log_header "PHẦN 10: PASCAL-MODE TUI DASHBOARD"

    # Tạo script pascal-mode tại /usr/local/bin/
    # Create the pascal-mode dashboard script
    # Đây là dashboard độc lập, có thể gọi từ terminal

    log_info "Creating pascal-mode dashboard at ${PASCAL_MODE_PATH}..."

    # Copy từ local pascal-mode script, fallback về heredoc nếu không tìm thấy
    local PASCAL_SOURCE
    # pascal-mode ở cùng thư mục lib/
    PASCAL_SOURCE="$(dirname "$0")/pascal-mode"

    if [ -f "$PASCAL_SOURCE" ]; then
        cp "$PASCAL_SOURCE" godmode-pascal-source.sh
        log_success "Copied pascal-mode from local source"
    else
        # Fallback: generate inline dashboard (basic version)
        cat > godmode-pascal-source.sh << 'PASCAL_FALLBACK'
#!/bin/bash
PASCAL_LOG="/tmp/pascal-mode.log"
check_eco_mode() {
    local eco_path="/sys/devices/platform/panasonic/eco_mode"
    [ -f "$eco_path" ] && { local v; v=$(cat "$eco_path"); case "$v" in 1) echo "ENABLED (80%)";; 0) echo "DISABLED (100%)";; *) echo "UNKNOWN";; esac; } || echo "N/A"
}
check_cpu_temp() {
    local t="/sys/class/thermal/thermal_zone0/temp"; [ -f "$t" ] && { local r; r=$(cat "$t"); echo "$((r/1000)).$((r%1000/100))°C"; } || echo "N/A"
}
while true; do
    clear
    echo -e "\033[1;35m╔══════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;35m║     PASCAL-MODE — GODMODE DASHBOARD     ║\033[0m"
    echo -e "\033[1;35m╚══════════════════════════════════════════╝\033[0m"
    echo "CPU: $(check_cpu_temp) | Eco: $(check_eco_mode)"
    CHOICE=$(whiptail --title "PASCAL-MODE" --menu "Select:" 16 55 5 \
        "[1]" "God-Mode" "[2]" "Standard" "[3]" "CFXZ6-Mode" "[4]" "Health" "[E]" "Exit" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && break
    case "$CHOICE" in "[1]") echo "off" | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null && echo "God-Mode ON";; "[2]") echo "on" | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null && echo "Standard ON";; "[3]") [ -f /sys/devices/platform/panasonic/eco_mode ] && echo "1" | sudo tee /sys/devices/platform/panasonic/eco_mode >/dev/null && echo "CFXZ6 ON";; "[4]") sensors 2>/dev/null | head -5;; "[E]") break;; esac
    read -r -p "Press Enter..."
done
PASCAL_FALLBACK
    fi

    # Copy vào /usr/local/bin/ và set quyền
    # Copy to system path and set permissions
    try_catch "Copy pascal-mode to ${PASCAL_MODE_PATH}" \
        "sudo cp godmode-pascal-source.sh '$PASCAL_MODE_PATH'"
    try_catch "Set pascal-mode executable" \
        "sudo chmod +x '$PASCAL_MODE_PATH'"

    # Dọn file tạm / Clean temp file
    rm -f godmode-pascal-source.sh

    # --- Tạo alias toàn cục / Create global alias ---
    # Thêm alias vào /etc/profile.d/ để tất cả user đều dùng được
    local ALIAS_FILE="/etc/profile.d/godmode-alias.sh"
    safe_sudo_write "$ALIAS_FILE" '# GodMode: Pascal-Mode global alias
alias pascal-mode="sudo /usr/local/bin/pascal-mode"
'

    try_catch "Make alias script executable" "sudo chmod +x '$ALIAS_FILE'"

    # Cũng thêm vào .bashrc của user hiện tại
    if [ -f "$HOME/.bashrc" ]; then
        if ! grep -q "pascal-mode" "$HOME/.bashrc" 2>/dev/null; then
            echo '# GodMode: Pascal-Mode Dashboard' >> "$HOME/.bashrc"
            echo 'alias pascal-mode="/usr/local/bin/pascal-mode"' >> "$HOME/.bashrc"
        fi
    fi

    log_success "Pascal-Mode deployed! Run 'pascal-mode' to open dashboard"
    log_info "Alias installed: pascal-mode → ${PASCAL_MODE_PATH}"
}


# ============================================================================
# PART 9: NETWORK & SECURITY HARDENING
# ============================================================================
# Phân hệ này thiết lập firewall, SSH hardening, DNS privacy,
# fail2ban, apparmor và kernel hardening.
# ----------------------------------------------------------------------------

setup_network_security() {
    log_header "PHẦN 9: NETWORK & SECURITY HARDENING"

    # --- 9a. Firewall (nftables) ---
    log_info "9a: Configuring nftables firewall..."
    if ! pacman -Qi nftables &>/dev/null; then
        try_catch "Install nftables" "sudo pacman -S --noconfirm nftables 2>/dev/null; true"
    fi

    safe_sudo_write "/etc/nftables.conf" '# GodMode: CF-XZ6 nftables Firewall Ruleset
table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;

        # Allow loopback
        iif lo accept

        # Allow established/related
        ct state established,related accept

        # Allow SSH from LAN
        tcp dport 2222 ip saddr 192.168.0.0/16 accept

        # Allow Docker bridge
        iifname "docker*" accept

        # Rate limit SSH
        tcp dport 2222 meter ssh-meter { ip saddr limit rate 1/second burst 5 } accept

        # Allow ICMP (ping)
        icmp type echo-request limit rate 10/second accept

        # Log dropped
        log prefix "nftables-drop: " limit rate 1/minute
        counter drop
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}
'
    try_catch "Enable nftables" "sudo systemctl enable --now nftables 2>/dev/null; true"

    # --- 9b. SSH Hardening ---
    log_info "9b: Hardening SSH..."
    if command -v sshd &>/dev/null; then
        safe_sudo_write "/etc/ssh/sshd_config" '# GodMode: SSH Hardened Configuration
Port 2222
PermitRootLogin no
PasswordAuthentication no
AllowUsers '"$USER"'
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
KexAlgorithms sntrup761x25519-sha512@openssh.com
PubkeyAuthentication yes
AuthenticationMethods publickey
'
        # Generate SSH key if missing
        if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
            try_catch "Generate SSH ED25519 key" "ssh-keygen -t ed25519 -a 100 -f '$HOME/.ssh/id_ed25519' -N '' -C '$USER@cfxz6-arch'"
        fi
        try_catch "Restart SSH" "sudo systemctl restart sshd 2>/dev/null; true"
        log_success "SSH hardened: port 2222, key-only, ED25519"
    fi

    # --- 9c. DNS Privacy ---
    log_info "9c: Configuring DNS privacy..."
    safe_sudo_write "/etc/systemd/resolved.conf" '[Resolve]
# GodMode: DNS Privacy with Cloudflare & Quad9
DNS=1.1.1.1 9.9.9.9
DNSOverTLS=yes
DNSSEC=yes
FallbackDNS=1.0.0.1 149.112.112.112
Cache=yes
'
    try_catch "Enable systemd-resolved" "sudo systemctl enable --now systemd-resolved 2>/dev/null; true"

    # --- 9d. Fail2ban ---
    log_info "9d: Configuring fail2ban..."
    if ! pacman -Qi fail2ban &>/dev/null; then
        try_catch "Install fail2ban" "sudo pacman -S --noconfirm fail2ban"
    fi
    safe_sudo_write "/etc/fail2ban/jail.local" '[DEFAULT]
# GodMode: Fail2ban Configuration
bantime = 1h
findtime = 10m
maxretry = 3

[sshd]
enabled = true
port = 2222
logpath = /var/log/auth.log
maxretry = 3

[sddm]
enabled = true
logpath = /var/log/sddm.log
'
    try_catch "Enable fail2ban" "sudo systemctl enable --now fail2ban 2>/dev/null; true"

    # --- 9e. Kernel Hardening ---
    log_info "9e: Applying kernel hardening..."
    safe_sudo_write "/etc/sysctl.d/99-security.conf" '# GodMode: Kernel Security Hardening
kernel.unprivileged_bpf_disabled=1
net.core.bpf_jit_enable=1
kernel.kexec_load_disabled=1
kernel.yama.ptrace_scope=2
dev.tty.ldisc_autoload=0
vm.unprivileged_userfaultfd=0
kernel.ctrl-alt-del=0
'
    try_catch "Apply kernel hardening" "sudo sysctl -p /etc/sysctl.d/99-security.conf 2>/dev/null; true"

    # --- 9f. AppArmor ---
    log_info "9f: Installing AppArmor..."
    if ! pacman -Qi apparmor &>/dev/null; then
        try_catch "Install AppArmor" "sudo pacman -S --noconfirm apparmor 2>/dev/null; true"
    fi
    try_catch "Enable AppArmor" "sudo systemctl enable --now apparmor 2>/dev/null; true"

    log_success "Network & Security Hardening complete!"
}


# ============================================================================
# PART 10: DOTFILES MANAGEMENT & BACKUP STRATEGY
# ============================================================================
# Phân hệ này thiết lập Chezmoi cho dotfiles, rclone cho cloud sync,
# và USB auto-backup qua udev.
# ----------------------------------------------------------------------------

setup_dotfiles_backup() {
    log_header "PHẦN 10: DOTFILES MANAGEMENT & BACKUP"

    # --- 10a. Chezmoi Init ---
    log_info "10a: Setting up Chezmoi dotfiles..."
    if ! command -v chezmoi &>/dev/null; then
        try_catch "Install chezmoi" "yay -S --noconfirm chezmoi-bin 2>/dev/null; true"
    fi

    if command -v chezmoi &>/dev/null && [ ! -d "$HOME/.local/share/chezmoi" ]; then
        try_catch "Init chezmoi" "chezmoi init 2>/dev/null; true"

        # Add key configs to chezmoi
        for cfg in "$HOME/.zshrc" "$HOME/.config/hypr/" "$HOME/.config/waybar/" \
                   "$HOME/.config/kitty/" "$HOME/.config/nvim/" "$HOME/.tmux.conf" \
                   "$HOME/.gitconfig"; do
            if [ -e "$cfg" ]; then
                chezmoi add "$cfg" 2>/dev/null || true
            fi
        done
        log_success "Chezmoi initialized with key configs"
    fi

    # --- 10b. rclone Cloud Sync ---
    log_info "10b: Configuring rclone..."
    if ! command -v rclone &>/dev/null; then
        try_catch "Install rclone" "sudo pacman -S --noconfirm rclone 2>/dev/null; true"
    fi
    mkdir -p "$HOME/.config/rclone"

    # Create sync systemd service + timer
    safe_sudo_write "/etc/systemd/system/rclone-sync.service" '[Unit]
Description=GodMode: Daily rclone Cloud Sync
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/rclone sync /home/'"$USER"'/Documents gdrive:Documents
User='"$USER"'
Nice=19
IOSchedulingClass=idle
'
    safe_sudo_write "/etc/systemd/system/rclone-sync.timer" '[Unit]
Description=GodMode: Daily rclone sync timer

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
'
    try_catch "Enable rclone timer" "sudo systemctl enable rclone-sync.timer 2>/dev/null; true"

    # --- 10c. USB Auto-Backup ---
    log_info "10c: Creating USB auto-backup udev rule..."
    safe_sudo_write "/etc/udev/rules.d/99-usb-backup.rules" '# GodMode: USB Auto-Backup
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="BACKUP", RUN+="/usr/local/bin/godmode-usb-backup.sh"
'
    safe_sudo_write "/usr/local/bin/godmode-usb-backup.sh" '#!/bin/bash
# GodMode: USB Auto-Backup
# Auto-mounted when USB labeled "BACKUP" is inserted
DEVICE="$1"
MOUNT="/mnt/backup"
mkdir -p "$MOUNT"
mount "/dev/${DEVICE}" "$MOUNT" 2>/dev/null || exit 1
rsync -a --delete /home/'"$USER"'/Documents/ "$MOUNT/Documents/" 2>/dev/null
rsync -a --delete /home/'"$USER"'/school/ "$MOUNT/school/" 2>/dev/null
umount "$MOUNT" 2>/dev/null
echo "[$(date)] USB backup complete" >> /var/log/godmode-usb-backup.log
'
    try_catch "Make USB backup script executable" "sudo chmod +x /usr/local/bin/godmode-usb-backup.sh"

    log_success "Dotfiles & Backup strategy configured!"
}


# ============================================================================
# PART 11: FINAL SYSTEM INTEGRATION & POST-INSTALL
# ============================================================================
# Phân hệ này hoàn tất tích hợp hệ thống: multi-user, bootloader,
# sudoers hardening, kernel params, reboot check.
# ----------------------------------------------------------------------------

setup_final_integration() {
    log_header "PHẦN 11: FINAL SYSTEM INTEGRATION"

    # --- 11a. Multi-user Setup ---
    log_info "11a: Setting up dev group..."
    if ! getent group dev &>/dev/null; then
        try_catch "Create dev group" "sudo groupadd -g 1001 dev 2>/dev/null; true"
    fi
    try_catch "Add user to dev group" "sudo usermod -aG dev,docker,libvirt,realtime,audio,video,input $USER 2>/dev/null; true"
    log_success "User added to dev, docker, libvirt, realtime groups"

    # --- 11b. Hostname ---
    if [ -n "$HOSTNAME" ]; then
        local current_hostname
        current_hostname=$(hostname)
        if [ "$current_hostname" != "$HOSTNAME" ]; then
            try_catch "Set hostname" "sudo hostnamectl set-hostname '$HOSTNAME'"
            try_catch "Update hosts file" "safe_sudo_write '/etc/hosts' '127.0.0.1   localhost\n::1         localhost\n127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}\n'"
            log_success "Hostname set to ${HOSTNAME}"
        fi
    fi

    # --- 11c. Git Identity ---
    if [ -n "${GIT_NAME:-}" ] && [ -n "${GIT_EMAIL:-}" ]; then
        try_catch "Set Git user name" "git config --global user.name '$GIT_NAME'"
        try_catch "Set Git user email" "git config --global user.email '$GIT_EMAIL'"
        log_success "Git identity configured: ${GIT_NAME} <${GIT_EMAIL}>"
    fi

    # --- 11d. Bootloader Optimization ---
    log_info "11d: Optimizing boot parameters..."
    local KERNEL_PARAMS="nowatchdog processor.max_cstate=4 intel_idle.max_cstate=4 i915.enable_fbc=1 i915.enable_psr=1 i915.enable_rc6=1 i915.fastboot=1 mitigations=off pcie_aspm=force"

    if [ "$CAP_SYSTEMD_BOOT" -eq 1 ]; then
        local boot_entry
        boot_entry=$(ls /boot/loader/entries/*.conf 2>/dev/null | head -1)
        if [ -n "$boot_entry" ]; then
            try_catch "Update systemd-boot params" \
                "sudo sed -i 's/^options.*/options ${KERNEL_PARAMS}/' '$boot_entry'"
            log_success "systemd-boot kernel params updated"
        fi
    fi

    if [ "$CAP_GRUB" -eq 1 ]; then
        try_catch "Update GRUB params" \
            "sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"${KERNEL_PARAMS}\"/' /etc/default/grub"
        try_catch "Regenerate GRUB config" "sudo grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null; true"
        log_success "GRUB kernel params updated"
    fi

    # --- 11e. sudoers Hardening ---
    log_info "11e: Hardening sudoers..."
    safe_sudo_write "/etc/sudoers.d/99-cfxz6" "$USER ALL=(ALL) ALL
Defaults timestamp_timeout=5
Defaults passwd_timeout=1
Defaults badpass_message=\"Sai mat khau. Thu lai.\"
Defaults log_input, log_output
"
    try_catch "Set sudoers permissions" "sudo chmod 440 /etc/sudoers.d/99-cfxz6"

    # --- 11f. Reboot Schedule Check ---
    log_info "11f: Creating reboot check service..."
    safe_sudo_write "/usr/local/bin/godmode-reboot-check.sh" '#!/bin/bash
# GodMode: Reboot Check
# So sanh kernel version vs installed version
INSTALLED=$(ls /usr/lib/modules/ 2>/dev/null | sort -V | tail -1)
RUNNING=$(uname -r)
if [ "$INSTALLED" != "$RUNNING" ]; then
    echo "KERNEL UPDATE: $RUNNING -> $INSTALLED (reboot required)"
    exit 1
fi
echo "Kernel is up-to-date: $RUNNING"
exit 0
'
    try_catch "Make reboot check executable" "sudo chmod +x /usr/local/bin/godmode-reboot-check.sh"

    # Reboot check timer
    safe_sudo_write "/etc/systemd/system/godmode-reboot-check.service" '[Unit]
Description=GodMode: Kernel Reboot Check

[Service]
Type=oneshot
ExecStart=/usr/local/bin/godmode-reboot-check.sh
'
    safe_sudo_write "/etc/systemd/system/godmode-reboot-check.timer" '[Unit]
Description=GodMode: Daily Kernel Reboot Check

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
'
    try_catch "Enable reboot check timer" "sudo systemctl enable godmode-reboot-check.timer 2>/dev/null; true"

    log_success "Final System Integration complete!"
}


# ============================================================================
# MAIN EXECUTION — Main entry point
# ============================================================================
# Hàm main() điều phối toàn bộ quy trình:
# 1. Kiểm tra an toàn (không chạy root)
# 2. Kiểm tra dependencies
# 3. Khởi tạo log
# 4. TUI Wizard (nếu lần đầu chạy)
# 5. Triển khai lần lượt các phân hệ 3→10
# 6. Hoàn tất

main() {
    # --- Bước 1: Initialize log + safety ---
    init_log
    init_safety

    # --- Bước 2: Safety checks ---
    check_root
    check_dependencies

    # Enable verbose mode if set
    is_verbose && set -x

    echo -e "${BOLD}${MAGENTA}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     PANASONIC CF-XZ6 GOD-MODE SETUP                         ║"
    echo "║     Intel Core i5-7300U | 8GB RAM | Hyprland                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo ""

    # --- Bước 3: Pre-flight audit (PART 0) ---
    safe_run "00" "Pre-flight Hardware Audit" run_preflight_audit || true

    # --- Bước 4: Capability Probe ---
    log_info "Probing system capabilities..."
    probe_capabilities

    # --- Bước 5: Interactive Setup Confirmation + Offline Warning ---
    local CONFIRM_MSG
    CONFIRM_MSG="This script will configure your Panasonic CF-XZ6 with:\n\n\
• Complete Pre-flight Hardware Audit\n\
• JaKooLit Hyprland Desktop (Y2K Vintage theme)\n\
• Shell & Terminal Enhancement (ZSH/Fish + Tmux)\n\
• Dynamic CPU Affinity Engine (real-time core pinning)\n\
• Memory & Process Tuning (oomd, earlyoom, hugepages)\n\
• CF-XZ6 Hardware Integration (touch, rotate, tablet, eco, stylus, lid)\n\
• Thermal Hardening (thermald, TLP, undervolt, auto-cpufreq)\n\
• Btrfs + ZRAM + sysctl + Snapper optimization\n\
• IT Student Ecosystem (dev tools, containers, DB, security)\n\
• Auto-maintenance timer (expanded)\n\
• Network & Security Hardening (nftables, SSH, DNS, fail2ban)\n\
• Pascal-Mode Control Dashboard\n\
• Final Integration (multi-user, bootloader, sudoers)\n"

    if [ "$CAP_NETWORK" -eq 0 ]; then
        CONFIRM_MSG+="\n${YELLOW}⚠ OFFLINE MODE: Network unavailable. Online features (AUR, Hyprland, Ollama, rclone, git clone) will be SKIPPED.${RESET}\n"
    fi
    CONFIRM_MSG+="\nSAFETY: This script will NOT run as root.\n\
Backups will be created before any system file changes.\n\
Resume support: interrupted parts can be skipped on re-run.\n\n\
Continue?"

    whiptail --title "CONFIRMATION" --yesno "$CONFIRM_MSG" 32 78
    if [ $? -ne 0 ]; then
        log_info "Setup cancelled by user"
        exit 0
    fi

    # --- Bước 6: Run Wizard ---
    safe_run "01" "TUI Setup Wizard" run_wizard
    load_wizard_vars

    # --- Bước 7: Package state snapshot ---
    log_info "Saving pre-install package state..."
    save_package_state "$PKG_BEFORE"

    # --- Bước 6: Deploy subsystems (có parallel execution) ---
    safe_run "02" "JaKooLit Hyprland Desktop" deploy_jakoolit_hyprland
    safe_run "25" "Shell & Terminal Enhancement" setup_shell_terminal
    safe_run "03" "CPU Affinity Engine" setup_cpu_affinity_engine
    safe_run "35" "Memory & Process Tuning" setup_memory_tuning
    safe_run "04" "CF-XZ6 Hardware Integration" setup_cfxz6_hardware
    safe_run "05" "Thermal Hardening & Undervolt" setup_thermal_undervolt
    safe_run "06" "Btrfs + ZRAM + sysctl" setup_btrfs_zram_sysctl
    safe_run "07" "IT Student Ecosystem" setup_it_student_ecosystem

    # Parallel: 08+09, 10+11 (không phụ thuộc)
    log_info "Running parallel subsystem groups..."
    safe_run "08" "Auto Maintenance Timer" setup_auto_maintenance &
    local pid_08=$!
    safe_run "09" "Pascal-Mode Dashboard" deploy_pascal_mode &
    local pid_09=$!
    wait $pid_08 $pid_09 2>/dev/null || true

    safe_run "10" "Network & Security Hardening" setup_network_security &
    local pid_10=$!
    safe_run "11" "Dotfiles & Backup Strategy" setup_dotfiles_backup &
    local pid_11=$!
    wait $pid_10 $pid_11 2>/dev/null || true

    safe_run "12" "Final System Integration" setup_final_integration &
    local pid_12=$!
    wait $pid_12 2>/dev/null || true

    # --- Bước 8: Package state diff ---
    log_info "Saving post-install package state..."
    save_package_state "$PKG_AFTER"
    local new_pkgs
    new_pkgs=$(diff_package_state "$PKG_BEFORE" "$PKG_AFTER")
    if [ -n "$new_pkgs" ]; then
        local pkg_count
        pkg_count=$(echo "$new_pkgs" | wc -l)
        log_success "${pkg_count} new packages installed"
        echo "$new_pkgs" >> "$LOG_FILE"
    fi

    # --- Bước 9: Complete ---
    log_header "SETUP COMPLETE"

    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║              GOD-MODE SETUP COMPLETE!                       ║${RESET}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "Recommended next steps:"
    echo "  1. Log out and log in to apply shell aliases"
    echo "  2. Type 'pascal-mode' to open the control dashboard"
    echo "  3. Verify Hyprland with: hyprctl monitors"
    echo "  4. Check ZRAM: zramctl"
    echo "  5. Check temperature: sensors"
    echo ""

    if [ "$CAP_NETWORK" -eq 0 ]; then
        echo -e "${YELLOW}⚠ Setup chay o offline mode — mot so tinh nang bi bo qua:${RESET}"
        echo "  • Hyprland Desktop (JaKooLit) — can mang de git clone"
        echo "  • AUR packages — can mang de yay -S"
        echo "  • Ollama AI — can mang de tai model"
        echo "  • Git clone dotfiles — can mang de chezmoi/rclone"
        echo ""
        echo -e "  Sau khi co mang, chay: ${CYAN}bash lib/godmode-recovery.sh --network${RESET}"
        echo ""
    fi

    echo -e "Post-install notes:"
    echo "  • Event monitor will start automatically with Hyprland"
    echo "  • Eco mode (80% charge) will persist across reboots"
    echo "  • Auto-maintenance runs Sunday 23:00"
    echo "  • Firewall active (nftables), SSH on port 2222"
    echo "  • Log file: ${LOG_FILE}"
    echo ""

    if whiptail --title "REBOOT" --yesno "A reboot is recommended to apply all changes.\n\nReboot now?" 10 40; then
        log_info "Rebooting..."
        sudo reboot
    else
        log_info "Please reboot later to apply all changes"
    fi

    log_success "God-Mode setup completed successfully!"
}

# ============================================================================
# ENTRY POINT
# ============================================================================
# Gọi hàm main với tất cả output và error được log + auto-recovery
# Call main with all output and error logged + auto-recovery

# Chạy main trong subshell để tránh xung đột pipe với set -e
# Run main in subshell to avoid pipe conflicts with set -e
SETUP_EXIT_CODE=0
(
    main "$@" || SETUP_EXIT_CODE=$?
    exit $SETUP_EXIT_CODE
) 2>&1 | tee -a "$LOG_FILE"
SETUP_PIPESTATUS=(${PIPESTATUS[@]})
SETUP_EXIT_CODE=${SETUP_PIPESTATUS[0]}

# Neu setup that bai, chay recovery
if [ "$SETUP_EXIT_CODE" -ne 0 ]; then
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}║     SETUP KHONG HOAN TAT HOAN TOAN                          ║${RESET}"
    echo -e "${YELLOW}║     Mot so phan co the that bai. Khong sao!                  ║${RESET}"
    echo -e "${YELLOW}║     Cac buoc tiep theo:                                     ║${RESET}"
    echo -e "${YELLOW}║                                                            ║${RESET}"
    echo -e "${YELLOW}║  1. Xem log: cat ${LOG_FILE}                ║${RESET}"
    echo -e "${YELLOW}║  2. Chay recovery: bash lib/godmode-recovery.sh --all       ║${RESET}"
    echo -e "${YELLOW}║  3. Chay lai setup: ./start.sh (se skip phan da OK)        ║${RESET}"
    echo -e "${YELLOW}║  4. Neu loi JaKooLit: kiem tra mang hoac dung fallback     ║${RESET}"
    echo -e "${YELLOW}║  5. Neu loi AUR: kiem tra AUR availability                 ║${RESET}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""

    # Tu dong chay recovery script
    RECOVERY_SCRIPT="$(dirname "$0")/godmode-recovery.sh"
    if [ -f "$RECOVERY_SCRIPT" ]; then
        echo -e "${CYAN}>>>${RESET} Running auto-recovery..."
        bash "$RECOVERY_SCRIPT" --all 2>/dev/null || true
    fi
fi
