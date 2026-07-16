#!/bin/bash
# ============================================================================
# PHASE3-CHROOT.SH — chroot configuration
# ----------------------------------------------------------------------------
# Chay trong arch-chroot de cau hinh:
# - Timezone, locale, hostname, hosts
# - Root password, user creation, sudo
# - mkinitcpio (btrfs hook + intel-ucode)
# - Bootloader (systemd-boot)
# - Enable services
# ============================================================================

phase3_ask_credentials() {
    log_step "3.0: User credentials"

    # Hostname
    read -r -p "  Hostname [${DEFAULT_HOSTNAME}]: " input_hostname
    INSTALL_HOSTNAME="${input_hostname:-$DEFAULT_HOSTNAME}"
    log_info "Hostname: ${INSTALL_HOSTNAME}"

    # Root password
    while true; do
        read -r -s -p "  Root password: " pass1
        echo ""
        read -r -s -p "  Confirm root password: " pass2
        echo ""
        if [ "$pass1" = "$pass2" ] && [ -n "$pass1" ]; then
            INSTALL_ROOT_PASS="$pass1"
            break
        fi
        log_warn "Passwords don't match or empty. Try again."
    done

    # User
    read -r -p "  Username [${DEFAULT_USER}]: " input_user
    INSTALL_USER="${input_user:-$DEFAULT_USER}"
    log_info "Username: ${INSTALL_USER}"

    while true; do
        read -r -s -p "  User password: " pass1
        echo ""
        read -r -s -p "  Confirm user password: " pass2
        echo ""
        if [ "$pass1" = "$pass2" ] && [ -n "$pass1" ]; then
            INSTALL_PASS="$pass1"
            break
        fi
        log_warn "Passwords don't match or empty. Try again."
    done

    save_state
}

phase3_chroot_commands() {
    log_step "3.1: Configuring system via arch-chroot"

    # Build a single chroot script with all commands
    local chroot_script="/tmp/arch-install-chroot.sh"

    cat > "$chroot_script" << 'CHROOT_SCRIPT'
#!/bin/bash
set -euo pipefail

# Read state
source /tmp/arch-install-state.sh

echo ">>> Setting timezone..."
ln -sf "/usr/share/zoneinfo/${INSTALL_TIMEZONE}" /etc/localtime
hwclock --systohc

echo ">>> Setting locale..."
sed -i 's/^#\(en_US.UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo ">>> Setting keymap..."
echo "KEYMAP=us" > /etc/vconsole.conf

echo ">>> Setting hostname..."
echo "${INSTALL_HOSTNAME}" > /etc/hostname
cat > /etc/hosts << HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${INSTALL_HOSTNAME}.localdomain ${INSTALL_HOSTNAME}
HOSTS_EOF

echo ">>> Setting root password..."
echo "root:${INSTALL_ROOT_PASS}" | chpasswd

echo ">>> Creating user..."
useradd -m -G wheel,storage,power,audio,video,input -s /bin/bash "${INSTALL_USER}"
echo "${INSTALL_USER}:${INSTALL_PASS}" | chpasswd

echo ">>> Setting up sudo..."
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/99-wheel
chmod 440 /etc/sudoers.d/99-wheel

# --- Swapfile ---
if [ "${USE_SWAPFILE:-0}" = "1" ] && [ -n "${INSTALL_SWAPFILE:-}" ]; then
    echo ">>> Creating swapfile: ${INSTALL_SWAPFILE}..."
    # Swapfile on Btrfs requires NO_COW before writing data
    truncate -s 0 "${INSTALL_SWAPFILE}"
    chattr +C "${INSTALL_SWAPFILE}"
    fallocate -l ${SWAPFILE_SIZE_MB}M "${INSTALL_SWAPFILE}"
    chmod 600 "${INSTALL_SWAPFILE}"
    mkswap "${INSTALL_SWAPFILE}"
    swapon "${INSTALL_SWAPFILE}"
    echo "${INSTALL_SWAPFILE} none swap defaults 0 0" >> /etc/fstab
    echo ">>> Swapfile created: ${INSTALL_SWAPFILE}"
fi

echo ">>> Configuring mkinitcpio..."
if [ "${USE_ENCRYPTION:-0}" = "1" ]; then
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt filesystems fsck btrfs)/' /etc/mkinitcpio.conf
else
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck btrfs)/' /etc/mkinitcpio.conf
fi
mkinitcpio -P

# --- Bootloader ---
if [ -n "${INSTALL_ESP:-}" ]; then
    echo ">>> Installing systemd-boot..."
    bootctl install

    # Detect root device
    local root_dev="${INSTALL_ROOT:-}"
    if [ -z "$root_dev" ]; then
        root_dev=$(findmnt -n -o SOURCE / 2>/dev/null || true)
    fi
    [ -n "$root_dev" ] && echo ">>> Root device: ${root_dev}" || echo ">>> WARNING: Cannot detect root device"

    # Get root PARTUUID
    ROOT_PARTUUID=""
    [ -n "$root_dev" ] && ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$root_dev" 2>/dev/null || true)
    [ -z "$ROOT_PARTUUID" ] && echo ">>> WARNING: Cannot detect PARTUUID. Will use placeholder."

    cat > /boot/loader/entries/arch.conf << LOADER_EOF
title   Arch Linux (linux-zen)
linux   /vmlinuz-linux-zen
initrd  /intel-ucode.img
initrd  /initramfs-linux-zen.img
options root=PARTUUID=${ROOT_PARTUUID} rw rootflags=subvol=@ ${KERNEL_PARAMS}
LOADER_EOF

    cat > /boot/loader/loader.conf << LOADER_CONF
default arch.conf
timeout 3
console-mode max
editor no
LOADER_CONF
    echo ">>> systemd-boot installed"
else
    echo ">>> WARNING: No ESP configured. Skipping bootloader install."
fi

# --- refind_linux.conf (always, as fallback) ---
echo ">>> Generating /boot/refind_linux.conf for rEFInd..."
local root_dev="${INSTALL_ROOT:-}"
if [ -z "$root_dev" ]; then
    root_dev=$(findmnt -n -o SOURCE / 2>/dev/null || true)
fi
ROOT_PARTUUID=""
[ -n "$root_dev" ] && ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$root_dev" 2>/dev/null || true)
[ -z "$ROOT_PARTUUID" ] && echo ">>> WARNING: Cannot detect PARTUUID. Must fix manually after reboot."
cat > /boot/refind_linux.conf << REFIND_EOF
"Boot with defaults"  "root=PARTUUID=${ROOT_PARTUUID} rw rootflags=subvol=@ ${KERNEL_PARAMS}"
"Boot to single-user" "root=PARTUUID=${ROOT_PARTUUID} rw rootflags=subvol=@ single ${KERNEL_PARAMS}"
"Boot with minimal"   "root=PARTUUID=${ROOT_PARTUUID} rw rootflags=subvol=@ ${KERNEL_PARAMS}"
REFIND_EOF
echo ">>> refind_linux.conf created"

# --- rEFInd ESP kernel sync ---
if [ "${REFIND_SYNC_ESP:-true}" = "true" ]; then
    if [ -f /usr/local/bin/refind-sync.sh ]; then
        echo ">>> Syncing kernel to ESP for rEFInd..."
        bash /usr/local/bin/refind-sync.sh || echo "WARNING: refind-sync.sh failed"
    fi
fi

# --- Fix fstab Btrfs compression ---
if grep -q "btrfs" /etc/fstab 2>/dev/null && ! grep -q "compress=zstd" /etc/fstab 2>/dev/null; then
    echo ">>> Patching fstab Btrfs compression..."
    sed -i '/btrfs/ { /compress=zstd/! s/subvol=[^, ]*/&,compress=zstd:3,noatime/ }' /etc/fstab
    echo ">>> Fstab patched with compress=zstd:3,noatime"
fi

echo ">>> Enabling services..."
systemctl enable NetworkManager
systemctl enable systemd-resolved
systemctl enable fstrim.timer
systemctl enable bluetooth

echo ">>> Creating first-boot flag..."
mkdir -p /var/lib/godmode
touch /var/lib/godmode/firstboot-pending

echo ">>> CHROOT CONFIGURATION COMPLETE"
CHROOT_SCRIPT

    # Copy refind-sync.sh into chroot for kernel sync
    local refind_sync_src="$LIB_DIR/refind-sync.sh"
    if [ -f "$refind_sync_src" ]; then
        sudo mkdir -p /mnt/usr/local/bin
        sudo cp "$refind_sync_src" /mnt/usr/local/bin/refind-sync.sh
        sudo chmod +x /mnt/usr/local/bin/refind-sync.sh
        log_info "refind-sync.sh copied to chroot: /usr/local/bin/refind-sync.sh"
    else
        log_warn "refind-sync.sh not found at $refind_sync_src — kernel sync will be skipped"
    fi

    # Copy state + script into /mnt
    sudo cp "$STATE_FILE" /mnt/tmp/arch-install-state.sh
    sudo cp "$chroot_script" /mnt/tmp/arch-install-chroot.sh
    sudo chmod +x /mnt/tmp/arch-install-chroot.sh

    # Run in chroot
    run_cmd "Configure system in chroot" \
        sudo arch-chroot /mnt /tmp/arch-install-chroot.sh

    log_success "System configured"
}

phase3_main() {
    log_step "PHASE 3: SYSTEM CONFIGURATION"
    load_state

    guard_phase 3 "System Configuration" || return 0

    # Set defaults from config
    INSTALL_TIMEZONE="$DEFAULT_TIMEZONE"
    REFIND_SYNC_ESP="${REFIND_SYNC_ESP:-true}"
    save_state

    phase3_ask_credentials
    phase3_chroot_commands

    save_phase_progress 3
    log_success "Phase 3 complete — system configured"
}
