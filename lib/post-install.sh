#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
BACKUP_DIR="/tmp/calarch-backups"

R='\033[0m'; B='\033[1m'
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
    local mnt="${1:-}"
    local dev=""
    [ -z "$mnt" ] && { findmnt -n -o SOURCE / 2>/dev/null || echo ""; return; }
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

default_kernel_params() {
    local mnt="${1:-}"
    local kparams="${KERNEL_PARAMS:-}"
    if [ -z "$kparams" ] && [ -n "$mnt" ] && [ -f "$mnt/calarch.conf" ]; then
        kparams=$(grep -E '^KERNEL_PARAMS=' "$mnt/calarch.conf" 2>/dev/null | head -1 | cut -d'=' -f2- || true)
        kparams="${kparams#\"}"; kparams="${kparams%\"}"
        kparams="${kparams#\'}"; kparams="${kparams%\'}"
    fi
    echo "${kparams:-nowatchdog processor.max_cstate=4 intel_idle.max_cstate=4 i915.enable_fbc=1 i915.enable_psr=1 i915.enable_rc6=1 i915.fastboot=1 mitigations=off pcie_aspm=force}"
}

generate_refind_config() {
    local mnt="${1:-/mnt}"
    local root_dev="${2:-}"
    local do_sync="${3:-true}"

    [ -z "$root_dev" ] && root_dev=$(detect_root_dev "$mnt")
    [ -n "$root_dev" ] && log_info "Root device: ${root_dev}" || log_warn "Cannot detect root device"

    local partuuid=""
    [ -n "$root_dev" ] && partuuid=$(detect_partuuid "$root_dev")
    if [ -z "$partuuid" ] && [ -f "$mnt/etc/fstab" ]; then
        partuuid=$(awk '$1 ~ /PARTUUID=/ {gsub(/.*PARTUUID=/,""); gsub(/,.*/,""); print; exit}' "$mnt/etc/fstab" 2>/dev/null || true)
    fi
    if [ -z "$partuuid" ] && [ -f "$mnt/boot/refind_linux.conf" ]; then
        partuuid=$(sed -n 's/.*root=PARTUUID=\([A-Za-z0-9-]*\).*/\1/p' "$mnt/boot/refind_linux.conf" 2>/dev/null | head -1 || true)
    fi

    local kparams
    kparams=$(default_kernel_params)

    local rootflags="" subvol=""
    if [ -n "$mnt" ]; then
        subvol=$(findmnt -rn -o OPTIONS "$mnt" 2>/dev/null | sed -n 's/.*subvol=\([^,]*\).*/\1/p' | head -1 || true)
    else
        subvol=$(findmnt -rn -o OPTIONS / 2>/dev/null | sed -n 's/.*subvol=\([^,]*\).*/\1/p' | head -1 || true)
    fi
    [ -n "$subvol" ] && rootflags="rootflags=subvol=${subvol}"

    if [ -z "$partuuid" ]; then
        log_warn "Khong detect duoc PARTUUID — dung PLACEHOLDER, can fix: bash start.sh --fix-partuuid $mnt <PARTUUID>"
        partuuid="PLACEHOLDER"
    fi

    local conf_path="$mnt/boot/refind_linux.conf"
    backup_file "$conf_path"
    cat > "$conf_path" << REFIND
# calarch: refind_linux.conf for rEFInd auto-detection
"Boot with defaults"  "root=PARTUUID=${partuuid} rw ${rootflags} ${kparams}"
"Boot to single-user" "root=PARTUUID=${partuuid} rw ${rootflags} single ${kparams}"
"Boot with minimal"   "root=PARTUUID=${partuuid} rw ${rootflags} ${kparams}"
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
    local mnt="$1"
    local live_mode=0
    [ -z "$mnt" ] && live_mode=1
    [ -z "$mnt" ] && mnt=""
    [ -n "$mnt" ] && [ ! -d "$mnt/etc" ] && live_mode=1

    if [ "$live_mode" -eq 1 ]; then
        log_step "Calarch post-install — LIVE mode"
        mnt=""
    else
        log_step "Calarch post-install on ${mnt}"
        [ ! -d "$mnt/etc" ] && { log_error "Invalid mount point: ${mnt}"; exit 1; }
    fi

    local username="" root_dev=""
    if [ "$live_mode" -eq 1 ]; then
        username="${SUDO_USER:-$USER}"
        [ -z "$username" ] && username=$(id -un 1000 2>/dev/null || echo "root")
        root_dev=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
    else
        username=$(awk -F: '$3>=1000 && $3!=65534 {print $1; exit}' "$mnt/etc/passwd" 2>/dev/null || echo "root")
        root_dev=$(detect_root_dev "$mnt")
    fi
    [ -n "$root_dev" ] && log_info "Root device: ${root_dev}" || log_warn "Cannot detect root device"

    # Console font
    if [ "$live_mode" -eq 1 ]; then
        if ! pacman -Qi terminus-font &>/dev/null 2>&1; then
            sudo pacman -S --noconfirm terminus-font 2>/dev/null || true
        fi
    else
        if ! arch-chroot "$mnt" pacman -Qi terminus-font &>/dev/null 2>&1; then
            arch-chroot "$mnt" pacman -S --noconfirm terminus-font 2>/dev/null || true
        fi
    fi
    if [ "$live_mode" -eq 1 ]; then
        if grep -q "^FONT=default8x16" /etc/vconsole.conf 2>/dev/null; then
            sudo sed -i "s/^FONT=.*/FONT=ter-132n/" /etc/vconsole.conf 2>/dev/null || echo "FONT=ter-132n" | sudo tee -a /etc/vconsole.conf >/dev/null 2>&1 || true
            log_info "CF-XZ6 fix: FONT default8x16 -> ter-132n (HiDPI)"
        elif ! grep -q "^FONT=" /etc/vconsole.conf 2>/dev/null; then
            echo "FONT=ter-132n" | sudo tee -a /etc/vconsole.conf >/dev/null 2>&1 || true
        fi
        sudo setfont ter-132n 2>/dev/null || setfont ter-132n 2>/dev/null || true
    else
        # chroot mode: cung ep ter-132n neu archinstall de default8x16
        if grep -q "^FONT=default8x16" "$mnt/etc/vconsole.conf" 2>/dev/null; then
            sed -i "s/^FONT=.*/FONT=ter-132n/" "$mnt/etc/vconsole.conf" 2>/dev/null || echo "FONT=ter-132n" >> "$mnt/etc/vconsole.conf"
            log_info "CF-XZ6 fix: $mnt/etc/vconsole.conf default8x16 -> ter-132n"
        elif ! grep -q "^FONT=" "$mnt/etc/vconsole.conf" 2>/dev/null; then
            echo "FONT=ter-132n" >> "$mnt/etc/vconsole.conf" 2>/dev/null || true
        fi
    fi

    if [ -n "$root_dev" ] && command -v btrfs &>/dev/null; then
        local fstype
        fstype=$(findmnt -n -o FSTYPE "${mnt:-/}" 2>/dev/null || echo "")
        if [ "$fstype" = "btrfs" ]; then
            if ! btrfs subvolume list "${mnt:-/}" 2>/dev/null | grep -q "@snapshots"; then
                log_info "Creating @snapshots subvolume..."
                local top_mnt
                top_mnt=$(findmnt -n -o TARGET --source "$root_dev" 2>/dev/null | head -1 || echo "${mnt:-/}")
                btrfs subvolume create "$top_mnt/@snapshots" 2>/dev/null || log_warn "Cannot create @snapshots subvolume"
                mkdir -p "${mnt:-/}/.snapshots" 2>/dev/null || true
                local uuid
                uuid=$(blkid -s UUID -o value "$root_dev" 2>/dev/null || echo "")
                if [ -n "$uuid" ] && ! grep -q "\.snapshots" "${mnt:-/}etc/fstab" 2>/dev/null; then
                    backup_file "${mnt:-/}etc/fstab"
                    echo "UUID=${uuid}  /.snapshots  btrfs  subvol=@snapshots  0  0" >> "${mnt:-/}etc/fstab"
                    log_ok "Created @snapshots with fstab entry"
                fi
            else
                log_info "@snapshots subvolume already exists"
            fi
        else
            log_info "Filesystem is ${fstype}, not btrfs — skipping @snapshots"
        fi
    fi

    # CF-XZ6: sua snapper @snapshots trung (archinstall errno 17) — idempotent
    if [ -f "$LIB_DIR/fix-snapper.sh" ]; then
        bash "$LIB_DIR/fix-snapper.sh" "$mnt" 2>/dev/null || log_warn "fix-snapper failed (non-fatal)"
    else
        # fallback inline neu thieu file (khi chay tu bundle cu)
        if [ ! -f "${mnt:-/}etc/snapper/configs/root" ] && [ -d "${mnt:-/}.snapshots" ]; then
            if command -v arch-chroot &>/dev/null && [ -n "$mnt" ]; then
                umount "$mnt/.snapshots" 2>/dev/null || true
                rmdir "$mnt/.snapshots" 2>/dev/null || true
                mkdir -p "$mnt/.snapshots" 2>/dev/null || true
                arch-chroot "$mnt" snapper --no-dbus -c root create-config / 2>/dev/null || arch-chroot "$mnt" snapper --no-dbus -c root create-config --no-create-subvolume / 2>/dev/null || true
            fi
        fi
    fi

    [ -n "$mnt" ] && patch_fstab_compression "$mnt"

    local kparams
    kparams=$(default_kernel_params "$mnt")

    if [ -d "${mnt:-/}boot/loader/entries" ]; then
        for f in "${mnt:-/}boot/loader/entries/"*.conf; do
            [ -f "$f" ] || continue
            if ! grep -q "nowatchdog" "$f" 2>/dev/null; then
                backup_file "$f"
                sed -i "s|^options.*|& $kparams|" "$f"
                log_ok "Added kernel params: $(basename "$f")"
            fi
        done
    fi

    if [ -f "${mnt:-/}etc/default/grub" ]; then
        if ! grep -q "nowatchdog" "${mnt:-/}etc/default/grub" 2>/dev/null; then
            backup_file "${mnt:-/}etc/default/grub"
            sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*|& $kparams|" "${mnt:-/}etc/default/grub"
            log_ok "Added kernel params to GRUB config"
        fi
        # E7: sinh lai grub.cfg de ap dung kparams (chi khi co grub-mkconfig)
        if [ -z "$mnt" ] && command -v grub-mkconfig &>/dev/null; then
            grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 && log_ok "grub.cfg regenerated" || log_warn "grub-mkconfig failed (non-fatal)"
        elif [ -n "$mnt" ] && command -v arch-chroot &>/dev/null && [ -x "$mnt/usr/sbin/grub-mkconfig" ]; then
            arch-chroot "$mnt" grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 && log_ok "grub.cfg regenerated" || log_warn "grub-mkconfig failed (non-fatal)"
        fi
    fi

    if [ -z "$mnt" ]; then
        # Live mode: kiem tra UKI, khong can refind_linux.conf neu co UKI
        if ls /boot/EFI/Linux/*.efi &>/dev/null 2>&1; then
            log_info "UKI detected — skipping refind_linux.conf"
        else
            generate_refind_config "" "$root_dev"
        fi
    else
        generate_refind_config "$mnt" "$root_dev"
    fi

    local user_home
    if [ "$live_mode" -eq 1 ]; then
        user_home=$(getent passwd "$username" 2>/dev/null | cut -d: -f6 || echo "/home/$username")
    else
        user_home=$(awk -F: -v u="$username" '$1==u {print $6}' "$mnt/etc/passwd" 2>/dev/null || echo "$mnt/home/$username")
        [ ! -d "$user_home" ] && user_home="$mnt/root"
    fi

    if [ -d "$user_home/calarch" ]; then
        log_info "calarch already exists at ${user_home}/calarch — skipping clone"
    else
        if [ -d "$SCRIPT_DIR/.git" ] && [ -z "$mnt" ]; then
            cp -a "$SCRIPT_DIR" "$user_home/calarch" 2>/dev/null || log_warn "Cannot copy calarch to ${user_home}/calarch"
        elif [ -d "$SCRIPT_DIR/.git" ] && [ -n "$mnt" ]; then
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
    # Dam bao exec bit cho cac script (lan dau cai / he thong cu khong co mode 755)
    chmod +x "$user_home/calarch"/*.sh "$user_home/calarch"/lib/*.sh 2>/dev/null || true

    if [ "$live_mode" -eq 1 ]; then
        if [ -d "$user_home/calarch" ]; then
            chown -R "${username}:${username}" "$user_home/calarch" 2>/dev/null || true
        fi
        systemctl enable NetworkManager --now 2>/dev/null || log_warn "Cannot enable NetworkManager"
    else
        if [ -d "$user_home/calarch" ] && command -v arch-chroot &>/dev/null; then
            local chroot_path
            chroot_path="${user_home#$mnt}"
            [ -z "$chroot_path" ] && chroot_path="/root"
            [ "${chroot_path:0:1}" != "/" ] && chroot_path="/$chroot_path"
            arch-chroot "$mnt" chown -R "${username}:${username}" "$chroot_path/calarch" 2>/dev/null || true
        fi
        if command -v arch-chroot &>/dev/null; then
            arch-chroot "$mnt" systemctl enable NetworkManager &>/dev/null || log_warn "Cannot enable NetworkManager"
        fi
    fi

    local _p="$mnt"
    mkdir -p "${_p:-/}var/lib/godmode"
    touch "${_p:-/}var/lib/godmode/firstboot-pending"

    cat > "${_p:-/}etc/profile.d/godmode-welcome.sh" << 'WELCOME'
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

    local bashlogin
    if [ "$live_mode" -eq 1 ]; then
        [ "$username" = "root" ] && bashlogin="/root/.bash_login" || bashlogin="/home/$username/.bash_login"
    else
        bashlogin="$mnt/home/$username/.bash_login"
        [ "$username" = "root" ] && bashlogin="$mnt/root/.bash_login"
    fi
    cat > "$bashlogin" << 'BASHEOF'
#!/bin/bash
FLAG="/var/lib/godmode/firstboot-pending"
DONE="/var/lib/godmode/firstboot-done"
RUNNING="/tmp/godmode-setup-running"
LOG="/tmp/godmode-setup.log"

[ ! -f "$FLAG" ] && exit 0
[ -f "$DONE" ] && exit 0
[ -f "$RUNNING" ] && exit 0

touch "$RUNNING"
for i in $(seq 1 15); do
    ping -c 1 -W 1 archlinux.org &>/dev/null && break
    sleep 2
done
if ! ping -c 1 -W 1 archlinux.org &>/dev/null && [ ! -d ~/calarch ]; then
    echo "[calarch] Chua co mang — ket noi WiFi/ethernet roi dang nhap lai de chay setup tu dong."
    rm -f "$RUNNING"
    exit 0
fi
command -v git &>/dev/null || sudo pacman -S git --noconfirm &>/dev/null || true
if [ ! -d ~/calarch ]; then
    git clone --depth=1 https://github.com/tpc-pascal/calarch.git ~/calarch 2>/dev/null \
        || git clone --depth=1 https://github.com/tpc-pascal/calarch.git /tmp/calarch 2>/dev/null || true
fi
if [ -d ~/calarch ]; then
    echo ">>> Dang chay post-install (mot lan)..."
    sudo bash ~/calarch/lib/post-install.sh post-install >> "$LOG" 2>&1 || true
    if bash ~/calarch/lib/godmode-setup.sh; then
        rm -f "$FLAG"
        touch "$DONE"
        echo -e "\033[1;32mGod-Mode setup complete! System ready.\033[0m"
    else
        echo -e "\033[1;33mGod-Mode setup chua hoan tat (co buoc loi). Se thu lai vao lan dang nhap sau.\033[0m"
        rm -f "$RUNNING"
        exit 0
    fi
fi
rm -f "$RUNNING"
BASHEOF
    if [ "$live_mode" -eq 1 ]; then
        chown "${username}:${username}" "$bashlogin" 2>/dev/null || true
    else
        chown "${username}:${username}" "$bashlogin" 2>/dev/null || true
    fi

    local svc_file="${_p:-/}etc/systemd/system/godmode-firstboot.service"
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
        cat > "${_p:-/}usr/local/bin/godmode-firstboot.sh" << 'FBS'
#!/bin/bash
set -euo pipefail
for i in $(seq 1 20); do
    ping -c 1 -W 1 archlinux.org &>/dev/null && break
    sleep 3
done
exit 0
FBS
        chmod +x "${_p:-/}usr/local/bin/godmode-firstboot.sh"
        if [ "$live_mode" -eq 1 ]; then
            systemctl enable godmode-firstboot.service 2>/dev/null || true
        elif command -v arch-chroot &>/dev/null; then
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
    awk -v pu="$new_partuuid" '{gsub(/PLACEHOLDER/, pu); gsub(/PLACEHOLDER_PARTUUID/, pu); gsub(/PARTUUID=[ \t]*$/, "PARTUUID=" pu)}1' "$conf" > "${conf}.tmp" \
        && mv -f "${conf}.tmp" "$conf" || { rm -f "${conf}.tmp"; log_error "Khong the cap nhat $conf"; exit 1; }
    log_ok "Da cap nhat PARTUUID trong $conf"
    cat "$conf"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    action="${1:-post-install}"
    case "$action" in
        post-install|--post-install)
            post_install "${2:-}"
            ;;
        fix-partuuid|--fix-partuuid)
            fix_partuuid "${2:-/mnt}" "${3:-}"
            ;;
        refind|--refind)
            generate_refind_config "${2:-/mnt}" "" "${3:-true}"
            ;;
        *)
            echo "Usage: bash lib/post-install.sh <action> [args]"
            echo "  post-install [mnt]       — chay calarch post-install (live neu khong co mnt)"
            echo "  fix-partuuid [mnt] <id>  — sua PARTUUID trong refind_linux.conf"
            echo "  refind [mnt]             — sinh refind_linux.conf"
            ;;
    esac
fi
