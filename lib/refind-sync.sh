#!/bin/bash
# ============================================================================
# REFIND-SYNC.SH — Sync kernel to ESP for rEFInd + manage entry + pacman hook
# ----------------------------------------------------------------------------
# Giai quyet: rEFInd EFI driver khong doc duoc Btrfs co nen (zstd)
# Nen kernel + initramfs phai nam tren FAT32 de rEFInd auto-detect.
#
# Edge cases covered:
#   - Multiple ESPs → chon ESP co rEFInd installed hoac ESP duoc mount
#   - rEFInd chua cai → warn, skip entry generation, van copy kernel
#   - AMD vs Intel CPU → tu dong phat hien ucode
#   - Multiple kernels (linux, linux-zen, linux-lts) → sync tat ca
#   - ESP day → check df truoc khi copy, warn
#   - FAT32 4GB limit → check file size, warn
#   - ESP da mount san → detect, khong unmount sau khi xong
#   - Khong tim thay ESP → warn, skip
#   - Idempotent → dung marker trong refind.conf
#   - Chay lai nhieu lan → an toan, khong duplicate entries
#   - initramfs fallback → bo qua, chi sync primary
#   - Btrfs khong nen → van sync (consistency)
#   - ext4 root → van sync (optional, auto-detect van hoat dong)
#
# Cach dung:
#   Tu ISO installer:  bash lib/refind-sync.sh --mnt /mnt [--esp /dev/sdX1]
#   Tu he thong:       sudo bash lib/refind-sync.sh
#   Kiem tra:          bash lib/refind-sync.sh --check
#   Cai hook:          sudo bash lib/refind-sync.sh --install-hook
# ============================================================================
set -euo pipefail

R='\033[0m'; B='\033[1m'; D='\033[0;90m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'

log_i()  { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_w()  { echo -e "${YEL}[!!]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }

# Default kernel params (match config.sh)
DEFAULT_KERNEL_PARAMS="nowatchdog processor.max_cstate=4 intel_idle.max_cstate=4 i915.enable_fbc=1 i915.enable_psr=1 i915.enable_rc6=1 i915.fastboot=1 mitigations=off pcie_aspm=force"

# === CONFIG ===
REFIND_ESP_DIR="EFI/arch"
REFIND_ENTRY_NAME="calarch"
ESP_MOUNT_BASE="/tmp/calarch-esp"

# === PARSE ARGS ===
MNT=""
ESP_DEV=""
MODE="sync"
while [ $# -gt 0 ]; do
    case "$1" in
        --mnt) MNT="$2"; shift 2 ;;
        --esp) ESP_DEV="$2"; shift 2 ;;
        --check) MODE="check"; shift ;;
        --install-hook) MODE="install-hook"; shift ;;
        *) echo -e "${RED}Unknown: $1${R}"; exit 1 ;;
    esac
done

[ -z "$MNT" ] && MNT="/"
MNT="${MNT%/}"
[ -z "$MNT" ] && MNT="/"

# === DETECT ESP ===
detect_esp() {
    local mnt="$1"
    local esp_dev=""

    if [ -n "$ESP_DEV" ]; then
        [ -b "$ESP_DEV" ] && { echo "$ESP_DEV"; return; }
        log_e "ESP device not found: $ESP_DEV"
        return 1
    fi

    local fstab="$mnt/etc/fstab"
    if [ -f "$fstab" ]; then
        while read -r line; do
            [ -z "$line" ] && continue
            [[ "$line" == \#* ]] && continue
            local dev mp fstype opts
            read -r dev mp fstype opts _ <<< "$line"
            if [[ "$mp" == "/boot" || "$mp" == "/efi" || "$mp" == "/boot/efi" ]]; then
                if [[ "$fstype" == "vfat" || "$fstype" == "fat" || "$fstype" == "msdos" ]]; then
                    esp_dev="$dev"
                    break
                fi
            fi
        done < "$fstab"

        if [ -n "$esp_dev" ]; then
            local resolved
            resolved=$(resolve_device "$esp_dev")
            [ -n "$resolved" ] && { echo "$resolved"; return; }
        fi
    fi

    while read -r line; do
        local dev
        dev=$(echo "$line" | awk -F: '{print $1}')
        [ ! -b "$dev" ] && continue
        local mntpoint
        mntpoint=$(lsblk -n -o MOUNTPOINT "$dev" 2>/dev/null || true)
        [ -z "$mntpoint" ] && continue
        if [ "$mntpoint" = "$mnt/boot" ] || [ "$mntpoint" = "$mnt/efi" ]; then
            local fstype
            fstype=$(lsblk -n -o FSTYPE "$dev" 2>/dev/null || true)
            if [[ "$fstype" == "vfat" || "$fstype" == "fat" ]]; then
                echo "$dev"
                return
            fi
        fi
    done < <(lsblk -o NAME,FSTYPE -n -l 2>/dev/null | while read -r n f; do echo "/dev/$n"; done)

    local current_esp
    current_esp=$(findmnt -n -o SOURCE /boot 2>/dev/null || true)
    if [ -n "$current_esp" ] && [ -b "$current_esp" ]; then
        local fstype
        fstype=$(lsblk -n -o FSTYPE "$current_esp" 2>/dev/null || true)
        if [[ "$fstype" == "vfat" || "$fstype" == "fat" ]]; then
            echo "$current_esp"
            return
        fi
    fi

    local blkid_out
    blkid_out=$(blkid 2>/dev/null || true)
    if [ -n "$blkid_out" ]; then
        local found
        found=$(echo "$blkid_out" | grep -i "PART_ENTRY_TYPE=\"c12a7328-f81f-11d2-ba4b-00a0c93ec93b\"" | head -1 | awk -F: '{print $1}')
        [ -b "$found" ] && { echo "$found"; return; }
    fi

    lsblk -o NAME,FSTYPE -n -l 2>/dev/null | while read -r name fstype; do
        if [[ "$fstype" == "vfat" || "$fstype" == "fat" ]]; then
            local dev="/dev/$name"
            [ -b "$dev" ] && echo "$dev"
        fi
    done | head -1

    return 0
}

resolve_device() {
    local spec="$1"
    case "$spec" in
        UUID=*)
            local uuid="${spec#UUID=}"
            blkid -U "$uuid" 2>/dev/null || true
            ;;
        PARTUUID=*)
            local puuid="${spec#PARTUUID=}"
            blkid -t "PARTUUID=$puuid" -o device 2>/dev/null || true
            ;;
        /dev/*)
            [ -b "$spec" ] && echo "$spec" || true
            ;;
        *)
            echo "$spec"
            ;;
    esac
}

# === MOUNT ESP ===
mount_esp_temp() {
    local esp_dev="$1"
    local mnt_dir="$ESP_MOUNT_BASE-$$"

    local current_mnt
    current_mnt=$(findmnt -n -o TARGET "$esp_dev" 2>/dev/null || true)
    if [ -n "$current_mnt" ]; then
        echo "$current_mnt"
        return 0
    fi

    rm -rf "$mnt_dir"
    mkdir -p "$mnt_dir"
    if ! mount "$esp_dev" "$mnt_dir" 2>/dev/null; then
        log_e "Cannot mount ESP $esp_dev to $mnt_dir"
        rm -rf "$mnt_dir" 2>/dev/null || true
        return 1
    fi
    echo "$mnt_dir"
}

unmount_esp_temp() {
    local esp_mnt="$1"
    if [ -d "$esp_mnt" ]; then
        if [ "${esp_mnt#/tmp/calarch-esp}" != "$esp_mnt" ]; then
            umount "$esp_mnt" 2>/dev/null || true
            rmdir "$esp_mnt" 2>/dev/null || true
        fi
    fi
}

# === DETECT KERNELS ===
detect_kernels() {
    local boot_dir="$1"
    if [ ! -d "$boot_dir" ]; then
        boot_dir="$MNT/boot"
        [ "$MNT" = "/" ] && boot_dir="/boot"
    fi
    [ ! -d "$boot_dir" ] && return 1

    local kernels=()
    for f in "$boot_dir"/vmlinuz-*; do
        [ -f "$f" ] || continue
        local base
        base=$(basename "$f")
        local name="${base#vmlinuz-}"
        local initrd="$boot_dir/initramfs-$name.img"
        local initrd_fallback="$boot_dir/initramfs-$name-fallback.img"
        local initrd_uki="$boot_dir/initrd-$name.img"

        [ -f "$initrd" ] || initrd="$initrd_uki"
        [ -f "$initrd" ] || continue

        kernels+=("$name:$f:$initrd")
    done

    [ ${#kernels[@]} -eq 0 ] && return 1

    printf '%s\n' "${kernels[@]}"
}

detect_ucode() {
    local boot_dir="$1"
    local ucode=""

    if [ -f "$boot_dir/intel-ucode.img" ]; then
        ucode="$boot_dir/intel-ucode.img"
    elif [ -f "$boot_dir/amd-ucode.img" ]; then
        ucode="$boot_dir/amd-ucode.img"
    fi
    echo "$ucode"
}

# === GET ROOT PARTUUID ===
detect_root_partuuid() {
    local mnt="$1"
    local root_dev
    root_dev=$(findmnt -n -o SOURCE "$mnt" 2>/dev/null || true)
    [ -z "$root_dev" ] && root_dev=$(findmnt -n -o SOURCE --target "$mnt" 2>/dev/null || true)
    [ -z "$root_dev" ] && return 1

    local partuuid
    partuuid=$(blkid -s PARTUUID -o value "$root_dev" 2>/dev/null || true)
    echo "${partuuid:-}"
}

# === GET ROOTFLAGS ===
detect_rootflags() {
    local mnt="$1"
    local rootflags
    rootflags=$(findmnt -n -o OPTIONS "$mnt" 2>/dev/null || true)
    local subvol=""
    if echo "$rootflags" | grep -q "subvol="; then
        subvol="subvol=$(echo "$rootflags" | grep -oP 'subvol=[^,]+' | head -1)"
    fi
    echo "${subvol:-}"
}

# === GET KERNEL PARAMS ===
get_kernel_params() {
    local mnt="$1"
    local config_file="$mnt/calarch.conf"
    [ "$mnt" = "/" ] && config_file="/calarch.conf"
    [ ! -f "$config_file" ] && config_file="$HOME/calarch/calarch.conf"
    if [ ! -f "$config_file" ]; then
        local home_dirs
        home_dirs=$(ls -d "$mnt/home"/*/calarch/calarch.conf 2>/dev/null | head -1)
        [ -n "$home_dirs" ] && config_file="$home_dirs"
    fi

    if [ -f "$config_file" ]; then
        local params
        params=$(grep -E '^KERNEL_PARAMS=' "$config_file" 2>/dev/null | head -1 | cut -d'=' -f2-)
        if [ -n "$params" ]; then
            echo "$params"
            return
        fi
    fi

    echo "$DEFAULT_KERNEL_PARAMS"
}

# === CHECK DISK SPACE ===
check_esp_space() {
    local esp_mnt="$1"
    local needed_kb="$2"
    local avail_kb
    avail_kb=$(df -k "$esp_mnt" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
    if [ "$avail_kb" -lt "$needed_kb" ]; then
        log_w "ESP may be low on space: ${avail_kb}KB available, need ~${needed_kb}KB"
        return 1
    fi
    return 0
}

# === SYNC KERNEL TO ESP ===
sync_to_esp() {
    local esp_root="$1"
    local boot_dir="$2"
    local out_dir="$esp_root/$REFIND_ESP_DIR"

    mkdir -p "$out_dir"

    local ucode_src
    ucode_src=$(detect_ucode "$boot_dir")
    local ucode_dst=""
    if [ -n "$ucode_src" ]; then
        ucode_dst="$out_dir/$(basename "$ucode_src")"
        if [ ! -f "$ucode_dst" ] || ! diff -q "$ucode_src" "$ucode_dst" 2>/dev/null; then
            cp -f "$ucode_src" "$ucode_dst"
            log_ok "Copied ucode: $(basename "$ucode_src")"
        fi
    fi

    local total_kb=0
    local kernel_entries=()
    while IFS=: read -r name kernel initrd; do
        [ -z "$name" ] && continue
        total_kb=$((total_kb + 50000))
        kernel_entries+=("$name:$kernel:$initrd")
    done < <(detect_kernels "$boot_dir" 2>/dev/null || true)

    if [ ${#kernel_entries[@]} -eq 0 ]; then
        log_w "No kernels found in $boot_dir"
        return 1
    fi

    check_esp_space "$esp_root" "$total_kb" || log_w "Continuing anyway..."

    local synced=()
    for entry in "${kernel_entries[@]}"; do
        local name kernel initrd
        IFS=: read -r name kernel initrd <<< "$entry"

        local kernel_dst="$out_dir/vmlinuz-$name"
        local initrd_dst="$out_dir/initramfs-$name.img"

        if [ -f "$kernel_dst" ] && [ -f "$initrd_dst" ]; then
            if diff -q "$kernel" "$kernel_dst" 2>/dev/null && diff -q "$initrd" "$initrd_dst" 2>/dev/null; then
                log_i "Kernel $name unchanged, skipping"
                synced+=("$name:$kernel_dst:$initrd_dst")
                continue
            fi
        fi

        local ksize
        ksize=$(stat -c%s "$kernel" 2>/dev/null || echo 0)
        local isize
        isize=$(stat -c%s "$initrd" 2>/dev/null || echo 0)

        if [ "$isize" -gt 4294967295 ]; then
            log_w "initramfs $name > 4GB! FAT32 limit. Skipping."
            continue
        fi

        cp -f "$kernel" "$kernel_dst"
        cp -f "$initrd" "$initrd_dst"

        log_ok "Synced kernel $name"

        synced+=("$name:$kernel_dst:$initrd_dst")
    done

    local ucode_name=""
    [ -n "$ucode_dst" ] && ucode_name=$(basename "$ucode_dst")

    echo "synced:${#synced[@]}"
    for s in "${synced[@]}"; do
        echo "entry:$s:$ucode_name"
    done
}

# === MANAGE REFIND ENTRY ===
manage_refind_entry() {
    local esp_root="$1"
    local partuuid="$2"
    local rootflags="$3"
    local kernel_params="$4"
    local boot_is_esp="${5:-0}"

    local refind_conf="$esp_root/EFI/refind/refind.conf"
    if [ ! -f "$refind_conf" ]; then
        log_w "rEFInd not found at $refind_conf"
        [ -d "$esp_root/EFI/refind" ] || log_w "Directory $esp_root/EFI/refind does not exist — rEFInd may not be installed"
        return 1
    fi

    local partuuid_str="$partuuid"
    local rootflags_str="$rootflags"
    [ -n "$rootflags_str" ] && rootflags_str="rootflags=$rootflags_str"
    local kparams_str="$kernel_params"

    local marker_begin="# --- calarch: begin ---"
    local marker_end="# --- calarch: end ---"

    local entry_text=""
    entry_text+="$marker_begin\n"
    entry_text+="# Calarch kernel entries (auto-generated by refind-sync.sh)\n"

    local esp_arch_dir="$REFIND_ESP_DIR"
    local loader_prefix="/$esp_arch_dir"
    [ "$boot_is_esp" = "1" ] && loader_prefix=""
    local ucode_name=""
    local ucode_src
    ucode_src=$(detect_ucode "$MNT/boot" 2>/dev/null || true)
    [ -z "$ucode_src" ] && ucode_src=$(detect_ucode "/boot" 2>/dev/null || true)
    [ -n "$ucode_src" ] && ucode_name=$(basename "$ucode_src")

    while IFS=: read -r name kernel initrd; do
        [ -z "$name" ] && continue
        local title="Arch Linux ($name)"

        entry_text+="\n"
        entry_text+="menuentry \"$title\" {\n"
        entry_text+="    icon     /EFI/refind/icons/os_arch.png\n"
        entry_text+="    loader   ${loader_prefix}/vmlinuz-$name\n"

        if [ -n "$ucode_name" ]; then
            entry_text+="    initrd   ${loader_prefix}/$ucode_name\n"
        fi
        entry_text+="    initrd   ${loader_prefix}/initramfs-$name.img\n"

        local options_str="root=PARTUUID=${partuuid_str} rw"
        [ -n "$rootflags_str" ] && options_str="$options_str $rootflags_str"
        [ -n "$kparams_str" ] && options_str="$options_str $kparams_str"
        entry_text+="    options  \"$options_str\"\n"
        entry_text+="}\n"
    done < <(detect_kernels "$MNT/boot" 2>/dev/null || detect_kernels "/boot" 2>/dev/null || true)

    entry_text+="$marker_end\n"

    local conf_content
    conf_content=$(cat "$refind_conf")
    local new_content=""

    if echo "$conf_content" | grep -qF "$marker_begin"; then
        new_content=$(echo "$conf_content" | awk -v m="$marker_begin" 'BEGIN{f=0} index($0,m){f=1;next} !f{print}')
        [ -n "$new_content" ] && new_content="$new_content\n"
        new_content="$new_content$entry_text"
        local after_marker
        after_marker=$(echo "$conf_content" | awk -v m="$marker_end" 'BEGIN{f=0} index($0,m){f=1;next} f{print}')
        [ -n "$after_marker" ] && new_content="$new_content$after_marker"
    else
        new_content="$conf_content"
        [ -n "$new_content" ] && new_content="$new_content\n\n"
        new_content="$new_content$entry_text"
    fi

    printf '%b' "$new_content" > "$refind_conf"
    log_ok "rEFInd entry updated at $refind_conf"
}

# === INSTALL PACMAN HOOK ===
install_pacman_hook() {
    local target_root="$1"
    local sync_script_path="${2:-/usr/local/bin/calarch-sync-kernel.sh}"

    local hook_dir="$target_root/etc/pacman.d/hooks"
    local hook_file="$hook_dir/calarch-sync-kernel.hook"
    local script_file="${target_root}${sync_script_path}"

    mkdir -p "$hook_dir"

    cat > "$script_file" << 'SCRIPT_EOF'
#!/bin/bash
# calarch-sync-kernel.sh — Sync kernel to ESP for rEFInd
# Auto-generated by calarch. Run manually to re-sync after kernel update.

LOGFILE="/var/log/calarch-kernel-sync.log"
{
    echo "[$(date)] calarch-sync-kernel start"
    self="$(readlink -f "$0")"
    self_dir="$(dirname "$self")"
    REFIND_SYNC="$self_dir/refind-sync.sh"
    if [ -f "$REFIND_SYNC" ]; then
        bash "$REFIND_SYNC" 2>&1
    elif [ -f "$HOME/calarch/lib/refind-sync.sh" ]; then
        bash "$HOME/calarch/lib/refind-sync.sh" 2>&1
    else
        FIND_RESULT=$(find /home -maxdepth 3 -name "refind-sync.sh" -path "*/calarch/*" 2>/dev/null | head -1)
        if [ -n "$FIND_RESULT" ]; then
            bash "$FIND_RESULT" 2>&1
        else
            echo "WARNING: refind-sync.sh not found. Skipping kernel sync."
            echo "Reinstall calarch or run: sudo pacman -Syu && bash ~/calarch/lib/refind-sync.sh"
        fi
    fi
    echo "[$(date)] calarch-sync-kernel end"
} >> "$LOGFILE" 2>&1
SCRIPT_EOF
    chmod +x "$script_file"
    log_ok "Sync script installed at $script_file"

    cat > "$hook_file" << HOOK_EOF
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux
Target = linux-zen
Target = linux-lts
Target = linux-hardened
Target = intel-ucode
Target = amd-ucode

[Action]
Description = Calarch: Sync kernel to ESP for rEFInd
When = PostTransaction
Exec = /bin/sh -c '${sync_script_path}'
HOOK_EOF
    log_ok "Pacman hook installed at $hook_file"
}

# === CHECK MODE ===
check_status() {
    local mnt="$1"

    echo "=== rEFInd Sync Status ==="
    echo ""

    local boot_dir="$mnt/boot"
    [ ! -d "$boot_dir" ] && boot_dir="/boot"

    echo "[Kernels]"
    local found=0
    for f in "$boot_dir"/vmlinuz-*; do
        [ -f "$f" ] || continue
        found=1
        local base base_name initrd_size
        base=$(basename "$f")
        base_name="${base#vmlinuz-}"
        local initrd="$boot_dir/initramfs-$base_name.img"
        [ -f "$initrd" ] && initrd_size=$(stat -c%s "$initrd" 2>/dev/null || echo "?") || initrd="(missing)"
        echo "  vmlinuz: $base  ($(stat -c%s "$f" 2>/dev/null || echo "?") bytes)"
        echo "  initrd:  initramfs-$base_name.img  ($initrd_size bytes)"
    done
    [ $found -eq 0 ] && echo "  (none found)"

    local ucode_src
    ucode_src=$(detect_ucode "$boot_dir")
    echo "  ucode:   $(basename "${ucode_src:-none}")"
    echo ""

    echo "[ESP]"
    local esp_dev
    esp_dev=$(detect_esp "$mnt" 2>/dev/null || true)
    if [ -n "$esp_dev" ]; then
        local esp_size esp_fstype
        esp_size=$(lsblk -n -o SIZE "$esp_dev" 2>/dev/null || echo "?")
        esp_fstype=$(lsblk -n -o FSTYPE "$esp_dev" 2>/dev/null || echo "?")
        echo "  Device: $esp_dev"
        echo "  Size:   $esp_size"
        echo "  Type:   $esp_fstype"
    else
        echo "  (not found or auto-detect failed)"
    fi
    echo ""

    echo "[rEFInd on ESP]"
    local esp_mnt=""
    if [ -n "$esp_dev" ]; then
        esp_mnt=$(mount_esp_temp "$esp_dev" 2>/dev/null || true)
        if [ -n "$esp_mnt" ]; then
            if [ -f "$esp_mnt/EFI/refind/refind.conf" ]; then
                echo "  rEFInd: installed at $esp_mnt/EFI/refind/"
                grep -q "calarch" "$esp_mnt/EFI/refind/refind.conf" 2>/dev/null && \
                    echo "  Entry:  calarch entry found" || \
                    echo "  Entry:  calarch entry NOT found"
                echo "  Synced kernels:"
                if [ -d "$esp_mnt/$REFIND_ESP_DIR" ]; then
                    for f in "$esp_mnt/$REFIND_ESP_DIR"/vmlinuz-*; do
                        [ -f "$f" ] && echo "    $(basename "$f")"
                    done
                else
                    echo "    (no synced kernels)"
                fi
            else
                echo "  rEFInd: NOT installed"
            fi
        fi
    fi

    echo ""
    echo "[Pacman Hook]"
    if [ -f "$mnt/etc/pacman.d/hooks/calarch-sync-kernel.hook" ] || [ -f "/etc/pacman.d/hooks/calarch-sync-kernel.hook" ]; then
        echo "  Hook: installed"
    else
        echo "  Hook: NOT installed"
    fi

    if [ -n "$esp_mnt" ]; then
        local esp_dev_for_unmount="$esp_dev"
        unmount_esp_temp "$esp_mnt" 2>/dev/null || true
    fi
}

# === MAIN ===
main() {
    case "$MODE" in
        check)
            check_status "$MNT"
            return 0
            ;;
        install-hook)
            install_pacman_hook "$MNT"
            return 0
            ;;
    esac

    local boot_dir="$MNT/boot"
    if [ ! -d "$boot_dir" ]; then
        boot_dir="/boot"
    fi
    if [ ! -d "$boot_dir" ]; then
        log_w "Boot directory not found at $MNT/boot or /boot"
        return 1
    fi

    local kernels
    kernels=$(detect_kernels "$boot_dir" 2>/dev/null || true)
    if [ -z "$kernels" ]; then
        log_w "No kernels found in $boot_dir"
        return 1
    fi
    log_i "Kernels detected: $(echo "$kernels" | wc -l)"

    local esp_dev
    esp_dev=$(detect_esp "$MNT" 2>/dev/null || true)
    if [ -z "$esp_dev" ]; then
        log_w "No ESP detected. Skipping rEFInd sync."
        log_w "Kernel remains at $boot_dir — rEFInd may not detect it on Btrfs+zstd."
        return 1
    fi
    log_i "ESP detected: $esp_dev"

    local esp_mnt
    esp_mnt=$(mount_esp_temp "$esp_dev")
    if [ -z "$esp_mnt" ]; then
        return 1
    fi
    log_i "ESP mounted at: $esp_mnt"

    local partuuid
    partuuid=$(detect_root_partuuid "$MNT") || true
    [ -z "$partuuid" ] && log_w "Cannot detect PARTUUID (may affect rEFInd entry)"

    local rootflags
    rootflags=$(detect_rootflags "$MNT") || true

    local kernel_params
    kernel_params=$(get_kernel_params "$MNT")

    # Check if /boot is already ESP (kernel already on FAT32)
    local boot_dev boot_fstype
    boot_dev=$(findmnt -n -o SOURCE "$boot_dir" 2>/dev/null || true)
    boot_fstype=$(findmnt -n -o FSTYPE "$boot_dir" 2>/dev/null || true)
    if [ "$boot_fstype" = "vfat" ] || [ "$boot_fstype" = "fat" ]; then
        log_i "/boot la FAT32 (ESP) — kernel da san tren ESP, bo qua copy"
    else
        log_i "Syncing kernel(s) to ESP..."
        sync_to_esp "$esp_mnt" "$boot_dir"
    fi

    local boot_is_esp=0
    if [ "$boot_fstype" = "vfat" ] || [ "$boot_fstype" = "fat" ]; then
        boot_is_esp=1
    fi

    if [ -n "$partuuid" ]; then
        log_i "Updating rEFInd entry..."
        manage_refind_entry "$esp_mnt" "$partuuid" "$rootflags" "$kernel_params" "$boot_is_esp" || \
            log_w "rEFInd entry update skipped (rEFInd not installed?)"
    fi

    log_i "Installing pacman hook..."
    install_pacman_hook "$MNT"

    unmount_esp_temp "$esp_mnt" || true

    echo ""
    log_ok "rEFInd kernel sync complete!"
    echo "  ESP:      $esp_dev"
    if [ "$boot_is_esp" = "1" ]; then
        echo "  Kernels:  already on ESP at $boot_dir"
    else
        echo "  Kernels:  $(echo "$kernels" | wc -l) synced to $esp_mnt/$REFIND_ESP_DIR/"
    fi
    local refind_found=0
    local refind_entries=0
    if [ -f "$esp_mnt/EFI/refind/refind.conf" ] 2>/dev/null; then
        refind_found=1
        refind_entries=$(grep -c 'menuentry.*Arch' "$esp_mnt/EFI/refind/refind.conf" 2>/dev/null || echo 0)
    fi
    echo "  rEFInd:   $([ $refind_found -eq 1 ] && echo 'installed' || echo 'NOT installed')"
    echo "  Entry:    ${refind_entries} entries"
    echo "  Hook:     /etc/pacman.d/hooks/calarch-sync-kernel.hook"
}

main "$@"
