#!/bin/bash
set -uo pipefail
# ============================================================================
# CF-XZ6-ROTATOR.SH — Auto-rotate Engine for Panasonic CF-XZ6
# ----------------------------------------------------------------------------
# Co che: Lang nghe output tu monitor-sensor (iio-sensor-proxy D-Bus client)
# va anh xa huong vat ly thanh tham so hyprctl de xoay man hinh + cam ung.
#
# Anh xa huong / Orientation mapping:
#   normal        → transform 0  (0°)      — Man hinh ngang chuan
#   bottom-up     → transform 2  (180°)    — Man hinh nguoc
#   left-up       → transform 1  (90°)     — Man hinh doc (xoay trai)
#   right-up      → transform 3  (270°)    — Man hinh doc (xoay phai)
# ============================================================================

if ! command -v monitor-sensor &>/dev/null; then
    echo "ERROR: monitor-sensor not found. Install iio-sensor-proxy."
    exit 1
fi

echo "[$(date)] CF-XZ6 Rotator Engine started" >> /tmp/cfxz6-rotator.log

# Vong lap lang nghe / Listen loop
monitor-sensor | while read -r line; do
    case "$line" in
        *"Accelerometer orientation: normal"*)
            hyprctl keyword monitor eDP-1,2160x1440@60Hz,0x0,1.5
            hyprctl keyword input:touchdevice:transform 0
            echo "[$(date)] → Landscape (0°)" >> /tmp/cfxz6-rotator.log
            ;;
        *"Accelerometer orientation: bottom-up"*)
            hyprctl keyword monitor eDP-1,2160x1440@60Hz,0x0,1.5,transform,2
            hyprctl keyword input:touchdevice:transform 2
            echo "[$(date)] → Landscape inverted (180°)" >> /tmp/cfxz6-rotator.log
            ;;
        *"Accelerometer orientation: left-up"*)
            hyprctl keyword monitor eDP-1,2160x1440@60Hz,0x0,1.5,transform,1
            hyprctl keyword input:touchdevice:transform 1
            echo "[$(date)] → Portrait (90°)" >> /tmp/cfxz6-rotator.log
            ;;
        *"Accelerometer orientation: right-up"*)
            hyprctl keyword monitor eDP-1,2160x1440@60Hz,0x0,1.5,transform,3
            hyprctl keyword input:touchdevice:transform 3
            echo "[$(date)] → Portrait inverted (270°)" >> /tmp/cfxz6-rotator.log
            ;;
    esac
done
