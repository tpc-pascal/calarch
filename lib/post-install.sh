#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
BACKUP_DIR="/tmp/calarch-backups"

R='\033[0m'; B='\033[1m'; D='\033[0;90m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'

log_step()   { echo -e "\n${B}${CY}=== $* ===${R}"; }
log_info()   { echo -e "${CY}>>>${R} $*"; }
log_ok()     { echo -e "${GR}[OK]${R} $*"; }
log_warn()   { echo -e "${YEL}[!!]${R} $*"; }
log_error()  { echo -e "${RED}[EE]${R} $*"; }

CHANGES=()
backup_file() {
    local src="$1"
    [ ! -f "$src" ] && return 0
    mkdir -p "$BACKUP_DIR"
    local bak="$BACKUP_DIR/$(echo "$src" | tr '/' '_')"
    if [ ! -f "$bak" ]; then
        cp -a "$src" "$bak"
        CHANGES+=("$src:$bak")
    fi
}

detect_root_dev() {
    local mnt="$1"
    local dev=""
    dev=$(findmnt -n -o SOURCE "$mnt" 2>/dev/null || true)
    [ -z "$dev" ] && dev=$(findmnt -n -o SOURCE --target "$mnt" 2>/dev/null || true)
    if [ -z "$dev" ]; then
        dev=$(lsblk -nlo NAME,MOUNTPOINT | awk -v m="$mnt" '$2==m {print "/dev/"$1; exit}' 2>/dev/null || true)
    fi
    if [ -z "$dev" ]; then
        local uuid
        uuid=$(findmnt -n -o UUID "$mnt" 2>/dev/null || true)
        [ -n "$uuid" ] && dev=$(blkid -U "$uuid" 2>/dev/null || true)
    fi
    echo "$dev"
}

patch_fstab_compression() {
    local mnt="$1"
    local fstab="$mnt/etc/fstab"
    [ ! -f "$fstab" ] && { log_warn "No fstab found at $fstab"; return; }
    if grep -q "btrfs" "$fstab" 2>/dev/null && ! grep -q "compress=zstd" "$fstab" 2>/dev/null; then
        backup_file "$fstab"
        sed -i '/btrfs/ { /compress=zstd/! s/subvol=[^, ]*/&,compress=zstd:3,noatime/ }' "$fstab"
        log_ok "Fstab Btrfs entries patched with compress=zstd:3,noatime"
    else
        log_info "Fstab Btrfs already has compression options"
    fi
}

detect_partuuid() {
    local root_dev="$1"
    local partuuid=""
    [ -n "$root_dev" ] && partuuid=$(blkid -s PARTUUID -o value "$root_dev" 2>/dev/null || true)
    echo "$partuuid"
}

generate_refind_config() {
    local mnt="${1:-/mnt}"
    local root_dev="${2:-}"
    local do_sync="${3:-true}"

    [ -z "$root_dev" ] && root_dev=$(detect_root_dev "$mnt")
    [ -n "$root_dev" ] && log_info "Root device: ${root_dev}" || log_warn "Cannot detect root device"

    local partuuid=""
    [ -n "$root_dev" ] && partuuid=$(detect_partuuid "$root_dev")

    local kparams="${KERNEL_PARAMS:-nowatchdog processor.max_cstate=4 intel_idle.max_cstate=4 i915.enable_fbc=1 i915.enable_psr=1 i915.enable_rc6=1 i915.fastboot=1 mitigations=off pcie_aspm=force}"

    if [ -z "$partuuid" ]; then
        log_error ""
        log_error "KHONG the tu dong detect PARTUUID cua root partition"
        log_error ""
        log_error "De fix th cong, lam theo cac buoc sau:"
        log_error "  1. Boot lai tu Arch ISO"
        log_error "  2. Mount root partition: mount -o subvol=@ /dev/ROOT /mnt"
        log_error "  3. Lay PARTUUID: blkid -s PARTUUID -o value /dev/ROOT"
        log_error "  4. Sua file: sed -i 's/PLACEHOLDER/<GIA_TRI>/g' /mnt/boot/refind_linux.conf"
        log_error "  5. Reboot"
        log_error ""
        log_error "Hoac chay: bash start.sh --fix-partuuid /mnt <PARTUUID>"
        partuuid="PLACEHOLDER_PARTUUID"
    fi

    local conf_path="$mnt/boot/refind_linux.conf"
    backup_file "$conf_path"
    cat > "$conf_path" << REFIND
# calarch: refind_linux.conf for rEFInd auto-detection
"Boot with defaults"  "root=PARTUUID=${partuuid} rw rootflags=subvol=@ ${kparams}"
"Boot to single-user" "root=PARTUUID=${partuuid} rw rootflags=subvol=@ single ${kparams}"
"Boot with minimal"   "root=PARTUUID=${partuuid} rw rootflags=subvol=@ ${kparams}"
REFIND
    log_ok "refind_linux.conf generated at ${conf_path}"

    if [ "$do_sync" = "true" ]; then
        local refind_sync="$LIB_DIR/refind-sync.sh"
        if [ -f "$refind_sync" ]; then
            log_info "Syncing kernel to ESP for rEFInd..."
            bash "$refind_sync" --mnt "$mnt" || log_warn "refind-sync.sh failed (non-fatal)"
        else
            log_info "refind-sync.sh not found — skipping kernel sync"
        fi
    fi
}

post_install() {
    local mnt="${1:-/mnt}"
    log_step "Calarch post-install on ${mnt}"

    [ ! -d "$mnt/etc" ] && { log_error "Invalid mount point: ${mnt}"; exit 1; }

    local username
    username=$(awk -F: '$3>=1000 && $3!=65534 {print $1; exit}' "$mnt/etc/passwd" 2>/dev/null || echo "root")
    log_info "Target user: ${username}"

    local root_dev
    root_dev=$(detect_root_dev "$mnt")
    [ -n "$root_dev" ] && log_info "Root device: ${root_dev}" || log_warn "Cannot detect root device"

    if [ -n "$root_dev" ] && command -v btrfs &>/dev/null; then
        local fstype
        fstype=$(findmnt -n -o FSTYPE "$mnt" 2>/dev/null || echo "")
        if [ "$fstype" = "btrfs" ]; then
            if ! btrfs subvolume list "$mnt" 2>/dev/null | grep -q "@snapshots"; then
                log_info "Creating @snapshots subvolume..."
                local top_mnt
                top_mnt=$(findmnt -n -o TARGET --source "$root_dev" 2>/dev/null | head -1 || echo "$mnt")
                btrfs subvolume create "$top_mnt/@snapshots" 2>/dev/null || log_warn "Cannot create @snapshots subvolume"
                mkdir -p "$mnt/.snapshots" 2>/dev/null || true
                local uuid
                uuid=$(blkid -s UUID -o value "$root_dev" 2>/dev/null || echo "")
                if [ -n "$uuid" ] && ! grep -q "\.snapshots" "$mnt/etc/fstab" 2>/dev/null; then
                    backup_file "$mnt/etc/fstab"
                    echo "UUID=${uuid}  /.snapshots  btrfs  subvol=@snapshots  0  0" >> "$mnt/etc/fstab"
                    log_ok "Created @snapshots with fstab entry"
                fi
            else
                log_info "@snapshots subvolume already exists"
            fi
        else
            log_info "Filesystem is ${fstype}, not btrfs — skipping @snapshots"
        fi
    fi

    patch_fstab_compression "$mnt"

    local kparams="${KERNEL_PARAMS:-nowatchdog processor.max_cstate=4 intel_idle.max_cstate=4 i915.enable_fbc=1 i915.enable_psr=1 i915.enable_rc6=1 i915.fastboot=1 mitigations=off pcie_aspm=force}"

    if [ -d "$mnt/boot/loader/entries" ]; then
        for f in "$mnt/boot/loader/entries/"*.conf; do
            [ -f "$f" ] || continue
            if ! grep -q "nowatchdog" "$f" 2>/dev/null; then
                backup_file "$f"
                sed -i "s|^options.*|& $kparams|" "$f"
                log_ok "Added kernel params: $(basename "$f")"
            fi
        done
    fi

    if [ -f "$mnt/etc/default/grub" ]; then
        if ! grep -q "nowatchdog" "$mnt/etc/default/grub" 2>/dev/null; then
            backup_file "$mnt/etc/default/grub"
            sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*|& $kparams|" "$mnt/etc/default/grub"
            log_ok "Added kernel params to GRUB config"
        fi
    fi

    generate_refind_config "$mnt" "$root_dev"

    local user_home="$mnt/home/$username"
    [ "$username" = "root" ] && user_home="$mnt/root"
    [ ! -d "$user_home" ] && user_home="$mnt/root"

    if [ -d "$user_home/calarch" ]; then
        log_info "calarch already exists at ${user_home}/calarch — skipping clone"
    else
        if [ -d "$SCRIPT_DIR/.git" ]; then
            cp -a "$SCRIPT_DIR" "$user_home/calarch" 2>/dev/null || log_warn "Cannot copy calarch to ${user_home}/calarch"
        else
            log_info "Cloning calarch from GitHub..."
            if git clone --depth=1 https://github.com/tpc-pascal/calarch.git "$user_home/calarch" 2>/dev/null; then
                log_ok "calarch cloned to ${user_home}/calarch"
            else
                log_warn "git clone failed. Install manually: cd ~ && git clone https://github.com/tpc-pascal/calarch.git"
            fi
        fi
    fi

    if [ -d "$user_home/calarch" ] && command -v arch-chroot &>/dev/null; then
        local chroot_path
        chroot_path="${user_home#$mnt}"
        [ -z "$chroot_path" ] && chroot_path="/root"
        arch-chroot "$mnt" chown -R "${username}:${username}" "$chroot_path/calarch" 2>/dev/null || true
    fi

    if command -v arch-chroot &>/dev/null; then
        if arch-chroot "$mnt" systemctl enable NetworkManager &>/dev/null; then
            log_ok "NetworkManager enabled for first boot"
        else
            log_warn "Cannot enable NetworkManager"
        fi
    fi

    mkdir -p "$mnt/var/lib/godmode"
    touch "$mnt/var/lib/godmode/firstboot-pending"

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

    local bashlogin="$mnt/home/$username/.bash_login"
    [ "$username" = "root" ] && bashlogin="$mnt/root/.bash_login"
    cat > "$bashlogin" << 'BASHEOF'
#!/bin/bash
FLAG="/var/lib/godmode/firstboot-pending"
DONE="/var/lib/godmode/firstboot-done"
[ ! -f "$FLAG" ] && exit 0
[ -f "$DONE" ] && exit 0
for i in $(seq 1 30); do
    ping -c 1 -W 1 archlinux.org &>/dev/null && break
    sleep 2
done
cd ~/calarch 2>/dev/null && bash start.sh -m first-boot
rm -f "$FLAG"
touch "$DONE"
echo ""
echo -e "\033[1;32mGod-Mode setup complete! System ready.\033[0m"
echo "  Use: cd ~/calarch && bash start.sh"
echo ""
BASHEOF
    chown "${username}:${username}" "$bashlogin" 2>/dev/null || true

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
for i in $(seq 1 20); do
    ping -c 1 -W 1 archlinux.org &>/dev/null && break
    sleep 3
done
rm -f "$FLAG"
touch "$DONE"
exit 0
FBS
        chmod +x "$mnt/usr/local/bin/godmode-firstboot.sh"
        if command -v arch-chroot &>/dev/null; then
            arch-chroot "$mnt" systemctl enable godmode-firstboot.service 2>/dev/null || true
        fi
    fi

    log_ok "Post-install complete"
    echo ""
    log_info "Sau reboot, login va chay: cd ~/calarch && bash start.sh"
    log_info "Hoac tu dong chay God-Mode setup lan dau khi login"
}

fix_partuuid() {
    local mnt="${1:-/mnt}"
    local new_partuuid="${2:-}"
    [ -z "$new_partuuid" ] && {
        log_error "Thieu PARTUUID."
        log_error "VD: bash start.sh --fix-partuuid /mnt a1b2c3d4-05"
        exit 1
    }
    local conf="$mnt/boot/refind_linux.conf"
    [ ! -f "$conf" ] && {
        log_error "Khong tim thay $conf"
        log_error "Chay lai post-install truoc: bash lib/post-install.sh $mnt"
        exit 1
    }
    awk -v pu="$new_partuuid" '{gsub(/PLACEHOLDER_PARTUUID/, pu); gsub(/PARTUUID= /, "PARTUUID=" pu)}1' "$conf" > "${conf}.tmp" && mv "${conf}.tmp" "$conf"
    log_ok "Da cap nhat PARTUUID trong $conf"
    cat "$conf"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    action="${1:-post-install}"
    case "$action" in
        post-install|--post-install)
            post_install "${2:-/mnt}"
            ;;
        fix-partuuid|--fix-partuuid)
            fix_partuuid "${2:-/mnt}" "${3:-}"
            ;;
        refind|--refind)
            generate_refind_config "${2:-/mnt}" "" "${3:-true}"
            ;;
        *)
            echo "Usage: bash lib/post-install.sh <action> [args]"
            echo "  post-install [mnt]     — chay calarch post-install (chay 1 lan)"
            echo "  fix-partuuid [mnt] <id> — sua PARTUUID trong refind_linux.conf"
            echo "  refind [mnt]            — sinh refind_linux.conf"
            ;;
    esac
fi
