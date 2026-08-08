#!/bin/bash
# ============================================================================
# YT-VIDEO.SH — Terminal YouTube Player
# yt-dlp + mpv: search, play, playlist, audio-only
# ============================================================================
set -euo pipefail

R='\033[0m'; B='\033[1m'; D='\033[0;90m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'; MG='\033[0;35m'

log_i() { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/tui.sh"
HISTORY_FILE="/tmp/calarch-yt-history.txt"

check_deps() {
    local missing=()
    command -v mpv &>/dev/null || missing+=("mpv")
    command -v yt-dlp &>/dev/null || missing+=("yt-dlp")
    if [ ${#missing[@]} -gt 0 ]; then
        log_i "Dang cai dependencies: ${missing[*]}"
        sudo pacman -S --noconfirm "${missing[@]}" 2>/dev/null || {
            log_e "Failed to install dependencies"
            return 1
        }
    fi
}

play_url() {
    local url="$1"
    local quality="${2:-best}"
    [ -z "$url" ] && return
    log_i "Dang phat: $url"
    clear
    # Chuyen "720p"/"2160p" -> 720/2160; "best" -> khong loc do cao
    local height_filter=""
    if [[ "$quality" =~ ^[0-9]+ ]]; then
        height_filter="bestvideo[height<=?${BASH_REMATCH[0]}]+"
    fi
    mpv --no-input-default-bindings \
        --ytdl-format="${height_filter}bestaudio/best" \
        --term-status-msg="" \
        --osd-level=0 \
        "$url" 2>/dev/null || mpv "$url" 2>/dev/null
    echo ""
    echo "$(date '+%Y-%m-%d %H:%M') | $url" >> "$HISTORY_FILE"
    read -r -p "Press Enter..."
}

search_play() {
    local query
    query=$(tui_input "YOUTUBE" "Nhap tu khoa tim kiem:" 8 50) || return
    [ -z "$query" ] && return

    # Search using yt-dlp, pick first result
    clear
    echo -e "${CY}Dang tim: $query...${R}"
    local url
    url=$(yt-dlp "ytsearch:$query" --get-id --max-downloads 1 2>/dev/null || true)
    if [ -n "$url" ]; then
        play_url "https://youtube.com/watch?v=$url"
    else
        log_e "Khong tim thay ket qua"
        read -r -p "Press Enter..."
    fi
}

audio_only() {
    local url
    url=$(tui_input "YOUTUBE AUDIO" "Nhap URL hoac tu khoa:" 8 50) || return
    [ -z "$url" ] && return

    clear
    if [[ "$url" != *"youtube.com"* ]] && [[ "$url" != *"youtu.be"* ]]; then
        local id
        id=$(yt-dlp "ytsearch:$url" --get-id --max-downloads 1 2>/dev/null || true)
        [ -n "$id" ] && url="https://youtube.com/watch?v=$id"
    fi

    mpv --no-video \
        --ytdl-format="bestaudio/best" \
        --term-status-msg="" \
        "$url" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M') | [AUDIO] $url" >> "$HISTORY_FILE"
    read -r -p "Press Enter..."
}

playlist_subscribe() {
    local url
    url=$(tui_input "PLAYLIST" "Nhap playlist URL:" 8 50) || return
    [ -z "$url" ] && return

    log_i "Dang tai playlist info..."
    local entries
    entries=$(yt-dlp --flat-playlist --dump-json "$url" 2>/dev/null | head -20 || true)
    clear

    local items=() i=1
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        local title
        title=$(echo "$entry" | python3 -c "import sys,json; print(json.load(sys.stdin).get('title','?'))" 2>/dev/null || echo "?")
        items+=("$i" "$title")
        i=$((i + 1))
    done <<< "$entries"

    if [ ${#items[@]} -eq 0 ]; then
        log_e "Khong tim thay video trong playlist"
        read -r -p "Press Enter..."
        return
    fi

    local sel
    sel=$(tui_menu "PLAYLIST" "Chon video:" 18 60 8 "${items[@]}") || return
    [ -z "$sel" ] && return

    # Extract URL for selected item
    local idx=$((sel * 2 - 1))
    local line
    line=$(echo "$entries" | sed -n "${sel}p" 2>/dev/null || true)
    local id
    id=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)
    if [ -n "$id" ]; then
        play_url "https://youtube.com/watch?v=$id"
    fi
}

main_menu() {
    check_deps
    while true; do
        local c
        c=$(tui_menu "YOUTUBE" "Terminal YouTube Player:" 14 50 5 \
            "[1]" "Play URL" \
            "[2]" "Search and play" \
            "[3]" "Audio only (background)" \
            "[4]" "Playlist browser" \
            "[B]" "Quay lai") || break
        case "$c" in
            "[1]")
                local url
                url=$(tui_input "YOUTUBE" "Nhap YouTube URL:" 8 50) || true
                [ -n "$url" ] && play_url "$url"
                ;;
            "[2]") search_play ;;
            "[3]") audio_only ;;
            "[4]") playlist_subscribe ;;
            "[B]") break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main_menu
fi
