#!/bin/bash
# ============================================================================
# BOOTSTRAP.SH — calarch unified installer
# ----------------------------------------------------------------------------
# Usage:
#   bash bootstrap.sh               # archinstall TUI → calarch post-install
#   bash bootstrap.sh --auto        # fully automatic (partition + pacstrap)
#   bash bootstrap.sh --help        # show help
#
# Override via env vars: CALARCH_DISK, CALARCH_HOSTNAME, ...
# ============================================================================

set -euo pipefail

VERSION="1.0.18"

# --- Colors ---
R='\033[0m'; B='\033[1m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'
log()   { echo -e "${CY}>>>${R} $*"; }
ok()    { echo -e "${GR}[OK]${R} $*"; }
warn()  { echo -e "${YEL}[!!]${R} $*"; }
err()   { echo -e "${RED}[EE]${R} $*"; exit 1; }
section() {
    if command -v gum &>/dev/null; then
        gum style --border double --padding "0 1" --margin "1 0" --foreground 99 "$*" 2>/dev/null \
            || echo -e "\n${CY}=== $* ===${R}"
    else
        echo -e "\n${CY}=== $* ===${R}"
    fi
}

# Chi giu lai ky tu an toan trong kernel cmdline. Ngan chan ky tu dac biet
# (", $, backtick, &, |, \) lam vo hieu hoa heredoc refind_linux.conf va sed.
sanitize_kernel_params() {
    printf '%s' "$1" | tr -cd 'A-Za-z0-9_./:=\-+@, '
}

# chpasswd nhan dinh dang "user:pass" — khong cho phep ':' hoac xuong dong
validate_pass() {
    case "$1" in
        *[:$'\n'$'\r']*) err "Password khong duoc chua ky tu ':' hoac xuong dong" ;;
    esac
}

# --- Config ---
AUTO="${CALARCH_AUTO:-0}"
DISK="${CALARCH_DISK:-}"
HOSTNAME="${CALARCH_HOSTNAME:-cfxz6}"
USERNAME="${CALARCH_USER:-pascal}"
TIMEZONE="${CALARCH_TIMEZONE:-Asia/Ho_Chi_Minh}"
LOCALE="${CALARCH_LOCALE:-en_US.UTF-8}"
KEYMAP="${CALARCH_KEYMAP:-us}"
ESP_MB="${CALARCH_ESP_MB:-512}"
ROOT_PASS="${CALARCH_ROOT_PASS:-}"
USER_PASS="${CALARCH_USER_PASS:-}"
CONSOLE_FONT="${CALARCH_CONSOLE_FONT:-ter-132n}"
KERNEL_PARAMS="${CALARCH_KERNEL_PARAMS:-nowatchdog processor.max_cstate=4 intel_idle.max_cstate=4 i915.enable_fbc=1 i915.enable_psr=1 i915.enable_rc6=1 i915.fastboot=1 mitigations=off pcie_aspm=force}"
# Sanitize ngay tai diem nap de moi noi su dung (state.sh, heredoc, sed) deu an toan
KERNEL_PARAMS=$(sanitize_kernel_params "$KERNEL_PARAMS")
ARCHINSTALL_DONE=0

BASE_PKGS=(
    base base-devel
    linux-zen linux-zen-headers
    linux-firmware intel-ucode
    btrfs-progs
    git curl vim
    networkmanager iwd dhcpcd
    gum sudo
    man-db man-pages
    bluez bluez-utils
    pipewire pipewire-pulse wireplumber
    refind terminus-font
)

CRED_FILE="/root/calarch-credentials.txt"

# --- Trap ---
cleanup() {
    set +e
    if mountpoint -q /mnt/boot 2>/dev/null; then umount /mnt/boot 2>/dev/null; fi
    if mountpoint -q /mnt/home 2>/dev/null; then umount /mnt/home 2>/dev/null; fi
    if mountpoint -q /mnt/.snapshots 2>/dev/null; then umount /mnt/.snapshots 2>/dev/null; fi
    if mountpoint -q /mnt 2>/dev/null; then umount /mnt 2>/dev/null; fi
    [ -f /mnt/tmp/chroot.sh ] && rm -f /mnt/tmp/chroot.sh 2>/dev/null
    [ -f /mnt/tmp/state.sh ] && rm -f /mnt/tmp/state.sh 2>/dev/null
}
trap cleanup EXIT INT TERM

# --- Args ---
case "${1:-}" in
    --help|-h)
        echo "calarch ${VERSION} — Unified bootstrap installer"
        echo ""
        echo "Usage: bash bootstrap.sh [options]"
        echo ""
        echo "  (no options)   Interactive mode: archinstall TUI → calarch post-install"
        echo "  --auto         Fully automatic (partition + pacstrap + config, no TUI)"
        echo "  --version|-v   Show version"
        echo "  --help|-h      Show this help"
        echo ""
        echo "Env overrides: CALARCH_DISK, CALARCH_HOSTNAME, CALARCH_USER, ..."
        exit 0 ;;
    --version|-v) echo "calarch ${VERSION}"; exit 0 ;;
    --auto) AUTO=1 ;;
esac

# ============================================================================
# VALIDATION HELPERS
# ============================================================================

validate_nonempty() {
    local var_name="$1" var_val="$2"
    [ -n "$var_val" ] || err "${var_name} is empty. Set via env var or check config."
}

validate_disk() {
    local disk="$1"
    [ -b "$disk" ] || err "Disk ${disk} not found (is it the right path?)"
    if [[ "$disk" =~ [0-9]$ ]] && [[ ! "$disk" =~ "nvme" ]]; then
        warn "${disk} looks like a partition, not a whole disk"
    fi
}

validate_hostname() {
    local h="$1"
    [[ "$h" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || err "Invalid hostname: ${h}"
}

validate_username() {
    local u="$1"
    [[ "$u" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || err "Invalid username: ${u}"
}

validate_timezone() {
    local tz="$1"
    [ -f "/usr/share/zoneinfo/${tz}" ] || err "Timezone not found: ${tz}"
}

validate_locale() {
    local loc="$1"
    [[ "$loc" =~ ^[a-z]{2}_[A-Z]{2}(\.[a-zA-Z0-9-]+)?$ ]] || err "Invalid locale format: ${loc}"
}

safe_sh() {
    printf '%q' "$1"
}

detect_disk() {
    for d in /dev/sd? /dev/sd?? /dev/nvme?n? /dev/mmcblk? /dev/vd?; do
        [ -b "$d" ] || continue
        local basename rem
        basename=$(basename "$d")
        rem=$(cat "/sys/block/${basename}/removable" 2>/dev/null || echo 1)
        [ "$rem" = "0" ] && echo "$d" && return
    done
    for d in /dev/sd? /dev/sd?? /dev/nvme?n? /dev/mmcblk? /dev/vd?; do
        [ -b "$d" ] || continue
        local basename label
        basename=$(basename "$d")
        label=$(lsblk -dno LABEL "$d" 2>/dev/null || echo "")
        [[ "$label" == *"ARCH"* ]] && continue
        echo "$d" && return
    done
    lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk" && $1!~/loop|ram|sr|zram/ {print "/dev/"$1; exit}' || echo ""
}

# ============================================================================
# USER PROMPTS
# ============================================================================

prompt_disk() {
    [ "$AUTO" -eq 1 ] && return
    [ -z "$DISK" ] && DISK=$(detect_disk)
    [ -z "$DISK" ] && err "No disk found"
    echo -e "Detected disk: ${CY}${DISK}${R}"
    echo -n "Use this disk? (ALL DATA WILL BE WIPED) [Y/n]: "
    local ans
    read -r ans
    if [[ "$ans" =~ ^[nN] ]]; then
        echo -e "\nAvailable disks:"
        local disks
        disks=$(lsblk -dno NAME,SIZE,MODEL 2>/dev/null | awk '{print "/dev/"$0}')
        echo "$disks"
        echo -n "Enter disk path (e.g. /dev/nvme0n1): "
        read -r DISK
    fi
    validate_nonempty "DISK" "${DISK:-}"
    validate_disk "$DISK"
}

prompt_identity() {
    [ "$AUTO" -eq 1 ] && return
    echo -n "Hostname [${HOSTNAME}]: "
    local input
    read -r input; [ -n "$input" ] && HOSTNAME="$input"
    echo -n "Username [${USERNAME}]: "
    read -r input; [ -n "$input" ] && USERNAME="$input"
    echo -n "Root password [auto-generate] (enter to generate): "
    read -r input; [ -n "$input" ] && { validate_pass "$input"; ROOT_PASS="$input"; }
    echo -n "User password [auto-generate] (enter to generate): "
    read -r input; [ -n "$input" ] && { validate_pass "$input"; USER_PASS="$input"; }
}

prompt_font() {
    [ "$AUTO" -eq 1 ] && return
    echo ""
    echo "Console font CF-XZ6 HiDPI (larger = readable, small = dau mat):"
    echo "  1) ter-132n (24pt) [CF-XZ6 khuyen nghi — BAT BUOC cho HiDPI]"
    echo "  2) ter-124n (21pt)"
    echo "  3) ter-116n (18pt)"
    echo "  4) Keep default (8x16, NHO — se dau mat tren CF-XZ6)"
    echo -n "Choose [1]: "
    local input
    read -r input
    case "${input:-1}" in
        1) CONSOLE_FONT="ter-132n" ;;
        2) CONSOLE_FONT="ter-124n" ;;
        3) CONSOLE_FONT="ter-116n" ;;
        4)
            echo -e "${YEL}Ban chon Keep default (8x16) — chu rat nho tren CF-XZ6 HiDPI, de dau mat.${R}"
            echo -n "Ban chac giu default8x16 (chu nho)? [y/N]: "
            local confirm
            read -r confirm
            if [[ "$confirm" =~ ^[yY] ]]; then
                CONSOLE_FONT=""
            else
                CONSOLE_FONT="ter-132n"
                echo "Da doi ve ter-132n (CF-XZ6)."
            fi
            ;;
        *) CONSOLE_FONT="ter-132n" ;;
    esac
}

connect_wifi() {
    echo ""
    warn "Khong co mang (ethernet/WiFi chua ket noi)."
    echo -n "Nhap ten mang WiFi (SSID): "
    local ssid
    read -r ssid
    echo -n "Nhap mat khau WiFi: "
    local pass
    read -r -s pass
    echo ""

    local dev
    # Tim device wlan* (bat ky cot nao), khong phu thuoc cu phap cot cua iwctl
    dev=$(iwctl device list 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i ~ /^wlan[0-9]+$/) {print $i; exit}}')
    [ -z "$dev" ] && dev=$(iwctl device list 2>/dev/null | grep -oiE 'wlan[0-9]+' | head -1)
    [ -z "$dev" ] && err "Khong tim thay WiFi adapter (iwctl device list)"
    ok "WiFi adapter: $dev"

    iwctl --passphrase "$pass" station "$dev" connect "$ssid" 2>/dev/null || true
    sleep 5

    if ping -c 1 -W 3 archlinux.org &>/dev/null; then
        ok "WiFi connected: $ssid"
    else
        err "Khong ket noi duoc WiFi. Thu lai: iwctl station $dev connect '$ssid'"
    fi
}

# ============================================================================
# ARCHINSTALL TUI
# ============================================================================

try_archinstall() {
    section "ARCHINSTALL: Base installation (TUI)"

    if ! command -v archinstall &>/dev/null; then
        log "Installing archinstall..."
        pacman -S --noconfirm archinstall 2>/dev/null || return 1
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  archinstall TUI — cau hinh day du                   ║"
    echo "║                                                    ║"
    echo "║  • Disk + Partition + Filesystem                    ║"
    echo "║  • Bootloader                                      ║"
    echo "║  • Locale + Timezone                               ║"
    echo "║  • Hostname + User + Password (do BAN dat)         ║"
    echo "║                                                    ║"
    echo "║  QUAN TRONG: Chon Exit (KHONG Reboot)               ║"
    echo "║  de calarch tu dong chay post-install.             ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    echo "KHUYEN NGHI CF-XZ6 trong archinstall:"
    echo "  • Network     : enable + chon NetworkManager (BAT BUOC truoc khi cai)"
    echo "  • Disk        : CF-XZ6: sda1 ESP 512MiB giu nguyen (/boot), sda9 Btrfs 68GB 6 subvol @/@home/@snapshots/@cache/@log/@pkg compress=zstd"
    echo "  • Filesystem  : Btrfs (CF-XZ6 toi uu; ext4 van boot duoc)"
    echo "  • Bootloader  : rEFInd + uki:true (CF-XZ6 /boot la ESP FAT32)"
    echo "  • Btrfs Snapshots: Da tao @snapshots -> chon None (calarch tu tao snapper sau); chon Snapper -> xoa @snapshots khoi danh sach"
    echo "  • User        : BAT BUOC tao 1 user thuong (vd pascal) + password — KHONG chi dat root password (root-only se phai login root, kho hieu)"
    echo "  • Ket thuc    : chon Exit (KHONG chon Reboot)"
    echo ""
    echo -n "Nhan Enter de mo archinstall... "
    read -r

    archinstall || {
        # CF-XZ6: bat loi Snapper @snapshots trung (errno 17) — log archinstall
        local snapper_hit=0
        if grep -q "snapper.*File exists\|errno:17.*snapshots\|Could not setup Btrfs snapper" /var/log/archinstall/install.log 2>/dev/null; then
            snapper_hit=1
            err "archinstall loi Snapper: @snapshots da ton tai (errno 17)"
            echo -e "${YEL}CF-XZ6 fix:${R} ban da tao subvol @snapshots va chon Btrfs Snapshots=Snapper -> trung nhau."
            echo "  Cach 1 (khuyen nghi): chay lai archinstall -> Manual partitioning -> sda9 -> xoa @snapshots khoi danh sach HOAC chon Btrfs Snapshots=None"
            echo "  Cach 2: tu sua: umount -R /mnt; rmdir /mnt/.snapshots 2>/dev/null; mkdir -p /mnt/.snapshots; roi chay lai bootstrap"
            echo "  Xem: grep -A2 snapper /var/log/archinstall/install.log | tail"
        fi
        if [ "$snapper_hit" -eq 0 ]; then
            warn "archinstall failed or was cancelled"
        fi
        if [ "$snapper_hit" -eq 1 ]; then
            echo -n "Chay lai archinstall ngay voi fix tren? [Y/n]: "
            local ans2
            read -r ans2
            if [[ ! "$ans2" =~ ^[nN] ]]; then
                # cleanup mount truoc khi thu lai (CF-XZ6 dual-boot, khong wipe disk)
                umount -R /mnt 2>/dev/null || true
                try_archinstall && return 0
            fi
        fi
        echo -n "Tiep tuc bang calarch manual (WIPE DISK) ? [y/N]: "
        local ans
        read -r ans
        [[ "$ans" =~ ^[yY] ]] || exit 1
        return 1
    }

    for p in /mnt /mnt/archinstall; do
        if [ -d "$p/etc" ] && [ -f "$p/etc/fstab" ]; then
            if [ "$p" != "/mnt" ]; then
                mkdir -p /mnt 2>/dev/null
                mount --move "$p" /mnt 2>/dev/null || true
            fi
            # Verify he thong that su nam o /mnt sau khi move
            if [ -f /mnt/etc/fstab ]; then
                ok "archinstall completed: system tai /mnt"
                return 0
            fi
            warn "mount --move that bai — he thong van o ${p}"
        fi
    done

    warn "archinstall xong nhung khong tim thay he thong tai /mnt"
    warn "Ban da chon Exit (khong phai Reboot) trong archinstall?"
    echo -n "Thu cong nhan mount point khac? [/mnt]: "
    local alt
    read -r alt
    [ -z "$alt" ] && alt="/mnt"
    if [ -d "$alt/etc" ] && [ -f "$alt/etc/fstab" ]; then
        [ "$alt" != "/mnt" ] && {
            mkdir -p /mnt 2>/dev/null
            mount --move "$alt" /mnt 2>/dev/null || true
        }
        return 0
    fi
    return 1
}

validate_archinstall_system() {
    section "VALIDATE: archinstall result"

    if [ ! -f /mnt/etc/fstab ]; then
        warn "Khong tim thay fstab tai /mnt"
        echo -n "Ban da chon Exit (khong phai Reboot) trong archinstall? [Y/n]: "
        local ans
        read -r ans
        [[ "$ans" =~ ^[nN] ]] && err "Thoat. Boot lai tu USB va chay lai calarch."
    fi

    local u
    u=$(awk -F: '$3>=1000 && $3!=65534 {print $1; exit}' /mnt/etc/passwd 2>/dev/null || echo "")
    if [ -z "$u" ]; then
        warn "CHUA tao user thuong (uid>=1000) — ban chi dat root password (root-only, KHONG khuyen dung, kho hieu, God-Mode se nam o /root)."
        echo "Khuyen: tao 1 user thuong (vd pascal) de ~/calarch o /home, dang nhap de hieu."
        echo -n "Chay lai archinstall de tao user [Y - khuyen nghi], calarch tao giup [c - it khuyen], hay thoat [n]? [Y/c/n]: "
        local choice
        read -r choice
        case "$choice" in
            [cC])
                ARCHINSTALL_DONE=0
                prompt_identity
                warn "calarch se tao user + dat hostname/locale/timezone giup ban"
                ;;
            [nN])
                err "Thoat. Chay lai: tao user thuong trong archinstall (khong chi root)."
                ;;
            *)
                warn "Chay lai archinstall (lan 2)..."
                ARCHINSTALL_DONE=0
                if try_archinstall; then
                    u=$(awk -F: '$3>=1000 && $3!=65534 {print $1; exit}' /mnt/etc/passwd 2>/dev/null || echo "")
                    [ -n "$u" ] && { ARCHINSTALL_DONE=1; ok "User thuong: ${u}"; }
                fi
                if [ "$ARCHINSTALL_DONE" -eq 0 ]; then
                    prompt_identity
                    warn "archinstall lan 2 that bai / khong tao user — calarch se tao user giup ban"
                fi
                ;;
        esac
        return 0
    fi

    ok "User thuong: ${u}"
    ARCHINSTALL_DONE=1

    local bootloader="unknown"
    if [ -f /mnt/boot/refind_linux.conf ]; then
        bootloader="rEFInd"
    elif [ -d /mnt/boot/loader/entries ]; then
        bootloader="systemd-boot"
    elif [ -f /mnt/boot/grub/grub.cfg ]; then
        bootloader="GRUB"
    fi
    [ "$bootloader" != "unknown" ] && ok "Bootloader: $bootloader" || warn "Khong detect duoc bootloader — calarch se xu ly sau post-install"

    local fstype
    fstype=$(findmnt -n -o FSTYPE /mnt 2>/dev/null || echo "")
    if [ -n "$fstype" ] && [ "$fstype" != "btrfs" ]; then
        warn "Filesystem: ${fstype} (khong phai Btrfs) — van boot duoc, kernel params tinh chinh chi du voi rEFInd"
    else
        [ -n "$fstype" ] && ok "Filesystem: ${fstype}"
    fi
}

# ============================================================================
# PHASE 1: DISK (manual fallback)
# ============================================================================

phase1() {
    section "PHASE 1: Disk setup (manual)"

    [ -z "$DISK" ] && DISK=$(detect_disk)
    validate_nonempty "DISK" "${DISK:-}"
    validate_disk "$DISK"

    ok "Target disk: $DISK"
    warn "THIS WILL WIPE ALL DATA ON $DISK"
    sleep 3

    local sfx=""
    # nvme0n1 -> nvme0n1p1, mmcblk0 -> mmcblk0p1; /dev/vd* khong can "p"
    if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
        sfx="p"
    fi

    dd if=/dev/zero of="$DISK" bs=1M count=10 status=none 2>/dev/null || true
    parted -s "$DISK" mklabel gpt || err "Failed to create GPT on ${DISK}"
    parted -s "$DISK" mkpart ESP fat32 1MiB "$((ESP_MB))MiB" || err "Failed to create ESP"
    parted -s "$DISK" set 1 esp on || err "Failed to set ESP flag"
    local ESP="${DISK}${sfx}1"
    parted -s "$DISK" mkpart root btrfs "$((ESP_MB))MiB" 100% || err "Failed to create root"
    local ROOT="${DISK}${sfx}2"

    partprobe "$DISK" 2>/dev/null || udevadm settle 2>/dev/null || sleep 3

    mkfs.fat -F32 "$ESP" >/dev/null 2>&1 || err "Failed to format ESP"
    mkfs.btrfs -f "$ROOT" >/dev/null 2>&1 || err "Failed to format root"
    ok "Partitions created: ESP=$ESP, Root=$ROOT"

    mount "$ROOT" /mnt || err "Failed to mount root"
    btrfs subvolume create /mnt/@ >/dev/null
    btrfs subvolume create /mnt/@home >/dev/null
    btrfs subvolume create /mnt/@snapshots >/dev/null
    umount /mnt

    mount -o compress=zstd:3,noatime,subvol=@ "$ROOT" /mnt || err "Failed to mount @"
    mkdir -p /mnt/{home,.snapshots,boot}
    mount -o compress=zstd:3,noatime,subvol=@home "$ROOT" /mnt/home || err "Failed to mount @home"
    mount -o compress=zstd:3,noatime,subvol=@snapshots "$ROOT" /mnt/.snapshots || err "Failed to mount @snapshots"
    mount "$ESP" /mnt/boot || err "Failed to mount ESP"
    ok "Filesystems mounted"
}

# ============================================================================
# PHASE 2: PACSTRAP (manual fallback)
# ============================================================================

phase2() {
    section "PHASE 2: Base installation (pacstrap)"

    if ! pacstrap /mnt "${BASE_PKGS[@]}" </dev/null; then
        err "pacstrap failed. Check network, disk space, or retry."
    fi

    genfstab -U /mnt > /mnt/etc/fstab 2>/dev/null || err "Failed to generate fstab"

    if grep -q "btrfs" /mnt/etc/fstab 2>/dev/null && ! grep -q "compress=zstd" /mnt/etc/fstab 2>/dev/null; then
        local fstab_tmp
        fstab_tmp=$(mktemp)
        sed '/btrfs/ { /compress=zstd/! s/subvol=[^, ]*/&,compress=zstd:3,noatime/ }' /mnt/etc/fstab > "$fstab_tmp"
        cp "$fstab_tmp" /mnt/etc/fstab
        rm -f "$fstab_tmp"
    fi
    ok "Base system installed"
}

# ============================================================================
# PHASE 3: SYSTEM CONFIGURATION (chroot)
# ============================================================================

phase3() {
    section "PHASE 3: System configuration"

    if [ "$ARCHINSTALL_DONE" -eq 0 ]; then
        validate_hostname "$HOSTNAME"
        validate_username "$USERNAME"
        validate_timezone "$TIMEZONE"
        validate_locale "$LOCALE"

        if [ -z "$ROOT_PASS" ]; then
            # Khong dung pipe co early-exit (tr|head => SIGPIPE 141 => fallback sai)
            ROOT_PASS=$(od -An -N18 -tx1 /dev/urandom 2>/dev/null | tr -dc 'a-zA-Z0-9' | cut -c1-12)
        fi
        if [ -z "$USER_PASS" ]; then
            USER_PASS=$(od -An -N18 -tx1 /dev/urandom 2>/dev/null | tr -dc 'a-zA-Z0-9' | cut -c1-12)
        fi
    else
        USERNAME=$(awk -F: '$3>=1000 && $3!=65534 {print $1; exit}' /mnt/etc/passwd 2>/dev/null || echo "")
        [ -z "$USERNAME" ] && err "Khong tim thay user thuong trong he thong vua cai (phai tao user trong archinstall)"
    fi

    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "/tmp")"
    if [ -f "$SCRIPT_DIR/lib/refind-sync.sh" ]; then
        cp "$SCRIPT_DIR/lib/refind-sync.sh" /mnt/usr/local/bin/refind-sync.sh 2>/dev/null || true
        chmod +x /mnt/usr/local/bin/refind-sync.sh 2>/dev/null || true
    fi

    mkdir -p /mnt/tmp
    cat > /mnt/tmp/state.sh << STATEEOF
KERNEL_PARAMS=$(safe_sh "$KERNEL_PARAMS")
CONSOLE_FONT=$(safe_sh "$CONSOLE_FONT")
ARCHINSTALL_DONE=$(safe_sh "$ARCHINSTALL_DONE")
STATEEOF
    if [ "$ARCHINSTALL_DONE" -eq 0 ]; then
        cat >> /mnt/tmp/state.sh << STATEEOF
TIMEZONE=$(safe_sh "$TIMEZONE")
LOCALE=$(safe_sh "$LOCALE")
KEYMAP=$(safe_sh "$KEYMAP")
HOSTNAME=$(safe_sh "$HOSTNAME")
USERNAME=$(safe_sh "$USERNAME")
ROOT_PASS=$(safe_sh "$ROOT_PASS")
USER_PASS=$(safe_sh "$USER_PASS")
STATEEOF
    fi

    cat > /mnt/tmp/chroot.sh << 'CRSCRIPT'
#!/bin/bash
set -euo pipefail

source /tmp/state.sh

if [ "$ARCHINSTALL_DONE" -eq 0 ]; then
    ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
    hwclock --systohc

    sed -i "s/^#\(${LOCALE}\)/\1/" /etc/locale.gen 2>/dev/null || \
        sed -i "s/^# *${LOCALE}/${LOCALE}/" /etc/locale.gen 2>/dev/null || true
    locale-gen 2>/dev/null || true
    echo "LANG=${LOCALE}" > /etc/locale.conf
    echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

    echo "${HOSTNAME}" > /etc/hostname
    cat > /etc/hosts << HEOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HEOF

    echo "root:${ROOT_PASS}" | chpasswd || echo "WARN: root password change failed"
    if ! useradd -m -G wheel,storage,power,audio,video,input -s /bin/bash "${USERNAME}" 2>/dev/null; then
        echo "WARN: useradd that bai cho '${USERNAME}' — kiem tra lai sau khi boot" >&2
    fi
    echo "${USERNAME}:${USER_PASS}" | chpasswd || echo "WARN: user password change failed"

    mkdir -p /etc/sudoers.d
    echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/99-wheel
    chmod 440 /etc/sudoers.d/99-wheel
fi

# CF-XZ6 HiDPI: ep ter-132n, ghi de default8x16 (chu nho dau mat)
if [ -n "${CONSOLE_FONT}" ]; then
    if grep -q "^FONT=default8x16" /etc/vconsole.conf 2>/dev/null; then
        sed -i "s/^FONT=.*/FONT=${CONSOLE_FONT}/" /etc/vconsole.conf
        echo "CF-XZ6 fix: FONT default8x16 -> ${CONSOLE_FONT} (HiDPI)"
    elif ! grep -q "^FONT=" /etc/vconsole.conf 2>/dev/null; then
        echo "FONT=${CONSOLE_FONT}" >> /etc/vconsole.conf
    fi
    setfont "${CONSOLE_FONT}" 2>/dev/null || setfont ter-132n 2>/dev/null || true
fi

if [ "$ARCHINSTALL_DONE" -eq 0 ]; then
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck btrfs)/' /etc/mkinitcpio.conf || true
fi
mkinitcpio -P || echo "WARN: mkinitcpio failed"

if [ -d /boot/EFI/refind ]; then
    refind-install 2>/dev/null || true

    ROOTFLAGS=""
    SUBVOL=$(findmnt -rn -o OPTIONS / 2>/dev/null | sed -n 's/.*subvol=\([^,]*\).*/\1/p' | head -1 || true)
    [ -n "$SUBVOL" ] && ROOTFLAGS="rootflags=subvol=${SUBVOL}"
    ROOTFLAGS=$(sanitize_kernel_params "$ROOTFLAGS")

    ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
    PARTUUID=""
    [ -n "$ROOT_DEV" ] && PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_DEV" 2>/dev/null || echo "")
    if [ -n "$PARTUUID" ]; then
        cat > /boot/refind_linux.conf << REFEOF
"Boot with defaults"  "root=PARTUUID=${PARTUUID} rw ${ROOTFLAGS} ${KERNEL_PARAMS}"
"Boot to single-user" "root=PARTUUID=${PARTUUID} rw ${ROOTFLAGS} single ${KERNEL_PARAMS}"
"Boot with minimal"   "root=PARTUUID=${PARTUUID} rw ${ROOTFLAGS} ${KERNEL_PARAMS}"
REFEOF
    else
        echo "WARN: Cannot detect PARTUUID — rEFInd may not boot without manual fix"
        cat > /boot/refind_linux.conf << REFEOF
"Boot with defaults"  "root=PARTUUID=PLACEHOLDER rw ${ROOTFLAGS} ${KERNEL_PARAMS}"
"Boot to single-user" "root=PARTUUID=PLACEHOLDER rw ${ROOTFLAGS} single ${KERNEL_PARAMS}"
"Boot with minimal"   "root=PARTUUID=PLACEHOLDER rw ${ROOTFLAGS} ${KERNEL_PARAMS}"
REFEOF
    fi

    if [ -x /usr/local/bin/refind-sync.sh ]; then
        /usr/local/bin/refind-sync.sh 2>/dev/null || true
    fi
elif [ -d /boot/loader/entries ]; then
    for f in /boot/loader/entries/*.conf; do
        [ -f "$f" ] || continue
        grep -q "nowatchdog" "$f" 2>/dev/null || sed -i "s|^options.*|& ${KERNEL_PARAMS}|" "$f" 2>/dev/null || true
    done
    echo "systemd-boot detected — kernel params added to loader entries"
elif [ -f /etc/default/grub ]; then
    grep -q "nowatchdog" /etc/default/grub 2>/dev/null || \
        sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*|& ${KERNEL_PARAMS}|" /etc/default/grub 2>/dev/null || true
    command -v grub-mkconfig &>/dev/null && grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
    echo "GRUB detected — kernel params added to GRUB config"
else
    echo "No known bootloader detected — kernel params handled by godmode post-install"
fi

systemctl enable NetworkManager 2>/dev/null || true
systemctl enable systemd-resolved 2>/dev/null || true
systemctl enable fstrim.timer 2>/dev/null || true
systemctl enable bluetooth 2>/dev/null || true

exit 0
CRSCRIPT

    chmod +x /mnt/tmp/chroot.sh || err "Failed to set chroot script permissions"
    arch-chroot /mnt /tmp/chroot.sh || warn "arch-chroot completed with warnings"
    rm -f /mnt/tmp/chroot.sh /mnt/tmp/state.sh

    if [ "$ARCHINSTALL_DONE" -eq 0 ]; then
        mkdir -p /root 2>/dev/null || true
        # Ghi creds bang printf — heredoc khong an toan cho value co ky tu dac biet
        {
            printf '╔══════════════════════════════════════════════════╗\n'
            printf '║     CALARCH INSTALLATION CREDENTIALS             ║\n'
            printf '╚══════════════════════════════════════════════════╝\n'
            printf '\n'
            printf '  Hostname:   %s\n' "$HOSTNAME"
            printf '  Username:   %s\n' "$USERNAME"
            printf '  User pass:  %s\n' "$USER_PASS"
            printf '  Root pass:  %s\n' "$ROOT_PASS"
            printf '\n'
            printf 'After reboot, login as %s.\n' "$USERNAME"
            printf 'On first login, everything runs automatically.\n'
            printf 'Check: cat /tmp/godmode-setup.log\n'
        } > "$CRED_FILE"
        chmod 600 "$CRED_FILE" 2>/dev/null || true
        ok "Credentials saved to ${CRED_FILE}"
    fi

    ok "System configured"
}

# ============================================================================
# PHASE 4: FIRST-BOOT HOOKS
# ============================================================================

phase4() {
    section "PHASE 4: First-boot hooks"

    USERNAME=$(awk -F: '$3>=1000 && $3!=65534 {print $1; exit}' /mnt/etc/passwd 2>/dev/null || echo "")
    [ -z "$USERNAME" ] && err "Khong tim thay user thuong (phai tao user trong archinstall)"

    mkdir -p "/mnt/var/lib/godmode"
    touch "/mnt/var/lib/godmode/firstboot-pending"

    local bashlogin="/mnt/home/${USERNAME}/.bash_login"
    mkdir -p "$(dirname "$bashlogin")" 2>/dev/null || true
    cat > "$bashlogin" << 'BASHEOF'
#!/bin/bash
FLAG="/var/lib/godmode/firstboot-pending"
DONE="/var/lib/godmode/firstboot-done"
RUNNING="/tmp/godmode-setup-running"

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
command -v git &>/dev/null || sudo pacman -S git --noconfirm 2>/dev/null || true
if [ ! -d ~/calarch ]; then
    git clone --depth=1 https://github.com/tpc-pascal/calarch.git ~/calarch 2>/dev/null || true
fi
if [ -d ~/calarch ]; then
    echo ">>> Dang chay post-install (mot lan)..."
    sudo bash ~/calarch/lib/post-install.sh post-install >> /tmp/godmode-setup.log 2>&1 || true
    bash ~/calarch/lib/godmode-setup.sh
    rm -f "$FLAG"
    touch "$DONE"
fi
rm -f "$RUNNING"
BASHEOF
    chown "${USERNAME}:${USERNAME}" "$bashlogin" 2>/dev/null || true

    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "/tmp")"
    if [ -d "$SCRIPT_DIR/.git" ]; then
        # Tranh nest neu da ton tai tu lan chay truoc
        [ -e "/mnt/home/${USERNAME}/calarch" ] && rm -rf "/mnt/home/${USERNAME}/calarch"
        cp -a "$SCRIPT_DIR" "/mnt/home/${USERNAME}/calarch" 2>/dev/null || true
        chown -R "${USERNAME}:${USERNAME}" "/mnt/home/${USERNAME}/calarch" 2>/dev/null || true
        ok "calarch copied to target home"
    else
        if git clone --depth=1 https://github.com/tpc-pascal/calarch.git "/mnt/home/${USERNAME}/calarch" 2>/dev/null; then
            ok "calarch bundled to target home (git clone)"
        else
            warn "Khong bundle duoc calarch — se tu clone o lan login dau"
        fi
        chown -R "${USERNAME}:${USERNAME}" "/mnt/home/${USERNAME}/calarch" 2>/dev/null || true
    fi
    # Dam bao cac script co exec bit (phong truong hop cp -a tu filesystem mac/git khong giu mode)
    chmod +x "/mnt/home/${USERNAME}/calarch"/*.sh "/mnt/home/${USERNAME}/calarch"/lib/*.sh 2>/dev/null || true

    ok "First-boot hooks created"
}

# ============================================================================
# PHASE 5: FINALIZE & REBOOT
# ============================================================================

phase5() {
    section "PHASE 5: Final checks"

    USERNAME=$(awk -F: '$3>=1000 && $3!=65534 {print $1; exit}' /mnt/etc/passwd 2>/dev/null || echo "")
    HOSTNAME=$(cat /mnt/etc/hostname 2>/dev/null || echo "")

    local bootloader="unknown"
    if [ -f /mnt/boot/refind_linux.conf ]; then
        bootloader="rEFInd"
    elif [ -d /mnt/boot/loader/entries ]; then
        bootloader="systemd-boot"
    elif [ -f /mnt/boot/grub/grub.cfg ]; then
        bootloader="GRUB"
    fi

    local checks=0
    [ -f /mnt/etc/fstab ] && checks=$((checks + 1))
    [ "$bootloader" != "unknown" ] && checks=$((checks + 1))
    [ -f "/mnt/home/${USERNAME}/.bash_login" ] && checks=$((checks + 1))
    [ -d /mnt/usr/share/zoneinfo ] && checks=$((checks + 1))

    echo ""
    echo -e "${B}${GR}╔══════════════════════════════════════════════════════════╗${R}"
    echo -e "${B}${GR}║            CALARCH INSTALLATION COMPLETE!              ║${R}"
    echo -e "${B}${GR}╚══════════════════════════════════════════════════════════╝${R}"
    echo ""
    echo "  Disk:       ${DISK:-auto}"
    echo "  Hostname:   ${HOSTNAME}"
    echo "  Username:   ${USERNAME}"
    echo "  Bootloader: $bootloader"
    echo "  Checks:     $checks/4 passed"
    echo ""

    if [ -f "$CRED_FILE" ]; then
        echo -e "${YEL}━━━ CREDENTIALS (also saved at ${CRED_FILE}) ━━━${R}"
        grep -v "^╔\|^║\|^╚\|^$\|^After\|^Check" "$CRED_FILE" 2>/dev/null | head -10 || true
        echo ""
    fi

    echo -e "${YEL}After first login, everything runs automatically.${R}"
    echo -e "${YEL}Check: cat /tmp/godmode-setup.log${R}"
    echo ""
    echo -e "${CY}Rebooting in 5 seconds... (Ctrl+C to cancel)${R}"
    sleep 5

    log "Unmounting and rebooting..."
    trap '' EXIT INT TERM
    umount -R /mnt 2>/dev/null || warn "Some filesystems could not be unmounted"
    reboot
}

# ============================================================================
# MAIN
# ============================================================================

section "calarch v${VERSION}"

phase0() {
    section "Environment check"

    [ "$EUID" -eq 0 ] || err "Run as root (sudo su)"
    [ -d /sys/firmware/efi/efivars ] || err "Boot Arch ISO in UEFI mode (not Legacy BIOS)"

    if ! ping -c 1 -W 3 archlinux.org &>/dev/null; then
        warn "No network. Starting dhcpcd..."
        if command -v dhcpcd &>/dev/null; then
            dhcpcd -q -t 10 2>/dev/null || true
            sleep 3
        fi
        if ! ping -c 1 -W 3 archlinux.org &>/dev/null; then
            connect_wifi
        fi
    fi
    ok "Network OK"

    command -v pacstrap &>/dev/null || err "pacstrap not found — this must be the Arch ISO"

    if ! pacman-key --list-keys &>/dev/null; then
        log "Initializing pacman keyring..."
        pacman-key --init 2>/dev/null || true
        pacman-key --populate archlinux 2>/dev/null || true
    fi
    ok "Environment OK"
}

phase0

prompt_font

if [ "$AUTO" -eq 1 ]; then
    [ -z "$DISK" ] && DISK=$(detect_disk)
    phase1
    phase2
else
    if try_archinstall; then
        ARCHINSTALL_DONE=1
        validate_archinstall_system
    else
        prompt_disk
        prompt_identity
        phase1
        phase2
    fi
fi

phase3
phase4
phase5
