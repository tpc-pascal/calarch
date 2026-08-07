#!/bin/bash
# ============================================================================
# GODMODE-RECOVERY.SH — Recovery & Fallback Handler (Capability-Aware)
# ----------------------------------------------------------------------------
# Xu ly cac truong hop that bai: retry, rollback, alternative package,
# module loading, network recovery. Tu dong load capability flags tu
# /tmp/godmode-capabilities.sh neu co.
# ============================================================================
set -uo pipefail

LOG_FILE="/tmp/godmode-recovery.log"
REPORT_FILE="/tmp/godmode-recovery-report.txt"
CAP_FILE="/tmp/godmode-capabilities.sh"
PKG_BEFORE="/tmp/godmode-pkg-before.txt"
PKG_AFTER="/tmp/godmode-pkg-after.txt"
echo "=== GodMode Recovery $(date) ===" > "$LOG_FILE"

CYAN='\033[0;36m'; RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; NC='\033[0m'

log_i() { echo -e "${CYAN}>>>${NC} $*" | tee -a "$LOG_FILE"; }

# --- Load capability flags (neu co) ---
load_caps() {
    if [ -f "$CAP_FILE" ]; then
        # An toan: /tmp world-writable — chi source file do chinh user so huu
        # va khong co group/other write bit (tranh RCE khi chay root).
        local owner_id uid_val
        owner_id=$(stat -c '%u' "$CAP_FILE" 2>/dev/null || echo "-1")
        uid_val=$(id -u 2>/dev/null || echo "-1")
        if [ "$owner_id" = "$uid_val" ] && ! find "$CAP_FILE" -perm /022 -print -quit 2>/dev/null | grep -q .; then
            source "$CAP_FILE"
            log_i "Loaded capability flags from ${CAP_FILE}"
        else
            log_i "Capability file ${CAP_FILE} khong an toan (owner=${owner_id}) — bo qua, probing..."
            CAP_NETWORK=0
            ping -c 2 -W 3 archlinux.org &>/dev/null && CAP_NETWORK=1
        fi
    else
        log_i "No capability file found — probing..."
        CAP_NETWORK=0
        ping -c 2 -W 3 archlinux.org &>/dev/null && CAP_NETWORK=1
    fi
}

# --- Network Recovery ---
recover_network() {
    log_i "Checking network connectivity..."
    if ping -c 2 -W 3 archlinux.org &>/dev/null; then
        echo "OK" >> "$REPORT_FILE"
        return 0
    fi
    log_i "Network down. Attempting recovery..."
    for svc in NetworkManager systemd-networkd wpa_supplicant iwd; do
        sudo systemctl start "$svc" 2>/dev/null || true
    done
    sleep 4
    if ping -c 2 -W 3 archlinux.org &>/dev/null; then
        log_i "Network recovered"
        echo "OK (recovered)" >> "$REPORT_FILE"
        return 0
    fi
    log_i "Network still down. Check: sudo iwctl station wlan0 connect SSID"
    echo "FAIL" >> "$REPORT_FILE"
    return 1
}

# --- AUR Recovery ---
recover_aur() {
    log_i "Checking AUR helper..."
    if command -v yay &>/dev/null; then
        log_i "yay is available"
        echo "OK" >> "$REPORT_FILE"
        return 0
    fi
    if command -v paru &>/dev/null; then
        log_i "paru found — creating yay alias"
        if ! grep -qF "alias yay=paru" "$HOME/.bashrc" 2>/dev/null; then
            echo 'alias yay=paru' >> "$HOME/.bashrc"
        fi
        alias yay=paru
        echo "OK (paru)" >> "$REPORT_FILE"
        return 0
    fi
    [ "$CAP_NETWORK" -eq 0 ] && { log_i "Offline — cannot install AUR helper"; echo "SKIP (offline)" >> "$REPORT_FILE"; return 1; }
    log_i "No AUR helper. Installing yay-bin..."
    local tmpdir
    tmpdir=$(mktemp -d) || return 1
    if ! cd "$tmpdir" 2>/dev/null; then rm -rf "$tmpdir"; return 1; fi
    sudo pacman -S --noconfirm --needed base-devel git 2>/dev/null || true
    if ! git clone --depth=1 https://aur.archlinux.org/yay-bin.git 2>/dev/null; then
        cd ~ 2>/dev/null && rm -rf "$tmpdir"
        return 1
    fi
    if ! (cd yay-bin && makepkg -si --noconfirm 2>/dev/null); then
        cd ~ 2>/dev/null && rm -rf "$tmpdir"
        return 1
    fi
    cd ~ 2>/dev/null && rm -rf "$tmpdir"
    log_i "yay-bin installed"
    echo "OK" >> "$REPORT_FILE"
}

# --- Kernel Module Recovery ---
recover_module() {
    local mod="$1"
    log_i "Loading kernel module: ${mod}..."
    sudo modprobe "$mod" 2>/dev/null && { log_i "Module ${mod} loaded"; echo "OK" >> "$REPORT_FILE"; return 0; }
    log_i "Module ${mod} not available. Trying alternatives..."
    case "$mod" in
        panasonic_laptop)
            for alt in panasonic acpi_panasonic; do
                sudo modprobe "$alt" 2>/dev/null || true
            done
            ;;
        msr)
            echo "msr.allow_writes=on" | sudo tee /etc/modprobe.d/msr.conf >/dev/null 2>&1 || true
            sudo modprobe msr 2>/dev/null || true
            ;;
    esac
    if lsmod | grep -q "$mod"; then
        log_i "Module ${mod} loaded via alternative"
        echo "OK" >> "$REPORT_FILE"
    else
        log_i "Module ${mod} not available"
        echo "SKIP" >> "$REPORT_FILE"
    fi
}

# --- JaKooLit Fallback ---
recover_hyprland() {
    [ "$CAP_NETWORK" -eq 0 ] && { log_i "Offline — cannot install Hyprland packages"; echo "SKIP (offline)" >> "$REPORT_FILE"; return 1; }
    log_i "Installing Hyprland manually (JaKooLit fallback)..."
    local pkgs=(hyprland waybar-hyprland rofi-lbonn-wayland-git swww dunst sddm hyprpaper hyprlock hypridle xdg-desktop-portal-hyprland)
    for pkg in "${pkgs[@]}"; do
        yay -S --noconfirm "$pkg" 2>/dev/null || true
    done
    log_i "Manual Hyprland packages installed"
    echo "OK" >> "$REPORT_FILE"
}

# --- Package retry: cai lai packages bi fail ---
recover_packages() {
    [ "$CAP_NETWORK" -eq 0 ] && { log_i "Offline — cannot retry packages"; return 1; }
    if [ -f "$PKG_BEFORE" ] && [ -f "$PKG_AFTER" ]; then
        log_i "Checking for failed packages..."
        # So sanh: packages trong after nhung khong trong before
        local new_pkgs
        new_pkgs=$(diff "$PKG_BEFORE" "$PKG_AFTER" 2>/dev/null | grep '^>' | sed 's/^> //' | awk '{print $1}')
        if [ -n "$new_pkgs" ]; then
            log_i "Found $(echo "$new_pkgs" | wc -l) newly installed packages"
        fi
    fi
    log_i "Re-running pacman -Syu..."
    sudo pacman -Syu --noconfirm 2>/dev/null || true
    echo "OK" >> "$REPORT_FILE"
}

# --- Main ---
main() {
    load_caps

    echo "GodMode Recovery Report" > "$REPORT_FILE"
    echo "========================" >> "$REPORT_FILE"
    echo "Time: $(date)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    # Always try network first
    recover_network
    recover_aur

    if [ $# -eq 0 ]; then
        # No args = light recovery (network + AUR only)
        log_i "Light recovery done. Run 'godmode-recovery.sh --all' for full recovery."
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            --network) ;;
            --module) shift; recover_module "$1" ;;
            --hyprland) recover_hyprland ;;
            --packages) recover_packages ;;
            --eco)
                [ -f /sys/devices/platform/panasonic/eco_mode ] && \
                    echo 1 | sudo tee /sys/devices/platform/panasonic/eco_mode > /dev/null && \
                    log_i "Eco mode re-enabled" || log_i "Eco mode not available"
                ;;
            --all)
                recover_hyprland
                recover_module "panasonic_laptop"
                recover_module "msr"
                recover_packages
                [ -f /sys/devices/platform/panasonic/eco_mode ] && \
                    echo 1 | sudo tee /sys/devices/platform/panasonic/eco_mode > /dev/null || true
                ;;
        esac
        shift
    done

    echo "" >> "$REPORT_FILE"
    echo "Recovery complete. See: $REPORT_FILE" >> "$REPORT_FILE"
    cat "$REPORT_FILE"

    if [ "$CAP_NETWORK" -eq 0 ]; then
        echo ""
        echo -e "${YEL}⚠ Network still offline. After connecting, run:${NC}"
        echo "  bash lib/godmode-recovery.sh --all"
    fi
}

main "$@"
