#!/bin/bash
set -euo pipefail
# ============================================================================
# CFXZ6-STYLUS-CALIBRATE.SH — Stylus Calibration cho Panasonic CF-XZ6
# ----------------------------------------------------------------------------
# Hieu chinh stylus cho man hinh ty le 3:2 (2160x1440), kich hoat palm
# rejection va mapping chinh xac cho ghi chu tren Xournal++ / Obsidian.
# ============================================================================

log_calibrate() {
    echo "[$(date '+%H:%M:%S')] $*" >> /tmp/cfxz6-stylus-calibrate.log
}

echo "CF-XZ6 Stylus Calibration Tool"
echo "================================"

# B1: Kiem tra thiet bi stylus
if command -v xsetwacom &>/dev/null; then
    echo "Xorg/Wacom driver detected. Cau hinh xsetwacom..."
    # Liet ke thiet bi
    xsetwacom list devices 2>/dev/null | while read -r device; do
        echo "  Found: $device"
        dev_name=$(echo "$device" | awk -F':' '{print $1}')
        
        # Kich hoat TabletPCButton (palm rejection)
        xsetwacom set "$dev_name" TabletPCButton on 2>/dev/null || true
        log_calibrate "Palm rejection ON for $dev_name"
        
        # Map to man hinh eDP-1
        xsetwacom set "$dev_name" MapToOutput eDP-1 2>/dev/null || true
        log_calibrate "Mapped $dev_name to eDP-1"
    done
elif [ -n "${WAYLAND_DISPLAY:-}" ] || command -v libinput-list-devices &>/dev/null; then
    echo "Wayland detected."
    echo "  Wayland su dung libinput mac dinh, calibration tu dong."
    echo "  Kiem tra: libinput list-devices | grep -A 20 Stylus"
    command -v libinput-list-devices &>/dev/null && libinput list-devices 2>/dev/null | grep -A 20 -i "stylus\|pen\|wacom" || true
else
    echo "No stylus calibration tool found."
    echo "  Cai: sudo pacman -S xf86-input-wacom (Xorg) hoac"
    echo "  dung libinput (Wayland, da co san)."
fi

# B2: Cau hinh Xournal++ preset
XOURNAL_CONFIG="$HOME/.config/xournalpp/settings.xml"
if [ ! -f "$XOURNAL_CONFIG" ]; then
    mkdir -p "$HOME/.config/xournalpp"
    cat > "$XOURNAL_CONFIG" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<settings>
    <property name="pressureMultiplier" value="0.8"/>
    <property name="ignoreTouch" value="true"/>
    <property name="zoomGesturesEnabled" value="false"/>
    <property name="drawingDevice" value="Stylus"/>
    <property name="inputSystem" value="LINUX"/>
    <property name="penFilterIgnoreTimes" value="150"/>
    <property name="penFlickDistance" value="15"/>
    <property name="penFlickSuppressTimeout" value="500"/>
</settings>
EOF
    echo "Created Xournal++ config with palm rejection"
fi

echo ""
echo "Calibration complete."
echo "  Log: /tmp/cfxz6-stylus-calibrate.log"
echo "  Test: Use Xournal++ or xinput test-xi2 --root"
