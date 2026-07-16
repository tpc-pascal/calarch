#!/bin/bash
# ============================================================================
# PHASE4-FINALIZE.SH — Verification, calarch clone, first-boot service, reboot
# ----------------------------------------------------------------------------
# - Verify bootloader + user + network
# - Clone calarch repo
# - Create first-boot systemd service
# - Print summary → offer reboot
# ============================================================================

phase4_verify() {
    log_step "4.1: Verify installation"

    local errors=0

    # Bootloader
    if [ -f /mnt/boot/loader/entries/arch.conf ]; then
        log_success "Bootloader: OK"
    elif [ -z "${INSTALL_ESP:-}" ]; then
        log_warn "Bootloader: SKIPPED (no ESP selected)"
    else
        log_error "Bootloader: MISSING (ESP was selected but install may have failed)"
        errors=$((errors + 1))
    fi

    # User
    if sudo grep -q "^${INSTALL_USER}:" /mnt/etc/passwd 2>/dev/null; then
        log_success "User ${INSTALL_USER}: OK"
        if sudo grep -q "^${INSTALL_USER}:" /mnt/etc/shadow 2>/dev/null; then
            log_success "User password: set"
        else
            log_warn "User password: may not be set"
        fi
    else
        log_error "User ${INSTALL_USER}: NOT FOUND"
        errors=$((errors + 1))
    fi

    # Wheel group + sudo
    if sudo grep -q "^%wheel" /mnt/etc/sudoers.d/99-wheel 2>/dev/null || sudo grep -q "^%wheel" /mnt/etc/sudoers 2>/dev/null; then
        log_success "Sudo for wheel: OK"
    else
        log_warn "Sudo for wheel: not configured"
    fi

    # Network
    if [ -f /mnt/etc/systemd/system/multi-user.target.wants/NetworkManager.service ]; then
        log_success "NetworkManager enabled: OK"
    else
        log_warn "NetworkManager may not be enabled"
    fi

    # fstab
    if [ -f /mnt/etc/fstab ]; then
        log_success "fstab: OK"
    else
        log_error "fstab: MISSING"
        errors=$((errors + 1))
    fi

    if [ "$errors" -gt 0 ]; then
        log_warn "${errors} error(s) found. Review before rebooting."
        confirm "Continue anyway?" || log_fatal "Aborted"
    else
        log_success "All checks passed — system is ready"
    fi
}

phase4_clone_calarch() {
    log_step "4.2: Clone calarch repository"

    local user_home="/mnt/home/${INSTALL_USER}"
    local calarch_dir="${user_home}/calarch"

    if [ -d "$calarch_dir" ]; then
        log_info "calarch already exists, updating..."
        run_cmd "Update calarch" \
            sudo git -C "$calarch_dir" pull 2>/dev/null || true
    else
        run_cmd "Clone calarch" \
            sudo git clone --depth=1 https://github.com/tpc-pascal/calarch.git "$calarch_dir"
    fi

    # Fix ownership
    run_cmd "Fix ownership" \
        sudo chown -R "${INSTALL_USER}:${INSTALL_USER}" "$calarch_dir"

    log_success "calarch ready at ${calarch_dir}"
}

phase4_firstboot_service() {
    log_step "4.3: Create first-boot service"

    local service_file="/mnt/etc/systemd/system/godmode-firstboot.service"
    local script_file="/mnt/usr/local/bin/godmode-firstboot.sh"

    # Create the first-boot script
    sudo tee "$script_file" > /dev/null << 'SCRIPT_EOF'
#!/bin/bash
# GodMode: First Boot Setup — chay 1 lan khi reboot
set -euo pipefail

FLAG_FILE="/var/lib/godmode/firstboot-pending"
DONE_FILE="/var/lib/godmode/firstboot-done"

[ ! -f "$FLAG_FILE" ] && exit 0
[ -f "$DONE_FILE" ] && exit 0

echo ">>> GodMode: First boot setup..."
echo ">>> Arch Linux installed successfully!"

# Xoa flag de khong chay lai
rm -f "$FLAG_FILE"
touch "$DONE_FILE"

# Thong bao cho user
cat > /etc/profile.d/godmode-welcome.sh << 'WELCOME'
#!/bin/bash
# GodMode: Welcome message
echo ""
echo -e "\033[1;32m╔══════════════════════════════════════════════════════════╗\033[0m"
echo -e "\033[1;32m║     WELCOME TO ARCH LINUX + PANASONIC CF-XZ6           ║\033[0m"
echo -e "\033[1;32m╚══════════════════════════════════════════════════════════╝\033[0m"
echo ""
echo "  Next step: Run the God-Mode setup:"
echo ""
echo "    cd ~/calarch"
echo "    ./start.sh"
echo ""
echo "  This will install Hyprland desktop, CPU affinity,"
echo "  thermal management, and all IT student tools."
echo ""
WELCOME

exit 0
SCRIPT_EOF

    sudo chmod +x "$script_file"

    # Create the service file
    sudo tee "$service_file" > /dev/null << 'SERVICE_EOF'
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
SERVICE_EOF

    # Enable the service in chroot
    run_cmd "Enable first-boot service" \
        sudo arch-chroot /mnt systemctl enable godmode-firstboot.service

    log_success "First-boot service created"
}

phase4_print_summary() {
    log_step "4.4: Installation summary"

    local swap_desc=""
    if [ "$USE_SWAPFILE" -eq 1 ] && [ -n "$INSTALL_SWAPFILE" ]; then
        swap_desc="${SWAPFILE_SIZE_MB}MB swapfile (${INSTALL_SWAPFILE})"
    elif [ -n "$INSTALL_SWAP" ]; then
        swap_desc="${INSTALL_SWAP}"
    else
        swap_desc="none"
    fi

    local boot_desc=""
    if [ -n "$INSTALL_ESP" ]; then
        boot_desc="systemd-boot (ESP: ${INSTALL_ESP})"
    else
        boot_desc="NOT INSTALLED — manual setup required"
    fi

    local mode_desc=""
    if [ "$INSTALL_MODE" = "partition" ]; then
        mode_desc="Existing partition (${INSTALL_ROOT})"
    else
        mode_desc="Whole disk (${INSTALL_DISK})"
    fi

    local summary=""
    summary+="\n${BOLD}${GREEN}════════════════════════════════════════════════════════${RESET}\n"
    summary+="${BOLD}${GREEN}  ARCH LINUX INSTALLATION COMPLETE!${RESET}\n"
    summary+="${BOLD}${GREEN}════════════════════════════════════════════════════════${RESET}\n"
    summary+="\n"
    summary+="  Mode:        ${mode_desc}\n"
    summary+="  Root:        ${INSTALL_ROOT}\n"
    summary+="  Swap:        ${swap_desc}\n"
    summary+="  Bootloader:  ${boot_desc}\n"
    summary+="  Hostname:    ${INSTALL_HOSTNAME}\n"
    summary+="  Username:    ${INSTALL_USER}\n"
    summary+="  Kernel:      linux-zen\n"
    summary+="  Filesystem:  Btrfs (zstd:3)\n"
    summary+="\n"
    summary+="${BOLD}${YELLOW}⚠ Don't forget to remove the USB before reboot!${RESET}\n"
    summary+="\n"
    summary+="${CYAN}After reboot:${RESET}\n"
    summary+="  Login as ${INSTALL_USER}\n"
    summary+="  Run:  cd ~/calarch && ./start.sh\n"

    echo -e "$summary"
}

phase4_reboot() {
    log_step "4.5: Reboot"

    echo ""
    log_info "Unmounting filesystems..."
    swapoff -a 2>/dev/null || true
    sudo umount -R /mnt 2>/dev/null || true

    echo ""
    if confirm "Reboot now?" "y"; then
        log_info "Rebooting... remove USB when prompted"
        sleep 2
        sudo reboot
    else
        log_info "You can reboot later: sudo reboot"
    fi
}

phase4_main() {
    log_step "PHASE 4: FINALIZATION"
    load_state

    guard_phase 4 "Finalization" || return 0

    phase4_verify
    phase4_clone_calarch
    phase4_firstboot_service
    phase4_print_summary
    phase4_reboot

    save_phase_progress 4
    log_success "Phase 4 complete — installation finalized"
}
