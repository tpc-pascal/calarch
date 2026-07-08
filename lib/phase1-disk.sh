#!/bin/bash
# ============================================================================
# PHASE1-DISK.SH — Disk partitioning, formatting, mounting
# ----------------------------------------------------------------------------
# Tao partition layout: ESP (512MB) + swap (8GB) + Btrfs root (con lai)
# Hoac dung chung ESP neu dual-boot voi Windows
# ============================================================================

phase1_select_disk() {
    log_step "1.1: Select install disk"

    # List available disks (physical, not partitions)
    local disks=()
    local disk_names=()
    while read -r name size; do
        [ -z "$name" ] && continue
        # Skip ram, loop, sr (optical), zram
        [[ "$name" == ram* ]] && continue
        [[ "$name" == loop* ]] && continue
        [[ "$name" == sr* ]] && continue
        [[ "$name" == zram* ]] && continue
        disks+=("$name")
        disk_names+=("$name ($size)")
    done < <(lsblk -d -o NAME,SIZE -n 2>/dev/null)

    if [ ${#disks[@]} -eq 0 ]; then
        log_fatal "No disks found!"
    fi

    echo -e "${CYAN}Available install disks:${RESET}"
    local i=0
    for d in "${disk_names[@]}"; do
        echo "  $((i+1)). $d"
        i=$((i+1))
    done
    echo ""

    local choice
    read -r -p "  Select disk number (1-${#disks[@]}): " choice
    choice=$((choice - 1))
    if [ "$choice" -lt 0 ] || [ "$choice" -ge "${#disks[@]}" ]; then
        log_fatal "Invalid selection"
    fi

    INSTALL_DISK="/dev/${disks[$choice]}"

    # Verify disk exists
    if [ ! -b "$INSTALL_DISK" ]; then
        log_fatal "Disk ${INSTALL_DISK} not found"
    fi

    log_info "Selected: ${INSTALL_DISK}"

    # Dual-boot safety
    if [ "$HAS_WINDOWS" -eq 1 ]; then
        echo ""
        log_warn "WINDOWS DETECTED on this system!"
        log_warn "Selected disk: ${INSTALL_DISK}"
        log_warn "Make sure this is NOT your Windows disk!"
        echo ""
        log_info "Windows partitions (NTFS):"
        lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null | grep -iE 'ntfs|NAME'
        echo ""
        confirm_dangerous "This will DESTROY ALL DATA on ${INSTALL_DISK}. Windows data on OTHER disks is safe." || log_fatal "Aborted by user"
    else
        confirm_dangerous "This will DESTROY ALL DATA on ${INSTALL_DISK}!" || log_fatal "Aborted by user"
    fi
}

phase1_create_partitions() {
    log_step "1.2: Partitioning ${INSTALL_DISK}"

    if [ ! -b "$INSTALL_DISK" ]; then
        log_fatal "Disk ${INSTALL_DISK} not found"
    fi

    # Determine partition naming (nvme → p1, sda → 1, mmcblk → p1)
    local suffix=""
    local p=""
    if [[ "$INSTALL_DISK" == *"nvme"* ]] || [[ "$INSTALL_DISK" == *"mmcblk"* ]] || [[ "$INSTALL_DISK" == *"loop"* ]]; then
        suffix="p"
    fi

    # Wipe existing partition table
    run_cmd "Wipe partition table on ${INSTALL_DISK}" \
        sudo dd if=/dev/zero of="$INSTALL_DISK" bs=1M count=10 2>/dev/null || true
    run_cmd "Create GPT partition table" \
        sudo parted -s "$INSTALL_DISK" mklabel gpt

    # Get disk size in MB
    local disk_size_mb
    disk_size_mb=$(lsblk -d -o SIZE -b "$INSTALL_DISK" 2>/dev/null | tail -1 | numfmt --from=iec --to-unit=1024 2>/dev/null || echo 0)
    disk_size_mb=$((disk_size_mb / 1024))
    local disk_size_gb=$((disk_size_mb / 1024))

    if [ "$disk_size_gb" -lt "$MIN_DISK_SIZE_GB" ]; then
        log_fatal "Disk too small: ${disk_size_gb}GB (need >= ${MIN_DISK_SIZE_GB}GB)"
    fi

    local current_mb=1  # Start at 1MB (leave room for GPT backup)

    if [ "$HAS_ESP" -eq 1 ]; then
        # Reuse existing ESP
        log_info "Reusing existing ESP: ${INSTALL_ESP}"
        # Just create root + swap
        # ESP was already detected, find it on this disk
        INSTALL_ESP=$(blkid 2>/dev/null | grep "$INSTALL_DISK" | grep -i "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" | awk -F: '{print $1}' | head -1)
        if [ -z "$INSTALL_ESP" ]; then
            log_warn "ESP not on this disk. Creating new one."
            HAS_ESP=0
        fi
    fi

    if [ "$HAS_ESP" -eq 0 ]; then
        # Create ESP partition (512MB)
        run_cmd "Create ESP partition (${ESP_SIZE_MB}MB)" \
            sudo parted -s "$INSTALL_DISK" mkpart ESP fat32 "${current_mb}Mib" "$((current_mb + ESP_SIZE_MB))Mib"
        run_cmd "Set ESP flag" \
            sudo parted -s "$INSTALL_DISK" set 1 esp on
        INSTALL_ESP="${INSTALL_DISK}${suffix}1"
        current_mb=$((current_mb + ESP_SIZE_MB))
    fi

    # Find next partition number
    local part_num=1
    if [ "$HAS_ESP" -eq 1 ]; then
        # Find the last partition number
        part_num=$(lsblk -n -o NAME "$INSTALL_DISK" 2>/dev/null | grep -c "$(basename "$INSTALL_DISK")${suffix}")
        part_num=$((part_num + 1))
    fi

    # Create swap partition (8GB)
    local swap_start=$current_mb
    local swap_end=$((current_mb + SWAP_SIZE_GB * 1024))
    run_cmd "Create swap partition (${SWAP_SIZE_GB}GB)" \
        sudo parted -s "$INSTALL_DISK" mkpart swap linux-swap "${swap_start}Mib" "${swap_end}Mib"
    INSTALL_SWAP="${INSTALL_DISK}${suffix}${part_num}"
    part_num=$((part_num + 1))
    current_mb=$swap_end

    # Create root partition (rest of disk)
    run_cmd "Create root partition (remaining)" \
        sudo parted -s "$INSTALL_DISK" mkpart root btrfs "${current_mb}Mib" 100%
    INSTALL_ROOT="${INSTALL_DISK}${suffix}${part_num}"

    # Wait for kernel to update partition table
    sleep 2
    sudo partprobe "$INSTALL_DISK" 2>/dev/null || true
    sleep 1

    log_success "Partitions created:"
    log_info "  ESP:   ${INSTALL_ESP}"
    log_info "  Swap:  ${INSTALL_SWAP}"
    log_info "  Root:  ${INSTALL_ROOT}"
}

phase1_format() {
    log_step "1.3: Formatting partitions"

    # Format ESP (only if we created it)
    if [ "$HAS_ESP" -eq 0 ]; then
        run_cmd "Format ESP as FAT32" \
            sudo mkfs.fat -F32 "$INSTALL_ESP"
    else
        log_info "ESP already formatted, skipping"
    fi

    # Format swap
    run_cmd "Format swap" \
        sudo mkswap "$INSTALL_SWAP"

    # Format root as Btrfs
    run_cmd "Format root as Btrfs" \
        sudo mkfs.btrfs -f "$INSTALL_ROOT"
}

phase1_create_subvolumes() {
    log_step "1.4: Creating Btrfs subvolumes"

    # Mount root temporarily
    run_cmd "Mount root temporarily" \
        sudo mount "$INSTALL_ROOT" /mnt

    # Create subvolumes
    run_cmd "Create @ subvolume" \
        sudo btrfs subvolume create /mnt/@
    run_cmd "Create @home subvolume" \
        sudo btrfs subvolume create /mnt/@home
    run_cmd "Create @snapshots subvolume" \
        sudo btrfs subvolume create /mnt/@snapshots

    # Unmount
    run_cmd "Unmount root" \
        sudo umount /mnt
}

phase1_mount() {
    log_step "1.5: Mounting filesystems"

    # Mount root subvolume
    run_cmd "Mount @ to /mnt" \
        sudo mount -o compress=zstd:3,noatime,subvol=@ "$INSTALL_ROOT" /mnt

    # Create mount directories
    run_cmd "Create /mnt/home" \
        sudo mkdir -p /mnt/home
    run_cmd "Create /mnt/.snapshots" \
        sudo mkdir -p /mnt/.snapshots

    # Mount home
    run_cmd "Mount @home" \
        sudo mount -o compress=zstd:3,noatime,subvol=@home "$INSTALL_ROOT" /mnt/home

    # Mount snapshots
    run_cmd "Mount @snapshots" \
        sudo mount -o compress=zstd:3,noatime,subvol=@snapshots "$INSTALL_ROOT" /mnt/.snapshots

    # Mount ESP
    run_cmd "Mount ESP to /mnt/boot" \
        sudo mkdir -p /mnt/boot && sudo mount "$INSTALL_ESP" /mnt/boot

    # Enable swap
    run_cmd "Enable swap" \
        sudo swapon "$INSTALL_SWAP"

    log_success "All filesystems mounted:"
    mount | grep -E '/mnt|swap' | while read -r line; do
        log_info "  ${line}"
    done
}

phase1_select_mode() {
    log_step "1.0: Select installation mode"

    echo -e "${CYAN}Select installation mode:${RESET}"
    echo "  1) Whole disk (wipe) — wipe entire disk, auto-partition (recommended)"
    echo "  2) Existing partition — install to existing partition, keep others"
    echo ""

    local choice
    read -r -p "  Select mode (1-2): " choice

    case "$choice" in
        2) INSTALL_MODE="partition" ;;
        *) INSTALL_MODE="disk" ;;
    esac

    log_info "Mode: ${INSTALL_MODE}"
    save_state
}

phase1_select_partition() {
    log_step "1.1: Select install partition"

    local parts=()
    local part_lines=()

    while read -r name size fstype label mountpoint; do
        [ -z "$name" ] && continue
        [[ "$name" == ram* ]] && continue
        [[ "$name" == loop* ]] && continue
        [[ "$name" == sr* ]] && continue
        [[ "$name" == zram* ]] && continue

        [ -n "$mountpoint" ] && continue

        parts+=("$name")
        local desc="/dev/${name}  ${size}"
        [ -n "$fstype" ] && desc+="  ${fstype}" || desc+="  ?"
        [ -n "$label" ] && desc+="  [${label}]"
        part_lines+=("$desc")
    done < <(lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT -n -l 2>/dev/null)

    if [ ${#parts[@]} -eq 0 ]; then
        log_warn "No available partitions found. Falling back to whole-disk mode."
        INSTALL_MODE="disk"
        save_state
        return 1
    fi

    echo -e "${CYAN}Available partitions:${RESET}"
    local i=0
    for d in "${part_lines[@]}"; do
        echo "  $((i+1)). $d"
        i=$((i+1))
    done
    echo ""

    local choice
    read -r -p "  Select partition number (1-${#parts[@]}): " choice
    choice=$((choice - 1))
    if [ "$choice" -lt 0 ] || [ "$choice" -ge "${#parts[@]}" ]; then
        log_fatal "Invalid selection"
    fi

    INSTALL_ROOT="/dev/${parts[$choice]}"

    if [ ! -b "$INSTALL_ROOT" ]; then
        log_fatal "Partition ${INSTALL_ROOT} not found"
    fi

    local basename
    basename=$(echo "${parts[$choice]}" | sed 's/[0-9]*$//; s/p$//')
    INSTALL_DISK="/dev/${basename}"

    log_info "Selected root: ${INSTALL_ROOT} (on ${INSTALL_DISK})"

    local size_bytes
    size_bytes=$(lsblk -d -o SIZE -b "${INSTALL_ROOT}" 2>/dev/null | tail -1 | numfmt --from=iec 2>/dev/null || echo 0)
    local size_gb=$((size_bytes / 1073741824))
    if [ "$size_gb" -lt "$MIN_DISK_SIZE_GB" ]; then
        log_fatal "Partition too small: ${size_gb}GB (need >= ${MIN_DISK_SIZE_GB}GB)"
    fi

    # Windows/NTFS warning
    if [ "${HAS_WINDOWS:-0}" -eq 1 ]; then
        log_warn "Windows detected on this system!"
        local sel_fstype
        sel_fstype=$(lsblk -n -o FSTYPE "${INSTALL_ROOT}" 2>/dev/null)
        if [ "$sel_fstype" = "ntfs" ]; then
            log_fatal "Cannot install to an NTFS partition. This would destroy Windows data.\nFree up space in Windows (Disk Management → Shrink Volume) and create a new empty partition."
        fi
        echo -e ""
        log_info "Windows partitions (NTFS):"
        lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null | grep -iE 'ntfs|NAME'
        echo -e "${YELLOW}Make sure you selected the RIGHT partition — NOT your Windows C: drive!${RESET}"
    fi

    confirm_dangerous "This will FORMAT ${INSTALL_ROOT} as Btrfs. ALL DATA on this partition will be DESTROYED.\nOther partitions on ${INSTALL_DISK} will NOT be touched." || log_fatal "Aborted by user"

    save_state
}

phase1_detect_esp() {
    log_step "1.2: Detect existing ESP"

    INSTALL_ESP=""
    HAS_ESP=0

    local esp_list=()
    local esp_lines=()

    while read -r line; do
        [ -z "$line" ] && continue
        local dev
        dev=$(echo "$line" | awk -F: '{print $1}')
        [ -z "$dev" ] && continue
        [ ! -b "$dev" ] && continue
        local mnt
        mnt=$(lsblk -n -o MOUNTPOINT "$dev" 2>/dev/null)
        [ -n "$mnt" ] && continue
        esp_list+=("$dev")
        local size
        size=$(lsblk -n -o SIZE "$dev" 2>/dev/null || echo "?")
        esp_lines+=("${dev}  (${size})")
    done < <(blkid 2>/dev/null | grep -i "PART_ENTRY_TYPE=\"c12a7328-f81f-11d2-ba4b-00a0c93ec93b\"")

    if [ ${#esp_list[@]} -eq 0 ]; then
        log_warn "No ESP found on any disk!"
        echo ""
        echo -e "${CYAN}Options:${RESET}"
        echo "  1) Create ESP on a disk — will wipe that disk's partition table"
        echo "  2) Skip — I will handle bootloader manually"
        echo ""
        read -r -p "  Select (1-2): " esp_choice

        if [ "$esp_choice" = "1" ]; then
            phase1_create_esp_disk
        else
            log_warn "Skipping ESP. Bootloader may not work without manual setup."
            INSTALL_ESP=""
            HAS_ESP=0
        fi
    else
        echo -e "${CYAN}Found ESP(s):${RESET}"
        local i=0
        for d in "${esp_lines[@]}"; do
            echo "  $((i+1)). $d"
            i=$((i+1))
        done
        echo ""

        if [ ${#esp_list[@]} -eq 1 ]; then
            read -r -p "  Use this ESP? [Y/n]: " use_esp
            case "$use_esp" in
                [nN]*) INSTALL_ESP="" ; HAS_ESP=0 ;;
                *) INSTALL_ESP="${esp_list[0]}" ; HAS_ESP=1 ;;
            esac
        else
            read -r -p "  Select ESP number (1-${#esp_list[@]}), or 0 to skip: " esp_choice
            if [ -n "$esp_choice" ] && [ "$esp_choice" -gt 0 ] && [ "$esp_choice" -le "${#esp_list[@]}" ]; then
                INSTALL_ESP="${esp_list[$((esp_choice-1))]}"
                HAS_ESP=1
            else
                INSTALL_ESP=""
                HAS_ESP=0
            fi
        fi

        if [ -n "$INSTALL_ESP" ]; then
            log_success "Using ESP: ${INSTALL_ESP}"
        else
            log_warn "No ESP selected. Bootloader install will be skipped."
        fi
    fi

    save_state
}

phase1_create_esp_disk() {
    log_step "1.2a: Create ESP on disk"

    local disks=()
    local disk_lines=()
    while read -r name size; do
        [ -z "$name" ] && continue
        [[ "$name" == ram* ]] && continue
        [[ "$name" == loop* ]] && continue
        [[ "$name" == sr* ]] && continue
        [[ "$name" == zram* ]] && continue
        disks+=("$name")
        disk_lines+=("$name ($size)")
    done < <(lsblk -d -o NAME,SIZE -n 2>/dev/null)

    if [ ${#disks[@]} -eq 0 ]; then
        log_fatal "No disks found for ESP creation!"
    fi

    echo -e "${CYAN}Select disk for ESP:${RESET}"
    local i=0
    for d in "${disk_lines[@]}"; do
        echo "  $((i+1)). $d"
        i=$((i+1))
    done
    echo ""

    local choice
    read -r -p "  Select disk number (1-${#disks[@]}): " choice
    choice=$((choice - 1))
    if [ "$choice" -lt 0 ] || [ "$choice" -ge "${#disks[@]}" ]; then
        log_fatal "Invalid selection"
    fi

    local esp_disk="/dev/${disks[$choice]}"
    log_info "Will create ESP on: ${esp_disk}"

    confirm_dangerous "This will WIPE the partition table on ${esp_disk} and create a single ESP (${ESP_SIZE_MB}MB)!\nAll data on ${esp_disk} will be DESTROYED." || log_fatal "Aborted by user"

    local suffix=""
    if [[ "$esp_disk" == *"nvme"* ]] || [[ "$esp_disk" == *"mmcblk"* ]]; then
        suffix="p"
    fi

    run_cmd "Wipe partition table" \
        sudo dd if=/dev/zero of="$esp_disk" bs=1M count=10 2>/dev/null || true
    run_cmd "Create GPT" \
        sudo parted -s "$esp_disk" mklabel gpt
    run_cmd "Create ESP (${ESP_SIZE_MB}MB)" \
        sudo parted -s "$esp_disk" mkpart ESP fat32 1MiB "${ESP_SIZE_MB}MiB"
    run_cmd "Set ESP flag" \
        sudo parted -s "$esp_disk" set 1 esp on

    sleep 2
    sudo partprobe "$esp_disk" 2>/dev/null || true
    sleep 1

    INSTALL_ESP="${esp_disk}${suffix}1"
    run_cmd "Format ESP as FAT32" \
        sudo mkfs.fat -F32 "$INSTALL_ESP"
    HAS_ESP=0
    log_success "ESP created: ${INSTALL_ESP}"
    save_state
}

phase1_setup_swap() {
    log_step "1.3: Configure swap"

    echo -e "${CYAN}Swap configuration:${RESET}"
    echo "  1) Swapfile — ${SWAPFILE_SIZE_MB}MB on Btrfs (default)"
    echo "  2) Existing swap partition — auto-detect"
    echo "  3) No swap"
    echo ""

    read -r -p "  Select (1-3): " swap_choice

    case "$swap_choice" in
        2)
            local swap_dev
            swap_dev=$(blkid 2>/dev/null | grep -i 'TYPE="swap"' | head -1 | awk -F: '{print $1}')
            if [ -n "$swap_dev" ] && [ -b "$swap_dev" ]; then
                log_info "Found swap partition: ${swap_dev}"
                read -r -p "  Use this swap partition? [Y/n]: " use_swap
                case "$use_swap" in
                    [nN]*) INSTALL_SWAP="" ; USE_SWAPFILE=1 ;;
                    *) INSTALL_SWAP="$swap_dev" ; USE_SWAPFILE=0
                       log_success "Using swap partition: ${INSTALL_SWAP}" ;;
                esac
            else
                log_warn "No swap partition found. Using swapfile."
                USE_SWAPFILE=1
            fi
            ;;
        3)
            USE_SWAPFILE=0
            INSTALL_SWAP=""
            log_info "No swap will be configured"
            ;;
        *)
            USE_SWAPFILE=1
            INSTALL_SWAPFILE="$SWAPFILE_PATH"
            log_info "Using swapfile: ${INSTALL_SWAPFILE} (${SWAPFILE_SIZE_MB}MB)"
            ;;
    esac

    save_state
}

phase1_format_root() {
    log_step "1.4: Format root partition"

    run_cmd "Format ${INSTALL_ROOT} as Btrfs" \
        sudo mkfs.btrfs -f "$INSTALL_ROOT"
}

phase1_mount_partition() {
    log_step "1.5: Mount filesystems"

    run_cmd "Mount @ subvolume to /mnt" \
        sudo mount -o compress=zstd:3,noatime,subvol=@ "$INSTALL_ROOT" /mnt

    run_cmd "Create /mnt/home" \
        sudo mkdir -p /mnt/home
    run_cmd "Create /mnt/.snapshots" \
        sudo mkdir -p /mnt/.snapshots

    run_cmd "Mount @home" \
        sudo mount -o compress=zstd:3,noatime,subvol=@home "$INSTALL_ROOT" /mnt/home

    run_cmd "Mount @snapshots" \
        sudo mount -o compress=zstd:3,noatime,subvol=@snapshots "$INSTALL_ROOT" /mnt/.snapshots

    if [ -n "$INSTALL_ESP" ]; then
        run_cmd "Mount ESP to /mnt/boot" \
            sudo mkdir -p /mnt/boot && sudo mount "$INSTALL_ESP" /mnt/boot
    else
        log_warn "No ESP mounted — bootloader install skipped"
    fi

    if [ "$USE_SWAPFILE" -eq 0 ] && [ -n "$INSTALL_SWAP" ]; then
        run_cmd "Enable swap partition" \
            sudo swapon "$INSTALL_SWAP"
    fi

    log_success "All filesystems mounted:"
    mount | grep -E '/mnt|swap' | while read -r line; do
        log_info "  ${line}"
    done
}

phase1_main() {
    log_step "PHASE 1: DISK SETUP"
    load_state

    guard_phase 1 "Disk Setup" || return 0

    phase1_select_mode

    if [ "$INSTALL_MODE" = "partition" ]; then
        phase1_select_partition || {
            INSTALL_MODE="disk"
            save_state
        }
    fi

    if [ "$INSTALL_MODE" = "disk" ]; then
        phase1_select_disk
        phase1_create_partitions
        phase1_format
        phase1_create_subvolumes
        phase1_mount
    else
        phase1_detect_esp
        phase1_setup_swap
        phase1_format_root
        phase1_create_subvolumes
        phase1_mount_partition
    fi

    save_phase_progress 1
    log_success "Phase 1 complete — disk ready"
}
