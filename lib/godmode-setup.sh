#!/bin/bash
# ============================================================================
# GODMODE-SETUP.SH — Guided first-boot setup (checklist TUI)
# ----------------------------------------------------------------------------
# Cac buoc: yay / hyprland / zram / undervolt / thermal / supermode / tweaks
# / ananicy-cpp. Idempotent, co the chay lai nhieu lan (state theo step).
# Goi tu: .bash_login (first boot) hoac `bash start.sh` -> G.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../calarch.conf"
source "$SCRIPT_DIR/config-load.sh"
calarch_load_config "$CONFIG_FILE"

R='\033[0m'; B='\033[1m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'

LOG_FILE="/tmp/godmode-setup.log"
STATE_DIR="/var/lib/godmode"
STATE_FILE="$STATE_DIR/godmode-steps.done"
# fallback khi chay user thuong (khong ghi duoc /var/lib)
if [ ! -w "$STATE_DIR" ] 2>/dev/null; then
    STATE_DIR="$HOME/.config/calarch"
    STATE_FILE="$STATE_DIR/godmode-steps.done"
fi
mkdir -p "$STATE_DIR" 2>/dev/null || true
touch "$STATE_FILE" 2>/dev/null || true

log_i()  { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_w()  { echo -e "${YEL}[!!]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }
has()    { command -v "$1" &>/dev/null; }

step_done() { grep -qx "$1" "$STATE_FILE" 2>/dev/null; }
step_mark() { echo "$1" >> "$STATE_FILE" 2>/dev/null || true; }

run_step() {
    local name="$1" label="$2" func="$3"
    if step_done "$name"; then
        log_ok "${label} — da lam truoc do (skip)"
        return 0
    fi
    echo "" >> "$LOG_FILE"
    echo "=== ${label} ($(date '+%H:%M:%S')) ===" >> "$LOG_FILE"
    if "$func"; then
        step_mark "$name"
        log_ok "${label} — XONG"
        return 0
    else
        log_w "${label} — THAT BAI (xem ${LOG_FILE}, chay lai de thu)"
        return 1
    fi
}

# --- 1. AUR helper ---
step_yay() {
    has yay && return 0
    if has paru; then
        echo 'alias yay=paru' >> "$HOME/.bashrc" 2>/dev/null || true
        return 0
    fi
    sudo pacman -S --noconfirm --needed base-devel git 2>/dev/null || true
    local tmpdir
    tmpdir=$(mktemp -d)
    if ! ( cd "$tmpdir" && git clone --depth=1 https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si --noconfirm ) 2>/dev/null; then
        rm -rf "$tmpdir"
        return 1
    fi
    rm -rf "$tmpdir"
    has yay
}

# --- 2. Desktop Hyprland (JaKooLit fork duy tri) ---
step_hyprland() {
    has hyprland && return 0
    [ -d "$HOME/Arch-Hyprland" ] || git clone --depth=1 https://github.com/LinuxBeginnings/Arch-Hyprland.git "$HOME/Arch-Hyprland" 2>/dev/null || return 1
    cat << EOF

${B}${CY}══════════ HUONG DAN CAI DESKTOP HYPRLAND (JaKooLit) ══════════${R}
  Trinh cai se hoi vai cau hoi (tieng Anh) — chon theo goi y:

  • GPU          : chon ${B}Intel${R} (khong chon nvidia)
  • DE/WM        : chon ${B}Hyprland${R}
  • Display mgr  : chon ${B}SDDM${R} (boot vao GUI tu dong)
  • Cac tuy chon khac : co the Enter mac dinh

  Sau khi xong, calarch se tu them CPU-affinity autostart
  va tiep tuc cac buoc con lai.
${B}${CY}════════════════════════════════════════════════════════════════${R}
EOF
    echo -n "Nhan Enter de chay JaKooLit installer (tuong tac)... "
    read -r
    if ! ( cd "$HOME/Arch-Hyprland" && chmod +x install.sh && ./install.sh ); then
        return 1
    fi
    local conf="$HOME/.config/hypr/hyprland.conf"
    chmod +x "$SCRIPT_DIR/hyprland-event-monitor.sh" 2>/dev/null || true
    if [ -f "$conf" ] && ! grep -q "hyprland-event-monitor" "$conf" 2>/dev/null; then
        echo "exec-once = ${SCRIPT_DIR}/hyprland-event-monitor.sh" >> "$conf"
    fi
    has hyprland
}

# --- 3. ZRAM 8GB + sysctl ---
step_zram() {
    sudo pacman -S --noconfirm zram-generator 2>/dev/null || true
    if [ ! -f /etc/systemd/zram-generator.conf ]; then
        printf '[zram0]\nzram-size = 8192\ncompression-algorithm = zstd\n' | sudo tee /etc/systemd/zram-generator.conf >/dev/null
    fi
    sudo systemctl enable systemd-zram-setup@zram0.service 2>/dev/null || true
    local sctl="/etc/sysctl.d/99-calarch.conf"
    [ -f "$sctl" ] || printf '# calarch zram tuning\n' | sudo tee "$sctl" >/dev/null
    grep -q "^vm.swappiness" "$sctl" 2>/dev/null || echo "vm.swappiness=180" | sudo tee -a "$sctl" >/dev/null
    grep -q "^vm.page-cluster" "$sctl" 2>/dev/null || echo "vm.page-cluster=0" | sudo tee -a "$sctl" >/dev/null
    sudo sysctl --system >/dev/null 2>&1 || true
    return 0
}

# --- 4. Undervolt (intel-undervolt) ---
step_undervolt() {
    if ! has intel-undervolt; then
        has yay || return 1
        yay -S --noconfirm intel-undervolt 2>/dev/null || return 1
    fi
    echo "msr.allow_writes=on" | sudo tee /etc/modprobe.d/msr.conf >/dev/null 2>&1 || true
    sudo modprobe msr 2>/dev/null || true
    local conf="/etc/intel-undervolt.conf"
    [ -f "$conf" ] || { echo "enable no" | sudo tee "$conf" >/dev/null; }
    local cpu="${UNDERVOLT_CPU:--50}" gpu="${UNDERVOLT_GPU:--20}" cache="${UNDERVOLT_CACHE:--50}"
    sudo sed -i "s/^undervolt 0 .*/undervolt 0 'CPU' ${cpu}/" "$conf"
    sudo sed -i "s/^undervolt 1 .*/undervolt 1 'GPU' ${gpu}/" "$conf"
    sudo sed -i "s/^undervolt 2 .*/undervolt 2 'CPU Cache' ${cache}/" "$conf"
    sudo intel-undervolt apply 2>/dev/null || true
    sudo systemctl enable intel-undervolt.service 2>/dev/null || true
    has intel-undervolt
}

# --- 5. Thermal (thermald + TLP) ---
step_thermal() {
    sudo pacman -S --noconfirm thermald tlp tlp-rdw 2>/dev/null || true
    sudo systemctl enable --now thermald 2>/dev/null || true
    sudo systemctl enable --now tlp 2>/dev/null || true
    return 0
}

# --- 6. Super Mode daemon + eco ---
step_supermode() {
    local unit="/etc/systemd/system/super-mode.service"
    if [ ! -f "$unit" ]; then
        printf '[Unit]\nDescription=calarch Super Mode daemon (COOL/HOT governor)\nAfter=multi-user.target\n\n[Service]\nType=simple\nExecStart=/bin/bash %s/super-mode.sh\nRestart=always\nRestartSec=10\n\n[Install]\nWantedBy=multi-user.target\n' "$SCRIPT_DIR" | sudo tee "$unit" >/dev/null
        sudo systemctl daemon-reload 2>/dev/null || true
    fi
    sudo systemctl enable super-mode.service 2>/dev/null || true
    sudo modprobe panasonic_laptop 2>/dev/null || true
    printf 'panasonic_laptop\n' | sudo tee /etc/modules-load.d/panasonic.conf >/dev/null 2>&1 || true
    if [ -f /sys/devices/platform/panasonic/eco_mode ]; then
        echo 1 | sudo tee /sys/devices/platform/panasonic/eco_mode >/dev/null 2>&1 || true
    fi
    return 0
}

# --- 7. Tinh chinh he thong (pacman + reflector + journal) ---
step_tweaks() {
    local pacconf="/etc/pacman.conf"
    grep -q "^ParallelDownloads" "$pacconf" 2>/dev/null || sudo sed -i "s/^#ParallelDownloads.*/ParallelDownloads = 5/" "$pacconf" 2>/dev/null || true
    grep -q "^ParallelDownloads" "$pacconf" 2>/dev/null || echo "ParallelDownloads = 5" | sudo tee -a "$pacconf" >/dev/null
    grep -q "^Color" "$pacconf" 2>/dev/null || sudo sed -i "s/^#Color/Color/" "$pacconf" 2>/dev/null || true
    grep -q "^VerbosePkgLists" "$pacconf" 2>/dev/null || sudo sed -i "s/^#VerbosePkgLists/VerbosePkgLists/" "$pacconf" 2>/dev/null || true
    sudo pacman -S --noconfirm reflector 2>/dev/null || true
    sudo systemctl enable reflector.timer 2>/dev/null || true
    local jconf="/etc/systemd/journald.conf"
    grep -q "^SystemMaxUse" "$jconf" 2>/dev/null || echo "SystemMaxUse=100M" | sudo tee -a "$jconf" >/dev/null

    # Wire godmode auto-maintenance (service + timer + scripts)
    if [ -f "$SCRIPT_DIR/godmode-cleanup.sh" ]; then
        sudo install -m 755 "$SCRIPT_DIR/godmode-cleanup.sh" /usr/local/bin/godmode-cleanup.sh 2>/dev/null || true
    fi
    if [ -f "$SCRIPT_DIR/godmode-recovery.sh" ]; then
        sudo install -m 755 "$SCRIPT_DIR/godmode-recovery.sh" /usr/local/bin/godmode-recovery.sh 2>/dev/null || true
    fi
    if [ -f "$SCRIPT_DIR/godmode-clean.service" ] && [ -f "$SCRIPT_DIR/godmode-clean.timer" ]; then
        sudo install -m 644 "$SCRIPT_DIR/godmode-clean.service" /etc/systemd/system/godmode-clean.service 2>/dev/null || true
        sudo install -m 644 "$SCRIPT_DIR/godmode-clean.timer" /etc/systemd/system/godmode-clean.timer 2>/dev/null || true
        sudo systemctl daemon-reload 2>/dev/null || true
        sudo systemctl enable godmode-clean.timer 2>/dev/null || true
    fi
    # Ollama drop-in (gioi han CPU/memory neu co ollama)
    if [ -f "$SCRIPT_DIR/ollama-override.conf" ]; then
        sudo mkdir -p /etc/systemd/system/ollama.service.d 2>/dev/null || true
        sudo install -m 644 "$SCRIPT_DIR/ollama-override.conf" /etc/systemd/system/ollama.service.d/ollama-override.conf 2>/dev/null || true
        sudo systemctl daemon-reload 2>/dev/null || true
        if systemctl is-active ollama &>/dev/null; then
            sudo systemctl restart ollama 2>/dev/null || true
        fi
    fi
    return 0
}

# --- 8. ananicy-cpp (nang cao) ---
step_ananicy() {
    has ananicy-cpp && return 0
    has yay || return 1
    yay -S --noconfirm ananicy-cpp 2>/dev/null || return 1
    sudo systemctl enable --now ananicy-cpp.service 2>/dev/null || true
    has ananicy-cpp
}

menu() {
    if has gum; then
        log_i "Chon cac buoc God-Mode (SPACE bo/chon, Enter de chay):"
        log_i "  yay=AUR helper  hyprland=Desktop Hyprland  zram=ZRAM+sysctl"
        log_i "  undervolt=intel-undervolt  thermal=thermald+TLP  supermode=daemon+eco"
        log_i "  tweaks=pacman+mirror+journal  ananicy=ananicy-cpp (nang cao)"
        echo ""
        gum choose --no-limit --header "God-Mode Setup — chon cac buoc:" \
            --selected "yay,hyprland,zram,undervolt,thermal,supermode,tweaks" \
            yay hyprland zram undervolt thermal supermode tweaks ananicy
    else
        echo "yay hyprland zram undervolt thermal supermode tweaks"
    fi
}

main() {
    local sel
    sel=$(menu || true)
    [ -z "$sel" ] && { log_w "Khong chon buoc nao — thoat"; return 0; }
    echo "" >> "$LOG_FILE"
    echo "=== GodMode Setup bat dau ($(date '+%Y-%m-%d %H:%M:%S')) ===" >> "$LOG_FILE"
    local item fail=0
    for item in $sel; do
        case "$item" in
            yay)       run_step yay "AUR helper (yay)" step_yay || fail=1 ;;
            hyprland)  run_step hyprland "Desktop Hyprland (JaKooLit)" step_hyprland || fail=1 ;;
            zram)      run_step zram "ZRAM 8GB + sysctl" step_zram || fail=1 ;;
            undervolt) run_step undervolt "intel-undervolt" step_undervolt || fail=1 ;;
            thermal)   run_step thermal "thermald + TLP" step_thermal || fail=1 ;;
            supermode) run_step supermode "Super Mode daemon + eco" step_supermode || fail=1 ;;
            tweaks)    run_step tweaks "Tinh chinh he thong" step_tweaks || fail=1 ;;
            ananicy)   run_step ananicy "ananicy-cpp" step_ananicy || fail=1 ;;
        esac
    done
    echo ""
    if [ "$fail" -eq 0 ]; then
        log_ok "God-Mode Setup hoan tat. Log: ${LOG_FILE}"
        log_ok "Reboot de ap dung day du (sddm/GUI, zram, daemon): sudo reboot"
    else
        log_w "God-Mode Setup co buoc THAT BAI. Log: ${LOG_FILE}"
        log_w "Chay lai sau khi xu ly: bash ~/calarch/lib/godmode-setup.sh"
    fi
    return "$fail"
}

main "$@"
