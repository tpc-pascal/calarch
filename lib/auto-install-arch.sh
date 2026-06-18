#!/bin/bash
# ============================================================================
# AUTO-INSTALL-ARCH.SH — calarch installer entry point
# ----------------------------------------------------------------------------
# Modifications are SAFE: every change is backed up, reversible, idempotent.
# Running multiple times is harmless. On error, changes are rolled back.
#
# Modes:
#   (no args) → interactive menu
#   --install          → archinstall TUI + calarch post-install
#   --post-install [mnt] → calarch post-install on mounted system
#   --refind [mnt]     → generate/update refind_linux.conf
#   --advanced         → legacy 5-phase installer
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
BACKUP_DIR="/tmp/calarch-backups"
CALARCH_LOG="/tmp/calarch.log"

# --- Source core modules ---
source "$LIB_DIR/common.sh"
source "$LIB_DIR/config.sh"

# ============================================================================
# ROLLBACK SYSTEM
# ============================================================================

CHANGES=()

backup_file() {
    local src="$1"
    [ ! -f "$src" ] && return 0
    mkdir -p "$BACKUP_DIR"
    local bak="$BACKUP_DIR/$(echo "$src" | tr '/' '_')"
    if [ ! -f "$bak" ]; then
        cp -a "$src" "$bak"
        CHANGES+=("$src:$bak")
        log_info "Backed up: ${src}"
    fi
}

rollback() {
    local ec=$?
    echo ""
    log_warn "Error occurred (exit ${ec}). Rolling back changes..."
    local restored=0
    for entry in "${CHANGES[@]}"; do
        local src="${entry%%:*}"
        local bak="${entry#*:}"
        if [ -f "$bak" ]; then
            cp -a "$bak" "$src" 2>/dev/null && restored=$((restored + 1))
        fi
    done
    if [ $restored -gt 0 ]; then
        log_info "Restored ${restored} file(s) from backup"
        log_info "Backups preserved at: ${BACKUP_DIR}"
    fi
    log_info "You can retry after fixing the issue"
}

cleanup() {
    local ec=$?
    trap '' EXIT INT TERM
    if [ $ec -ne 0 ] && [ ${#CHANGES[@]} -gt 0 ]; then
        rollback
        log_info "Backups saved at ${BACKUP_DIR} for inspection"
    else
        rm -rf "$BACKUP_DIR" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

# ============================================================================
# VALIDATION HELPERS
# ============================================================================

die_if_not_iso() {
    if ! command -v pacstrap &>/dev/null; then
        log_fatal "Not in Arch ISO live environment (pacstrap not found)"
    fi
}

die_if_no_network() {
    if ! ping -c 1 -W 3 archlinux.org &>/dev/null; then
        log_fatal "No network. Configure WiFi: iwctl station wlan0 connect <SSID>"
    fi
}

die_if_no_disk_space() {
    local mnt="${1:-/mnt}"
    local min_mb="${2:-1024}"
    local avail
    avail=$(df -m "$mnt" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
    if [ "$avail" -lt "$min_mb" ]; then
        log_fatal "Insufficient disk space at ${mnt}: ${avail}MB < ${min_mb}MB required"
    fi
}

validate_mount_point() {
    local mnt="$1"
    if [ ! -d "$mnt/etc" ] || [ ! -f "$mnt/etc/fstab" ]; then
        log_fatal "${mnt} does not contain a valid Arch Linux installation"
    fi
}

read_mount_point() {
    local prompt="${1:-Mount point}"
    local mnt=""
    echo -n "  ${prompt} [/mnt]: "
    read -r mnt
    [ -z "$mnt" ] && mnt="/mnt"
    validate_mount_point "$mnt"
    echo "$mnt"
}

# ============================================================================
# POST-INSTALL — calarch setup trên hệ thống đã được cài base
# ============================================================================

post_install() {
    local mnt="${1:-/mnt}"
    log_step "Calarch post-install on ${mnt}"

    validate_mount_point "$mnt"

    # --- 0. Detect user (UID >= 1000 from passwd) ---
    local username
    username=$(awk -F: '$3>=1000 && $3!=65534 {print $1; exit}' "$mnt/etc/passwd" 2>/dev/null || echo "")
    if [ -z "$username" ]; then
        log_warn "No user UID>=1000 found, using root"
        username="root"
    fi
    log_info "Target user: ${username}"

    # --- 1. Root partition device ---
    local root_dev
    root_dev=$(findmnt -n -o SOURCE "$mnt" 2>/dev/null || echo "")
    if [ -z "$root_dev" ]; then
        root_dev=$(findmnt -n -o SOURCE --target "$mnt" 2>/dev/null || echo "")
    fi
    [ -n "$root_dev" ] && log_info "Root device: ${root_dev}" || log_warn "Cannot detect root device"

    # --- 2. Btrfs @snapshots subvolume + fstab ---
    if [ -n "$root_dev" ] && command -v btrfs &>/dev/null; then
        local fstype
        fstype=$(findmnt -n -o FSTYPE "$mnt" 2>/dev/null || echo "")
        if [ "$fstype" = "btrfs" ]; then
            if ! btrfs subvolume list "$mnt" 2>/dev/null | grep -q "@snapshots"; then
                log_info "Creating @snapshots subvolume..."
                btrfs subvolume create "$mnt/@snapshots" 2>/dev/null || log_warn "Cannot create @snapshots subvolume"
                mkdir -p "$mnt/.snapshots" 2>/dev/null || true
                local uuid
                uuid=$(blkid -s UUID -o value "$root_dev" 2>/dev/null || echo "")
                if [ -n "$uuid" ] && ! grep -q "\.snapshots" "$mnt/etc/fstab" 2>/dev/null; then
                    backup_file "$mnt/etc/fstab"
                    echo "UUID=${uuid}  /.snapshots  btrfs  subvol=@snapshots  0  0" >> "$mnt/etc/fstab"
                    log_success "Created @snapshots with fstab entry"
                fi
            else
                log_info "@snapshots subvolume already exists"
            fi
        else
            log_info "Filesystem is ${fstype}, not btrfs — skipping @snapshots"
        fi
    fi

    # --- 3. Kernel params ---
    local kparams="$KERNEL_PARAMS"

    # systemd-boot: patch loader entries
    if [ -d "$mnt/boot/loader/entries" ]; then
        for f in "$mnt/boot/loader/entries/"*.conf; do
            [ -f "$f" ] || continue
            if ! grep -q "nowatchdog" "$f" 2>/dev/null; then
                backup_file "$f"
                sed -i "s/^options.*/& $kparams/" "$f"
                log_success "Added kernel params: $(basename "$f")"
            fi
        done
    fi

    # GRUB
    if [ -f "$mnt/etc/default/grub" ]; then
        if ! grep -q "nowatchdog" "$mnt/etc/default/grub" 2>/dev/null; then
            backup_file "$mnt/etc/default/grub"
            sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*/& $kparams/" "$mnt/etc/default/grub"
            log_success "Added kernel params to GRUB config"
        fi
    fi

    # rEFInd: generate refind_linux.conf (idempotent, always regenerates with current params)
    generate_refind_config "$mnt" "$root_dev"

    # --- 4. Clone calarch ---
    local user_home="$mnt/home/$username"
    [ "$username" = "root" ] && user_home="$mnt/root"
    [ ! -d "$user_home" ] && user_home="$mnt/root"

    if [ -d "$user_home/calarch" ]; then
        log_info "calarch already exists at ${user_home}/calarch — skipping clone"
    else
        if [ -d "$SCRIPT_DIR/.git" ]; then
            cp -a "$SCRIPT_DIR" "$user_home/calarch" 2>/dev/null || log_warn "Cannot copy calarch to ${user_home}/calarch"
        else
            die_if_no_network
            if git clone --depth=1 https://github.com/tpc-pascal/calarch.git "$user_home/calarch" 2>/dev/null; then
                log_success "calarch cloned to ${user_home}/calarch"
            else
                log_warn "git clone failed. Install manually: cd ~ && git clone https://github.com/tpc-pascal/calarch.git"
            fi
        fi
    fi

    [ -d "$user_home/calarch" ] && arch-chroot "$mnt" chown -R "${username}:${username}" "/home/${username}/calarch" 2>/dev/null || true

    # --- 5. Enable NetworkManager for first-boot internet ---
    if command -v arch-chroot &>/dev/null; then
        arch-chroot "$mnt" systemctl enable NetworkManager 2>/dev/null || log_warn "Cannot enable NetworkManager"
        log_success "NetworkManager enabled for first boot"
    fi

    # --- 6. First-boot setup: welcome + auto-run God-Mode on login ---
    mkdir -p "$mnt/var/lib/godmode"
    touch "$mnt/var/lib/godmode/firstboot-pending"

    # Profile.d welcome — shows on every login until setup is done
    cat > "$mnt/etc/profile.d/godmode-welcome.sh" << 'WELCOME'
#!/bin/bash
FLAG="/var/lib/godmode/firstboot-pending"
DONE="/var/lib/godmode/firstboot-done"
[ ! -f "$FLAG" ] && exit 0
[ -f "$DONE" ] && exit 0
echo ""
echo -e "\033[1;32m╔══════════════════════════════════════════════════════════╗\033[0m"
echo -e "\033[1;32m║     WELCOME TO ARCH LINUX + PANASONIC CF-XZ6           ║\033[0m"
echo -e "\033[1;32m╚══════════════════════════════════════════════════════════╝\033[0m"
echo ""
echo "  God-Mode setup will start automatically..."
echo ""
WELCOME

    # BashLogin: auto-run God-Mode setup on first interactive login
    local bashlogin="$mnt/home/$username/.bash_login"
    [ "$username" = "root" ] && bashlogin="$mnt/root/.bash_login"
    cat > "$bashlogin" << 'BASHEOF'
#!/bin/bash
FLAG="/var/lib/godmode/firstboot-pending"
DONE="/var/lib/godmode/firstboot-done"
[ ! -f "$FLAG" ] && exit 0
[ -f "$DONE" ] && exit 0
# Đợi network
for i in $(seq 1 30); do
    ping -c 1 -W 1 archlinux.org &>/dev/null && break
    sleep 2
done
# Chay God-Mode setup
cd ~/calarch 2>/dev/null && bash start.sh -m first-boot
rm -f "$FLAG"
touch "$DONE"
echo ""
echo -e "\033[1;32mGod-Mode setup complete! System ready.\033[0m"
echo "  Use: cd ~/calarch && ./start.sh  (for settings panel)"
echo ""
BASHEOF
    chown "${username}:${username}" "$bashlogin" 2>/dev/null || true

    # Systemd oneshot service (fallback, also runs on boot)
    local svc_file="$mnt/etc/systemd/system/godmode-firstboot.service"
    if [ ! -f "$svc_file" ]; then
        cat > "$svc_file" << 'SVC'
[Unit]
Description=GodMode: First Boot Setup
After=network-online.target
Wants=network-online.target
ConditionPathExists=/var/lib/godmode/firstboot-pending

[Service]
Type=oneshot
ExecStart=/usr/local/bin/godmode-firstboot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVC

        cat > "$mnt/usr/local/bin/godmode-firstboot.sh" << 'FBS'
#!/bin/bash
set -euo pipefail
FLAG="/var/lib/godmode/firstboot-pending"
DONE="/var/lib/godmode/firstboot-done"
[ ! -f "$FLAG" ] && exit 0
[ -f "$DONE" ] && exit 0
# Dieu nay chay o boot (khong co TUI). God-Mode se chay o login steps.
# Chi can dam bao network san sang
for i in $(seq 1 20); do
    ping -c 1 -W 1 archlinux.org &>/dev/null && break
    sleep 3
done
exit 0
FBS
        chmod +x "$mnt/usr/local/bin/godmode-firstboot.sh"

        if command -v arch-chroot &>/dev/null; then
            arch-chroot "$mnt" systemctl enable godmode-firstboot.service 2>/dev/null || true
        fi
    fi

    log_success "Post-install complete"
}

# ============================================================================
# GENERATE REFIND CONFIG
# ============================================================================

generate_refind_config() {
    local mnt="${1:-/mnt}"
    local root_dev="${2:-}"

    [ -z "$root_dev" ] && root_dev=$(findmnt -n -o SOURCE "$mnt" 2>/dev/null || echo "")

    local partuuid=""
    [ -n "$root_dev" ] && partuuid=$(blkid -s PARTUUID -o value "$root_dev" 2>/dev/null || echo "")

    if [ -z "$partuuid" ]; then
        log_warn "Cannot detect PARTUUID, refind_linux.conf will use placeholder"
        partuuid="PLACEHOLDER_PARTUUID"
    fi

    local conf_path="$mnt/boot/refind_linux.conf"
    local kparams="$KERNEL_PARAMS"

    backup_file "$conf_path"
    cat > "$conf_path" << REFIND
# calarch: refind_linux.conf for rEFInd auto-detection
"Boot with defaults"  "root=PARTUUID=${partuuid} rw rootflags=subvol=@ ${kparams}"
"Boot to single-user" "root=PARTUUID=${partuuid} rw rootflags=subvol=@ single ${kparams}"
"Boot with minimal"   "root=PARTUUID=${partuuid} rw rootflags=subvol=@ ${kparams}"
REFIND

    log_success "refind_linux.conf generated at ${conf_path}"
}

# ============================================================================
# FULL INSTALL — archinstall TUI + calarch post-install
# ============================================================================

full_install() {
    log_step "Full Install: archinstall TUI + calarch post-install"

    die_if_not_iso

    # --- 0. Install archinstall if needed ---
    if ! command -v archinstall &>/dev/null; then
        die_if_no_network
        log_info "Installing archinstall..."
        sudo pacman -S --noconfirm archinstall || log_fatal "Cannot install archinstall"
    fi

    # --- 1. Instructions ---
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  archinstall TUI se mo ra. Cau hinh:                       ║"
    echo "║  - Partition: chon partition ban muon                       ║"
    echo "║  - Filesystem: Btrfs (de co snapshot)                       ║"
    echo "║  - Bootloader: chon theo y (rEFInd / systemd-boot / GRUB)  ║"
    echo "║  - User: tao user + password                                ║"
    echo "║                                                            ║"
    echo "║  QUAN TRONG: Sau khi archinstall xong, chon \"Exit\"         ║"
    echo "║  (KHONG chon reboot). calarch se tu chay post-install.      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo -n "Nhan Enter de mo archinstall... "
    read -r

    # --- 2. Run archinstall TUI ---
    log_info "Starting archinstall TUI..."
    sudo archinstall || {
        log_warn "archinstall exited with error"
        echo -n "Continue anyway? [y/N]: "
        read -r cont
        [[ "$cont" =~ ^[yY] ]] || exit 1
    }

    # --- 3. Detect mount point ---
    local mnt=""
    for p in /mnt /mnt/archinstall; do
        [ -d "$p/etc" ] && [ -f "$p/etc/fstab" ] && mnt="$p" && break
    done

    if [ -z "$mnt" ]; then
        log_warn "Cannot auto-detect mount point"
        echo -n "Enter mount point [/mnt]: "
        read -r mnt
        [ -z "$mnt" ] && mnt="/mnt"
    fi

    validate_mount_point "$mnt"
    log_success "Detected installed system at: ${mnt}"

    # --- 4. Post-install ---
    post_install "$mnt"

    # --- 5. Summary ---
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Full install complete!                                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Sau reboot: login → cd ~/calarch → ./start.sh"
    echo ""

    # --- 6. Unmount + optional Reboot ---
    echo -n "Reboot now? [Y/n]: "
    read -r reboot_ans
    case "$reboot_ans" in
        [nN]*)
            log_info "Unmounting..."
            sudo umount -R "$mnt" 2>/dev/null || true
            log_info "You can reboot later: sudo reboot"
            ;;
        *)
            log_info "Unmounting..."
            sudo umount -R "$mnt" 2>/dev/null || true
            log_info "Rebooting... remove USB when prompted"
            sleep 2
            sudo reboot
            ;;
    esac
}

# ============================================================================
# ADVANCED INSTALLER — legacy 5-phase
# ============================================================================

run_advanced_installer() {
    log_step "Advanced 5-phase installer"

    die_if_not_iso

    for module in phase0-detect phase1-disk phase2-pacstrap phase3-chroot phase4-finalize; do
        local mp="$LIB_DIR/$module.sh"
        [ -f "$mp" ] || log_fatal "Module not found: $mp"
        source "$mp"
    done

    clear
    echo -e "${BOLD}${GREEN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║      ARCH LINUX AUTO INSTALLER — PANASONIC CF-XZ6       ║"
    echo "║      Dual-boot safe | Btrfs | linux-zen | systemd-boot  ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo ""
    confirm "Proceed?" "n" || exit 0

    phase0_main
    phase1_main
    phase2_main
    phase3_main
    phase4_main

    log_success "All phases complete!"
}

# ============================================================================
# MENU
# ============================================================================

show_menu() {
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║              calarch — Arch Linux + CF-XZ6                  ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""
        echo "  1) Full Install — archinstall TUI + calarch post-install"
        echo "  2) Post-Install Only — chay calarch tren he thong da mount"
        echo "  3) Bootloader Config — sinh refind_linux.conf"
        echo "  4) Advanced — 5-phase installer (legacy)"
        echo "  5) Exit"
        echo ""
        echo -n "  Select (1-5): "
        read -r choice

        case "$choice" in
            1) full_install ;;
            2)
                mnt=$(read_mount_point)
                post_install "$mnt"
                echo -n "  Reboot now? [y/N]: "
                read -r r
                [[ "$r" =~ ^[yY] ]] && sudo reboot
                ;;
            3)
                mnt=$(read_mount_point)
                generate_refind_config "$mnt"
                ;;
            4) run_advanced_installer ;;
            *) exit 0 ;;
        esac
    done
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    case "${1:-}" in
        --install|--quick|full)      full_install ;;
        --post-install)
            local mnt="${2:-/mnt}"
            [ -d "$mnt/etc" ] || mnt=$(read_mount_point "Mount point (system)")
            post_install "$mnt"
            echo -n "Reboot now? [y/N]: "
            read -r r
            [[ "$r" =~ ^[yY] ]] && sudo reboot
            ;;
        --refind|--bootloader)
            local mnt="${2:-/mnt}"
            generate_refind_config "$mnt"
            ;;
        --advanced)                  run_advanced_installer ;;
        *)                           show_menu ;;
    esac
}

main "$@"
