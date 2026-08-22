#!/bin/bash
# ============================================================================
# FIX-SNAPPER.SH — CF-XZ6 snapper @snapshots conflict recovery
# ----------------------------------------------------------------------------
# archinstall manual partitioning + Btrfs Snapper = errno 17 khi @snapshots
# da ton tai. Script nay idempotent: sua /mnt/.snapshots rong hoac
# thieu snapper config.
# ============================================================================
set -euo pipefail

R='\033[0m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'
log()  { echo -e "${CY}>>>${R} $*"; }
ok()   { echo -e "${GR}[OK]${R} $*"; }
warn() { echo -e "${YEL}[!!]${R} $*"; }

fix_snapper() {
    local mnt="${1:-/mnt}"
    [ ! -d "$mnt/etc" ] && { warn "Invalid mnt: $mnt"; return 1; }

    # 1) dam bao @snapshots subvol ton tai (CF-XZ6 6-subvol preset)
    if command -v btrfs &>/dev/null; then
        local root_dev
        root_dev=$(findmnt -n -o SOURCE "$mnt" 2>/dev/null || true)
        [ -z "$root_dev" ] && root_dev=$(findmnt -n -o SOURCE --target "$mnt" 2>/dev/null || true)
        if [ -n "$root_dev" ] && ! btrfs subvolume list "$mnt" 2>/dev/null | grep -q "@snapshots"; then
            log "Creating @snapshots subvolume (CF-XZ6)..."
            local top
            top=$(findmnt -n -o TARGET --source "$root_dev" 2>/dev/null | head -1 || echo "$mnt")
            btrfs subvolume create "$top/@snapshots" 2>/dev/null || warn "Cannot create @snapshots"
            mkdir -p "$mnt/.snapshots" 2>/dev/null || true
            local uuid
            uuid=$(blkid -s UUID -o value "$root_dev" 2>/dev/null || echo "")
            if [ -n "$uuid" ] && ! grep -q "\.snapshots" "$mnt/etc/fstab" 2>/dev/null; then
                echo "UUID=${uuid}  /.snapshots  btrfs  subvol=@snapshots  0  0" >> "$mnt/etc/fstab"
                ok "fstab /.snapshots added"
            fi
        fi
    fi

    # 2) neu snapper chua co config root nhung @snapshots da mount → tao config
    if [ ! -f "$mnt/etc/snapper/configs/root" ]; then
        # .snapshots dang la mountpoint cua @snapshots nhung snapper chua init
        # snapper create-config se fail neu .snapshots da ton tai → can xoa truoc
        local snap_mnt=""
        snap_mnt=$(findmnt -n -o TARGET "$mnt/.snapshots" 2>/dev/null || true)
        if [ -n "$snap_mnt" ]; then
            log ".snapshots is mounted ($snap_mnt) but snapper config missing — recreating..."
            umount "$mnt/.snapshots" 2>/dev/null || true
        fi
        # xoa thu muc rong de snapper tao lai subvol
        if [ -d "$mnt/.snapshots" ] && [ -z "$(ls -A "$mnt/.snapshots" 2>/dev/null)" ]; then
            rmdir "$mnt/.snapshots" 2>/dev/null || true
        elif [ -d "$mnt/.snapshots" ]; then
            # co du lieu cu → backup
            mv "$mnt/.snapshots" "$mnt/.snapshots.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
        fi
        mkdir -p "$mnt/.snapshots" 2>/dev/null || true
        if command -v arch-chroot &>/dev/null; then
            arch-chroot "$mnt" snapper --no-dbus -c root create-config / 2>/dev/null && ok "snapper config root created (CF-XZ6)" || {
                # fallback: thu voi --no-create-subvolume neu .snapshots van ton tai
                arch-chroot "$mnt" snapper --no-dbus -c root create-config --no-create-subvolume / 2>/dev/null && ok "snapper config root created (no-create-subvolume)" || warn "snapper create-config failed — chay tay: arch-chroot $mnt snapper create-config /"
            }
        else
            snapper --no-dbus -c root create-config / 2>/dev/null && ok "snapper config root created" || warn "snapper create-config failed"
        fi
        # remount neu can
        mount -a 2>/dev/null || true
        # neu snapper da tao subvol moi, dam bao fstab
        if [ -f "$mnt/etc/snapper/configs/root" ]; then
            ok "snapper ready — snapshots: snapper -c root list"
        fi
    else
        log "snapper config root already exists — skipping"
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    fix_snapper "${1:-/mnt}"
fi
