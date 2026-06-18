#!/bin/bash
# ============================================================================
# CONFIG.SH — Default configuration cho Arch Linux Installer
# ----------------------------------------------------------------------------
# Cac gia tri mac dinh co the ghi de bang bien moi truong
# ============================================================================

# --- System ---
DEFAULT_HOSTNAME="${ARCHCAL_HOSTNAME:-cfxz6-arch}"
DEFAULT_TIMEZONE="${ARCHCAL_TIMEZONE:-Asia/Ho_Chi_Minh}"
DEFAULT_LOCALE="${ARCHCAL_LOCALE:-en_US.UTF-8}"

# --- User ---
DEFAULT_USER="${ARCHCAL_USER:-pascal}"

# --- Install mode ---
DEFAULT_INSTALL_MODE="${ARCHCAL_INSTALL_MODE:-disk}"  # "disk" or "partition"

# --- Disk ---
MIN_DISK_SIZE_GB="${ARCHCAL_MIN_DISK_GB:-20}"
SWAP_SIZE_GB="${ARCHCAL_SWAP_GB:-8}"
ESP_SIZE_MB="${ARCHCAL_ESP_MB:-512}"

# --- Swapfile (for partition mode) ---
SWAPFILE_SIZE_MB="${ARCHCAL_SWAPFILE_MB:-8192}"
SWAPFILE_PATH="${ARCHCAL_SWAPFILE_PATH:-/.swapfile}"

# --- Kernel params for CF-XZ6 ---
KERNEL_PARAMS="nowatchdog processor.max_cstate=4 intel_idle.max_cstate=4 i915.enable_fbc=1 i915.enable_psr=1 i915.enable_rc6=1 i915.fastboot=1 mitigations=off pcie_aspm=force"

# --- Packages to pacstrap ---
BASE_PACKAGES=(
    base base-devel
    linux-zen linux-zen-headers
    linux-firmware intel-ucode
    btrfs-progs
    git curl vim
    networkmanager iwd dhcpcd
    whiptail sudo zstd
    man-db man-pages
    bluez bluez-utils
    pipewire pipewire-pulse wireplumber
)
