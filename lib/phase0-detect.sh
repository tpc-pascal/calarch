#!/bin/bash
# ============================================================================
# PHASE0-DETECT.SH — Live environment detection
# ----------------------------------------------------------------------------
# Chay trong Arch ISO live environment. Phat hien:
# - UEFI / Secure Boot
# - Network (Ethernet + WiFi)
# - Disk layout, Windows, existing ESP
# - CF-XZ6 hardware
# ============================================================================

phase0_detect_uefi() {
    log_step "0.1: UEFI & Secure Boot"
    UEFI_OK=0
    if [ -d /sys/firmware/efi/efivars ]; then
        UEFI_OK=1
        log_success "UEFI detected"
    else
        log_warn "Legacy BIOS detected — UEFI required"
        log_warn "Boot again with UEFI mode enabled in BIOS"
    fi

    SECURE_BOOT=0
    if command -v bootctl &>/dev/null && bootctl status 2>/dev/null | grep -qi "Secure Boot.*enabled"; then
        SECURE_BOOT=1
        log_warn "Secure Boot is ON — may need to disable it or sign bootloader"
    fi
    [ "$UEFI_OK" -eq 0 ] && log_fatal "UEFI is required. Aborting."
}

phase0_detect_cfxz6() {
    IS_CFXZ6=0
    local product
    product=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo "UNKNOWN")
    if [[ "$product" == *"CF-XZ6"* ]] || [[ "$product" == *"CFXZ6"* ]]; then
        IS_CFXZ6=1
        log_success "CF-XZ6 detected: ${product}"
    else
        log_info "Device: ${product} (not CF-XZ6, but install will work)"
    fi
}

phase0_network_ethernet() {
    log_info "Trying Ethernet (dhcpcd)..."
    dhcpcd -q -t 5 2>/dev/null || true
    sleep 2
    if ping -c 2 -W 3 archlinux.org &>/dev/null; then
        NETWORK_OK=1
        log_success "Ethernet connected"
        return 0
    fi
    return 1
}

phase0_network_wifi() {
    [ "$NETWORK_OK" -eq 1 ] && return 0
    log_info "Scanning WiFi networks..."

    # Start iwd if not running
    if ! systemctl is-active iwd &>/dev/null 2>&1; then
        systemctl start iwd 2>/dev/null || true
        sleep 1
    fi

    if ! command -v iwctl &>/dev/null; then
        log_warn "iwctl not available — WiFi may not work"
        return 1
    fi

    # Scan
    iwctl station wlan0 scan 2>/dev/null || true
    sleep 2

    # Get networks
    local networks
    networks=$(iwctl station wlan0 get-networks 2>/dev/null | tail -n +5 | head -20 || true)
    if [ -z "$networks" ]; then
        log_warn "No WiFi networks found (or wlan0 not available)"
        return 1
    fi

    echo -e "${CYAN}Available WiFi networks:${RESET}"
    echo "$networks" | while read -r line; do
        local ssid
        ssid=$(echo "$line" | awk '{print $1}')
        [ -n "$ssid" ] && echo "  • $ssid"
    done

    echo ""
    read -r -p "  Enter SSID to connect: " wifi_ssid
    [ -z "$wifi_ssid" ] && return 1

    read -r -s -p "  Enter password (leave empty for open network): " wifi_pass
    echo ""

    if [ -z "$wifi_pass" ]; then
        iwctl station wlan0 connect "$wifi_ssid" 2>/dev/null || true
    else
        iwctl --passphrase "$wifi_pass" station wlan0 connect "$wifi_ssid" 2>/dev/null || true
    fi

    sleep 3
    if ping -c 2 -W 3 archlinux.org &>/dev/null; then
        NETWORK_OK=1
        log_success "WiFi connected: ${wifi_ssid}"
        return 0
    else
        log_warn "Failed to connect to ${wifi_ssid}"
        return 1
    fi
}

phase0_detect_network() {
    log_step "0.2: Network"
    NETWORK_OK=0

    phase0_network_ethernet || phase0_network_wifi || true

    if [ "$NETWORK_OK" -eq 1 ]; then
        log_success "Network is available"
    else
        log_warn "Network unavailable. Online features (git clone, pacstrap) will fail."
        log_warn "You can still partition and format manually."
        if ! confirm "Continue anyway?"; then
            log_fatal "Network required. Connect via: iwctl"
        fi
    fi
}

phase0_detect_disks() {
    log_step "0.3: Disk scan"

    echo -e "${CYAN}Available disks:${RESET}"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | grep -E 'disk|NAME'
    echo ""

    # JSON for programmatic use
    lsblk -J -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null > /tmp/arch-install-disks.json || true

    # Detect Windows (NTFS + BitLocker)
    HAS_WINDOWS=0
    if lsblk -o FSTYPE 2>/dev/null | grep -q "ntfs"; then
        HAS_WINDOWS=1
        log_info "Windows partition detected (NTFS)"
    fi
    if blkid 2>/dev/null | grep -qi "bitlocker"; then
        HAS_WINDOWS=1
        log_warn "BitLocker detected — suspend BitLocker in Windows first!"
        if ! confirm "Continue? BitLocker may cause data loss."; then
            log_fatal "Suspend BitLocker in Windows and try again."
        fi
    fi

    # Detect existing ESP
    HAS_ESP=0
    local esp_guid="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
    local detected_esp
    detected_esp=$(blkid 2>/dev/null | grep -i "$esp_guid" | awk -F: '{print $1}' | head -1)
    if [ -n "$detected_esp" ]; then
        HAS_ESP=1
        INSTALL_ESP="$detected_esp"
        log_success "Existing ESP found: ${INSTALL_ESP}"
    fi
}

phase0_main() {
    log_step "PHASE 0: ENVIRONMENT DETECTION"
    load_state

    guard_phase 0 "Environment Detection" || return 0

    phase0_detect_uefi
    phase0_detect_cfxz6
    phase0_detect_network
    phase0_detect_disks

    save_phase_progress 0
    log_success "Phase 0 complete — environment scanned"
}
