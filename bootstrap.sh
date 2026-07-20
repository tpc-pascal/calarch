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

VERSION="1.0.11"

# --- Colors ---
R='\033[0m'; B='\033[1m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'
log()   { echo -e "${CY}>>>${R} $*"; }
ok()    { echo -e "${GR}[OK]${R} $*"; }
warn()  { echo -e "${YEL}[!!]${R} $*"; }
err()   { echo -e "${RED}[EE]${R} $*"; exit 1; }
section() {
    if command -v gum &>/dev/null; then
        gum style --border double --padding "0 1" --margin "1 0" --foreground 99 "$*" 2>/dev/null
    else
        echo -e "\n${CY}=== $* ===${R}"
    fi
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
    lsblk -dno NAME,TYPE | awk '$2=="disk" && $1!~/loop|ram|sr|zram/ {print "/dev/"$1; exit}'
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
    read -r input; [ -n "$input" ] && ROOT_PASS="$input"
    echo -n "User password [auto-generate] (enter to generate): "
    read -r input; [ -n "$input" ] && USER_PASS="$input"
}

prompt_font() {
    [ "$AUTO" -eq 1 ] && return
    echo ""
    echo "Console font (larger = more readable on HiDPI):"
    echo "  1) ter-132n (24pt) [recommended]"
    echo "  2) ter-124n (21pt)"
    echo "  3) ter-116n (18pt)"
    echo "  4) Keep default (8x16, small)"
    echo -n "Choose [1]: "
    local input
    read -r input
    case "${input:-1}" in
        1) CONSOLE_FONT="ter-132n" ;;
        2) CONSOLE_FONT="ter-124n" ;;
        3) CONSOLE_FONT="ter-116n" ;;
        4) CONSOLE_FONT="" ;;
        *) CONSOLE_FONT="ter-132n" ;;
    esac
}

# ============================================================================
# PRE-ARCHINSTALL WIZARD
# ============================================================================

prompt_install_mode() {
    [ "$AUTO" -eq 1 ] && return
    section "CHỌN ĐĨA CÀI ĐẶT"

    [ -z "$DISK" ] && DISK=$(detect_disk)
    [ -z "$DISK" ] && err "No disk found"

    local info
    info=$(lsblk -dno NAME,SIZE,MODEL "$DISK" 2>/dev/null | awk '{print $1" ("$2") - "$3}')
    echo -e "Phát hiện: ${B}${DISK}${R} — ${info}"
    echo -n "Dùng đĩa này? (ALL DATA SẼ BỊ XOÁ) [Y/n]: "
    local ans
    read -r ans
    if [[ "$ans" =~ ^[nN] ]]; then
        echo ""
        echo "Các đĩa khả dụng:"
        lsblk -dno NAME,SIZE,MODEL,TYPE | awk '$4=="disk" {printf "  /dev/%s  (%s, %s)\n", $1, $2, $3}'
        echo -n "Nhập đường dẫn (vd: /dev/nvme0n1): "
        read -r DISK
    fi
    validate_nonempty "DISK" "${DISK:-}"
    validate_disk "$DISK"
    ok "Disk: $DISK"
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
    echo "║  archinstall TUI — cau hinh he thong co ban         ║"
    echo "║                                                    ║"
    echo "║  • Partition + Filesystem                           ║"
    echo "║  • Bootloader                                      ║"
    echo "║  • Locale + Timezone                               ║"
    echo "║                                                    ║"
    echo "║  QUAN TRONG: Chon Exit (KHONG Reboot)               ║"
    echo "║  de calarch tu dong chay post-install.             ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    echo -n "Nhan Enter de mo archinstall... "
    read -r

    sudo archinstall || {
        warn "archinstall failed or was cancelled"
        echo -n "Tiep tuc bang calarch manual? [Y/n]: "
        local ans
        read -r ans
        [[ "$ans" =~ ^[nN] ]] && exit 1
        return 1
    }

    for p in /mnt /mnt/archinstall; do
        if [ -d "$p/etc" ] && [ -f "$p/etc/fstab" ]; then
            [ "$p" != "/mnt" ] && {
                mkdir -p /mnt 2>/dev/null
                mount --move "$p" /mnt 2>/dev/null || true
            }
            ok "archinstall completed: system tai /mnt"
            return 0
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
    [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]] || [[ "$DISK" == *"vd"* ]] && sfx="p"

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

    validate_hostname "$HOSTNAME"
    validate_username "$USERNAME"
    validate_timezone "$TIMEZONE"
    validate_locale "$LOCALE"

    if [ -z "$ROOT_PASS" ]; then
        ROOT_PASS=$(tr -dc 'a-zA-Z0-9' < /dev/urandom 2>/dev/null | head -c12) || ROOT_PASS="calarch"
    fi
    if [ -z "$USER_PASS" ]; then
        USER_PASS=$(tr -dc 'a-zA-Z0-9' < /dev/urandom 2>/dev/null | head -c12) || USER_PASS="calarch"
    fi

    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "/tmp")"
    if [ -f "$SCRIPT_DIR/lib/refind-sync.sh" ]; then
        cp "$SCRIPT_DIR/lib/refind-sync.sh" /mnt/usr/local/bin/refind-sync.sh 2>/dev/null || true
        chmod +x /mnt/usr/local/bin/refind-sync.sh 2>/dev/null || true
    fi

    mkdir -p /mnt/tmp
    cat > /mnt/tmp/state.sh << STATEEOF
TIMEZONE=$(safe_sh "$TIMEZONE")
LOCALE=$(safe_sh "$LOCALE")
KEYMAP=$(safe_sh "$KEYMAP")
HOSTNAME=$(safe_sh "$HOSTNAME")
USERNAME=$(safe_sh "$USERNAME")
ROOT_PASS=$(safe_sh "$ROOT_PASS")
USER_PASS=$(safe_sh "$USER_PASS")
KERNEL_PARAMS=$(safe_sh "$KERNEL_PARAMS")
CONSOLE_FONT=$(safe_sh "$CONSOLE_FONT")
STATEEOF

    cat > /mnt/tmp/chroot.sh << 'CRSCRIPT'
#!/bin/bash
set -euo pipefail

source /tmp/state.sh

ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

sed -i "s/^#\(${LOCALE}\)/\1/" /etc/locale.gen 2>/dev/null || \
    sed -i "s/^# *${LOCALE}/${LOCALE}/" /etc/locale.gen 2>/dev/null || true
locale-gen 2>/dev/null || true
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
[ -n "${CONSOLE_FONT}" ] && echo "FONT=${CONSOLE_FONT}" >> /etc/vconsole.conf

echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts << HEOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HEOF

echo "root:${ROOT_PASS}" | chpasswd || echo "WARN: root password change failed"
useradd -m -G wheel,storage,power,audio,video,input -s /bin/bash "${USERNAME}" 2>/dev/null || true
echo "${USERNAME}:${USER_PASS}" | chpasswd || echo "WARN: user password change failed"

echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/99-wheel
chmod 440 /etc/sudoers.d/99-wheel

sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck btrfs)/' /etc/mkinitcpio.conf
mkinitcpio -P || echo "WARN: mkinitcpio failed"

if command -v refind-install &>/dev/null; then
    refind-install 2>/dev/null || true
else
    echo "WARN: refind-install not found"
fi

ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
PARTUUID=""
[ -n "$ROOT_DEV" ] && PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_DEV" 2>/dev/null || echo "")
if [ -n "$PARTUUID" ]; then
    cat > /boot/refind_linux.conf << REFEOF
"Boot with defaults"  "root=PARTUUID=${PARTUUID} rw rootflags=subvol=@ ${KERNEL_PARAMS}"
"Boot to single-user" "root=PARTUUID=${PARTUUID} rw rootflags=subvol=@ single ${KERNEL_PARAMS}"
"Boot with minimal"   "root=PARTUUID=${PARTUUID} rw rootflags=subvol=@ ${KERNEL_PARAMS}"
REFEOF
else
    echo "WARN: Cannot detect PARTUUID — rEFInd may not boot without manual fix"
    cat > /boot/refind_linux.conf << 'REFEOF'
"Boot with defaults"  "root=PARTUUID=PLACEHOLDER rw rootflags=subvol=@ nowatchdog ..."
"Boot to single-user" "root=PARTUUID=PLACEHOLDER rw rootflags=subvol=@ single nowatchdog ..."
"Boot with minimal"   "root=PARTUUID=PLACEHOLDER rw rootflags=subvol=@ nowatchdog ..."
REFEOF
fi

if [ -x /usr/local/bin/refind-sync.sh ]; then
    /usr/local/bin/refind-sync.sh 2>/dev/null || true
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

    mkdir -p /root 2>/dev/null || true
    cat > "$CRED_FILE" << EOF
╔══════════════════════════════════════════╗
║     CALARCH INSTALLATION CREDENTIALS     ║
╚══════════════════════════════════════════╝

  Hostname:   ${HOSTNAME}
  Username:   ${USERNAME}
  User pass:  ${USER_PASS}
  Root pass:  ${ROOT_PASS}

After reboot, login as ${USERNAME}.
On first login, everything runs automatically.
Check: cat /tmp/godmode-setup.log
EOF
    chmod 600 "$CRED_FILE" 2>/dev/null || true

    ok "System configured"
    ok "Credentials saved to ${CRED_FILE}"
}

# ============================================================================
# PHASE 4: FIRST-BOOT HOOKS
# ============================================================================

phase4() {
    section "PHASE 4: First-boot hooks"

    mkdir -p "/mnt/var/lib/godmode"
    touch "/mnt/var/lib/godmode/firstboot-pending"

    local bashlogin="/mnt/home/${USERNAME}/.bash_login"
    cat > "$bashlogin" << 'BASHEOF'
#!/bin/bash
FLAG="/var/lib/godmode/firstboot-pending"
DONE="/var/lib/godmode/firstboot-done"
RUNNING="/tmp/godmode-setup-running"

[ ! -f "$FLAG" ] && exit 0
[ -f "$DONE" ] && exit 0
[ -f "$RUNNING" ] && exit 0

touch "$RUNNING"
(
    for i in $(seq 1 15); do
        ping -c 1 -W 1 archlinux.org &>/dev/null && break
        sleep 2
    done
    if ! command -v git &>/dev/null; then
        sudo pacman -Syu --noconfirm 2>/dev/null || true
        sudo pacman -S git --noconfirm 2>/dev/null || true
    fi
    if [ ! -d ~/calarch ]; then
        git clone --depth=1 https://github.com/tpc-pascal/calarch.git ~/calarch 2>/dev/null || true
    fi
    if [ -d ~/calarch ]; then
        sudo bash ~/calarch/lib/post-install.sh post-install 2>/dev/null
    fi
    rm -f "$FLAG"
    touch "$DONE"
    rm -f "$RUNNING"
) &>/tmp/godmode-setup.log &
BASHEOF
    chown "${USERNAME}:${USERNAME}" "$bashlogin" 2>/dev/null || true

    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "/tmp")"
    if [ -d "$SCRIPT_DIR/.git" ]; then
        cp -a "$SCRIPT_DIR" "/mnt/home/${USERNAME}/calarch" 2>/dev/null || true
        chown -R "${USERNAME}:${USERNAME}" "/mnt/home/${USERNAME}/calarch" 2>/dev/null || true
        ok "calarch copied to target home"
    fi

    ok "First-boot hooks created"
}

# ============================================================================
# PHASE 5: FINALIZE & REBOOT
# ============================================================================

phase5() {
    section "PHASE 5: Final checks"

    local checks=0
    [ -f /mnt/etc/fstab ] && checks=$((checks + 1))
    [ -f /mnt/boot/refind_linux.conf ] && checks=$((checks + 1))
    [ -f "/mnt/home/${USERNAME}/.bash_login" ] && checks=$((checks + 1))
    [ -d /mnt/usr/share/zoneinfo ] && checks=$((checks + 1))

    echo ""
    echo -e "${B}${GR}╔══════════════════════════════════════════════════════════╗${R}"
    echo -e "${B}${GR}║            CALARCH INSTALLATION COMPLETE!              ║${R}"
    echo -e "${B}${GR}╚══════════════════════════════════════════════════════════╝${R}"
    echo ""
    echo "  Disk:       $DISK"
    echo "  Hostname:   $HOSTNAME"
    echo "  Username:   $USERNAME"
    echo "  Bootloader: rEFInd"
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
        ping -c 1 -W 3 archlinux.org &>/dev/null || err "Network required. Connect via: iwctl"
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
    prompt_install_mode
    if ! try_archinstall; then
        prompt_identity
        phase1
        phase2
    fi
fi

phase3
phase4
phase5
