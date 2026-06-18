#!/bin/bash
# ============================================================================
# GODMODE-CLEANUP.SH — Auto Maintenance cho Panasonic CF-XZ6
# ----------------------------------------------------------------------------
# Duoc goi boi systemd timer (Chu Nhat 23:00)
# Don dep cache, log, snapshot cu de giai phong dung luong SSD 35GB
# ============================================================================
set -euo pipefail

LOG_FILE="/var/log/godmode-clean-report.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
FREED=0

log() {
    echo "[${TIMESTAMP}] $*" >> "$LOG_FILE"
    echo "[${TIMESTAMP}] $*"
}

measure() {
    local before after diff
    before=$(df / --output=avail 2>/dev/null | tail -1)
    "$@" 2>/dev/null
    after=$(df / --output=avail 2>/dev/null | tail -1)
    diff=$(( (before - after) / 1024 ))
    [ "$diff" -gt 0 ] && FREED=$((FREED + diff))
}

log "=== GodMode Cleanup Started ==="

# 1. Pacman cache
if command -v yay &>/dev/null; then
    measure yay -Sc --noconfirm && log "OK: yay cache cleaned"
else
    measure sudo pacman -Sc --noconfirm && log "OK: pacman cache cleaned"
fi

# 2. paccache (giu 1 phien ban gan nhat)
if command -v paccache &>/dev/null; then
    measure sudo paccache -r -k 1 && log "OK: paccache cleaned"
fi

# 3. NPM cache
if command -v npm &>/dev/null; then
    measure npm cache clean --force && log "OK: npm cache cleaned"
fi

# 4. Yarn cache
if command -v yarn &>/dev/null; then
    measure yarn cache clean && log "OK: yarn cache cleaned"
fi

# 5. Docker prune
if command -v docker &>/dev/null && systemctl is-active docker &>/dev/null; then
    measure docker system prune -af --volumes && log "OK: Docker cleaned"
fi

# 6. Podman prune
if command -v podman &>/dev/null; then
    measure podman system prune -af && log "OK: Podman cleaned"
fi

# 7. Log files > 50MB
measure sudo find /var/log -type f -size +50M -exec truncate -s 0 {} \; 2>/dev/null
log "OK: Large logs truncated"

# 8. Journald (giu 10 ngay)
measure sudo journalctl --vacuum-time=10d 2>/dev/null && log "OK: journal cleaned (10d)"

# 9. Trash >30 ngay
if command -v trash-empty &>/dev/null; then
    measure trash-empty 30 && log "OK: old trash emptied"
fi

# 10. User caches (quét tất cả user home, không chỉ root)
for user_home in /home/*; do
    [ -d "$user_home" ] || continue
    obs_cache="$user_home/.cache/obsidian"
    if [ -d "$obs_cache" ]; then
        measure find "$obs_cache" -type f -atime +30 -delete 2>/dev/null || true
        log "OK: Obsidian cache cleaned for $user_home"
    fi
    measure find "$user_home" -name "*.xopp.bak" -type f -mtime +15 -delete 2>/dev/null || true
done

# 12. Snapper cleanup
if command -v snapper &>/dev/null; then
    sudo snapper -c root cleanup 2>/dev/null && log "OK: snapper root cleaned"
    sudo snapper -c home cleanup 2>/dev/null && log "OK: snapper home cleaned"
fi

# 13. Btrfs balance (if usage diff >20%)
if command -v btrfs &>/dev/null; then
    usage=$(btrfs fi usage / 2>/dev/null | grep "unallocated" | awk '{print $2}' | tr -d 'GiB' || echo 0)
    total=$(df / --output=size 2>/dev/null | tail -1)
    total=$((total / 1048576))
    pct_unallocated=$(echo "scale=0; $usage * 100 / $total" | bc 2>/dev/null || echo 0)
    if [ "$pct_unallocated" -lt 20 ] 2>/dev/null; then
        measure sudo btrfs balance start -dusage=50 -musage=50 / && log "OK: Btrfs balanced"
    else
        log "INFO: Btrfs unallocated ${pct_unallocated}% (no balance needed)"
    fi
fi

log "=== GodMode Cleanup Completed (freed ~${FREED}MB) ==="
