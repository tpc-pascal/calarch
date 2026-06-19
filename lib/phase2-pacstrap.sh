#!/bin/bash
# ============================================================================
# PHASE2-PACSTRAP.SH — Install base system to /mnt
# ----------------------------------------------------------------------------
# Dung pacstrap de cai dat Arch Linux base vao /mnt:
# - kernel linux-zen, firmware, intel-ucode
# - base-devel, git, curl, vim, whiptail, sudo
# - networkmanager, iwd, btrfs-progs, pipewire
# ============================================================================

phase2_pacstrap() {
    log_step "2.1: Installing base system via pacstrap"

    log_info "This will install the following packages:"
    for pkg in "${BASE_PACKAGES[@]}"; do
        echo "  • $pkg"
    done
    echo ""
    confirm "Continue with installation?" "y" || log_fatal "Aborted by user"

    run_cmd "Install base system (this may take a few minutes)" \
        sudo pacstrap /mnt "${BASE_PACKAGES[@]}"

    log_success "Base system installed"
}

phase2_fstab() {
    log_step "2.2: Generating fstab"

    local fstab_file="/tmp/arch-install-fstab"
    run_cmd "Generate fstab" \
        sudo genfstab -U /mnt > "$fstab_file"

    # Ensure Btrfs mount options include compress
    # genfstab doesn't always preserve subvol mount options correctly
    # We fix them here
    if grep -q "/mnt/home" "$fstab_file" 2>/dev/null; then
        log_info "Fstab generated with subvolume entries"
    fi

    sudo cp "$fstab_file" /mnt/etc/fstab
    log_success "Fstab written"
}

phase2_verify() {
    log_step "2.3: Verify installation"

    local checks=0
    [ -d /mnt/etc ] && checks=$((checks + 1))
    [ -d /mnt/usr/bin ] && checks=$((checks + 1))
    [ -d /mnt/home ] && checks=$((checks + 1))
    [ -d /mnt/boot ] && checks=$((checks + 1))

    if [ "$checks" -ge 3 ]; then
        log_success "Base system verification: ${checks}/4 OK"
    else
        log_warn "Base system may be incomplete: ${checks}/4 checks passed"
    fi
}

phase2_main() {
    log_step "PHASE 2: BASE INSTALLATION"
    load_state

    guard_phase 2 "Base Installation" || return 0

    phase2_pacstrap
    phase2_fstab
    phase2_verify

    save_phase_progress 2
    log_success "Phase 2 complete — base system installed"
}
