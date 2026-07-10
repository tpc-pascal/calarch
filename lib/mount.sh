#!/bin/bash
# ============================================================================
# MOUNT.SH — Drive / Volume Manager
# Liet ke, mount, unmount, browse tat ca drives va partitions
# ============================================================================
set -euo pipefail

R='\033[0m'; B='\033[1m'; D='\033[0;90m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'; MG='\033[0;35m'

log_i() { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_w()  { echo -e "${YEL}[!!]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/tui.sh"
CONFIG_FILE="$SCRIPT_DIR/../calarch.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

MOUNT_BASE="${MOUNT_BASE:-/mnt}"

# --- Non-interactive sudo wrapper ---
_sudo() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif sudo -n true 2>/dev/null; then sudo "$@"
  elif command -v doas &>/dev/null && doas -n true 2>/dev/null; then doas "$@"
  elif command -v pkexec &>/dev/null; then pkexec "$@"
  else log_e "Root can not. Run: sudo $*"; return 1
  fi
}

check_deps() {
    local missing=()
    command -v lsblk &>/dev/null || missing+=("util-linux")
    command -v jq &>/dev/null || missing+=("jq")
    if [ ${#missing[@]} -gt 0 ]; then
        log_i "Dang cai dependencies: ${missing[*]}"
        if [ "$(id -u)" -eq 0 ]; then
            pacman -S --noconfirm "${missing[@]}" 2>/dev/null || return 1
        elif sudo -n true 2>/dev/null; then
            sudo pacman -S --noconfirm "${missing[@]}" 2>/dev/null || return 1
        else
            log_w "Run: sudo pacman -S ${missing[*]}"
        fi
    fi
}

list_partitions_flat() {
    lsblk -J -o NAME,FSTYPE,SIZE,LABEL,MOUNTPOINT 2>/dev/null | jq -r '
        .blockdevices[] |
        (if .children then .children[] else . end) |
        select(.fstype != null and .fstype != "") |
        "\(.name)|\(.fstype)|\(.size)|\(.label // "")|\(.mountpoint // "")"
    ' 2>/dev/null
}

show_drives_menu() {
    while true; do
        local entries=()
        local data
        data=$(list_partitions_flat) || {
            tui_msg "DRIVES" "Khong tim thay partition nao." 6 40
            return
        }

        local menu_items=()
        while IFS='|' read -r name fstype size label mountpoint; do
            [ -z "$name" ] && continue
            local dev="/dev/$name"
            local desc="[${dev}] ${label:-$name}  ${size}  ${fstype}"
            if [ -n "$mountpoint" ]; then
                desc+="  -> ${mountpoint}"
            else
                desc+="  (unmounted)"
            fi
            menu_items+=("$dev" "$desc")
        done <<< "$data"

        if [ ${#menu_items[@]} -eq 0 ]; then
            tui_msg "DRIVES" "Khong tim thay partition nao." 6 40
            return
        fi

        menu_items+=("MOUNT_ALL" "Mount all unmounted")
        menu_items+=("UMOUNT_ALL" "Unmount all mounted")

        local sel
        sel=$(tui_menu "DRIVE MANAGER" "Chon partition de mount/unmount:" 20 72 10 \
            "${menu_items[@]}") || return

        case "$sel" in
            MOUNT_ALL) mount_all ;;
            UMOUNT_ALL) unmount_all ;;
            *)
                local mountpoint
                mountpoint=$(echo "$data" | awk -F'|' -v d="${sel#/dev/}" '$1 == d {print $5}')
                if [ -n "$mountpoint" ]; then
                    action_unmount "${sel}"
                else
                    action_mount "${sel}"
                fi
                ;;
        esac
    done
}

_get_part_info() {
    local name="$1"
    local data
    data=$(list_partitions_flat) || return 1
    awk -F'|' -v n="$name" '$1 == n {print; exit}' <<< "$data"
}

action_mount() {
    local dev="$1"
    local name="${dev#/dev/}"
    local interactive="${2:-true}"
    local part_info
    local fstype label

    part_info=$(_get_part_info "$name") || true
    if [ -z "$part_info" ]; then
        log_e "Khong tim thay thong tin partition $dev"
        $interactive && read -r -p "Press Enter..."
        return
    fi
    IFS='|' read -r _ fstype _ label _ <<< "$part_info" || true

    local mount_label="${label:-$name}"
    local mount_path="${MOUNT_BASE}/${mount_label}"

    if [ ! -d "$mount_path" ]; then
        _sudo mkdir -p "$mount_path" 2>/dev/null || {
            log_e "Khong tao duoc thu muc $mount_path"
            $interactive && read -r -p "Press Enter..."
            return
        }
    fi

    local mount_opts=""
    case "$fstype" in
        ntfs|ntfs3)  mount_opts="-t ntfs-3g -o uid=1000,gid=1000,umask=022,big_writes" ;;
        exfat)       mount_opts="-t exfat -o uid=1000,gid=1000,umask=022" ;;
        vfat)        mount_opts="-t vfat -o uid=1000,gid=1000,umask=022" ;;
        *)           mount_opts="" ;;
    esac

    if $interactive; then
        if ! tui_yn "MOUNT" "Mount ${dev} (${label:-$name}) to ${mount_path}?" 7 55; then
            return
        fi
    fi

    # shellcheck disable=SC2086
    if _sudo mount $mount_opts "$dev" "$mount_path" 2>/dev/null; then
        log_ok "Da mount ${dev} -> ${mount_path}"
        if $interactive && tui_yn "MOUNT" "Mo file manager?" 6 42; then
            browse_path "$mount_path"
        fi
    else
        log_e "Mount that bai!"
        log_w "Thu: sudo mount $mount_opts $dev $mount_path"
        $interactive && read -r -p "Press Enter..."
    fi
}

action_unmount() {
    local dev="$1"
    local interactive="${2:-true}"
    local name="${dev#/dev/}"
    local part_info
    local mountpoint label

    part_info=$(_get_part_info "$name") || true
    if [ -z "$part_info" ]; then
        log_e "Khong tim thay thong tin partition $dev"
        $interactive && read -r -p "Press Enter..."
        return
    fi
    IFS='|' read -r _ _ _ label mountpoint <<< "$part_info" || true

    if [ -z "$mountpoint" ]; then
        log_e "Device $dev khong duoc mount"
        $interactive && read -r -p "Press Enter..."
        return
    fi

    label="${label:-$dev}"

    if $interactive; then
        if ! tui_yn "UNMOUNT" "Unmount ${label} (from ${mountpoint})?" 7 50; then
            return
        fi
    fi

    if _sudo umount "$dev" 2>/dev/null; then
        log_ok "Da unmount ${dev}"
        _sudo rmdir "$mountpoint" 2>/dev/null || true
    else
        log_w "${dev} busy, thu lazy unmount..."
        if _sudo umount -l "$dev" 2>/dev/null; then
            log_ok "Da lazy unmount ${dev}"
        else
            log_e "Unmount that bai!"
            local fuser_out
            fuser_out=$(fuser -vm "$mountpoint" 2>&1 | tail -5 || true)
            [ -n "$fuser_out" ] && echo -e "${D}Process dang dung:${R}\n$fuser_out"
        fi
    fi
    $interactive && read -r -p "Press Enter..."
}

browse_path() {
    local path="$1"
    if command -v thunar &>/dev/null; then
        nohup thunar "$path" >/dev/null 2>&1 &
    elif command -v nautilus &>/dev/null; then
        nohup nautilus "$path" >/dev/null 2>&1 &
    elif command -v dolphin &>/dev/null; then
        nohup dolphin "$path" >/dev/null 2>&1 &
    else
        xdg-open "$path" 2>/dev/null || true
    fi
}

mount_all() {
    local count=0
    local data
    data=$(list_partitions_flat) || { tui_msg "MOUNT ALL" "Loi doc partition." 6 40; return; }
    while IFS='|' read -r name fstype size label mountpoint; do
        [ -z "$name" ] && continue
        if [ -z "$mountpoint" ]; then
            action_mount "/dev/$name" false
            ((count++))
        fi
    done <<< "$data"
    if [ "$count" -eq 0 ]; then
        tui_msg "MOUNT ALL" "Tat ca da duoc mount." 6 40
    else
        tui_msg "MOUNT ALL" "Da mount ${count} partition(s)." 6 40
    fi
}

unmount_all() {
    local count=0
    local data
    data=$(list_partitions_flat) || { tui_msg "UNMOUNT ALL" "Loi doc partition." 6 40; return; }
    while IFS='|' read -r name fstype size label mountpoint; do
        [ -z "$name" ] && continue
        if [ -n "$mountpoint" ]; then
            action_unmount "/dev/$name" false
            ((count++))
        fi
    done <<< "$data"
    if [ "$count" -eq 0 ]; then
        tui_msg "UNMOUNT ALL" "Khong co partition nao dang mount." 6 46
    else
        tui_msg "UNMOUNT ALL" "Da unmount ${count} partition(s)." 6 46
    fi
}

show_partition_info() {
    local dev="$1"
    local name="${dev#/dev/}"
    local data
    data=$(_get_part_info "$name") || true
    if [ -z "$data" ]; then
        tui_msg "INFO" "Khong tim thay thong tin." 6 40
        return
    fi
    IFS='|' read -r _ fstype size label mountpoint <<< "$data" || true
    local uuid
    uuid=$(lsblk -J -o NAME,UUID 2>/dev/null | jq -r --arg n "$name" '.blockdevices[] | select(.name == $n) | .uuid // ""' 2>/dev/null || echo "")
    local info="Device: ${dev}\nLabel: ${label:-(none)}\nSize: ${size}\nType: ${fstype}\nUUID: ${uuid:-(none)}\nMount: ${mountpoint:-(none)}"
    tui_msg "PARTITION INFO" "$info" 12 50
}

main_menu() {
    check_deps
    while true; do
        local c
        c=$(tui_menu "DRIVE MANAGER" "Quan ly partition:" 16 56 6 \
            "[1]" "Xem danh sach partition + mount/unmount" \
            "[2]" "Mount tat ca chua mount" \
            "[3]" "Unmount tat ca da mount" \
            "[4]" "Thong tin partition" \
            "[5]" "Refresh danh sach" \
            "[B]" "Quay lai") || break
        case "$c" in
            "[1]") show_drives_menu ;;
            "[2]") mount_all ;;
            "[3]") unmount_all ;;
            "[4]")
                local data
                data=$(list_partitions_flat)
                local items=()
                while IFS='|' read -r name fstype size label mountpoint; do
                    [ -z "$name" ] && continue
                    items+=("/dev/$name" "${label:-$name}  ${size}  ${fstype}")
                done <<< "$data"
                if [ ${#items[@]} -gt 0 ]; then
                    local sel
                    sel=$(tui_menu "PARTITIONS" "Chon de xem thong tin:" 16 60 8 "${items[@]}") || continue
                    show_partition_info "$sel"
                else
                    tui_msg "INFO" "Khong co partition nao." 6 40
                fi
                ;;
            "[5]") true ;;
            "[B]") break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main_menu
fi
