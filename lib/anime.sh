#!/bin/bash
# ============================================================================
# ANIME.SH — Terminal Anime Player
# Nyaa.si search + mpv play with subs
# ============================================================================
set -euo pipefail

R='\033[0m'; B='\033[1m'; D='\033[0;90m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'; MG='\033[0;35m'

log_i() { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/tui.sh"
HISTORY_FILE="/tmp/calarch-anime-history.txt"
CACHE_DIR="/tmp/calarch-anime-cache"

check_deps() {
    local missing=()
    command -v mpv &>/dev/null || missing+=("mpv")
    command -v curl &>/dev/null || missing+=("curl")
    if [ ${#missing[@]} -gt 0 ]; then
        log_i "Dang cai dependencies: ${missing[*]}"
        sudo pacman -S --noconfirm "${missing[@]}" 2>/dev/null || return 1
    fi
    mkdir -p "$CACHE_DIR"
}

search_nyaa() {
    local query="$1"
    local encoded
    encoded=$(echo "$query" | sed 's/ /+/g')
    local url="https://nyaa.si/?q=${encoded}&s=seeders&o=desc"

    log_i "Dang tim: $query..."
    curl -s "$url" | grep -oP '<a href="/view/[^"]+"[^>]*>([^<]+)</a>' | head -20 > "$CACHE_DIR/nyaa-results.txt" 2>/dev/null || true

    if [ ! -s "$CACHE_DIR/nyaa-results.txt" ]; then
        log_i "Khong tim thay tren Nyaa. Thu tim tren YouTube..."
        return 1
    fi
    return 0
}

select_and_play() {
    local items=() i=1
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local title
        title=$(echo "$line" | sed 's/<[^>]*>//g' | head -c 60)
        items+=("$i" "$title")
        ((i++))
    done < "$CACHE_DIR/nyaa-results.txt"

    if [ ${#items[@]} -eq 0 ]; then
        log_e "Khong tim thay ket qua"
        return
    fi

    local sel
    sel=$(tui_menu "ANIME" "Chon anime de xem:" 18 66 8 "${items[@]}") || return
    [ -z "$sel" ] && return

    local idx=$((sel * 2 - 1))
    local magnet
    magnet=$(curl -s "https://nyaa.si/view/$sel" 2>/dev/null | grep -oP 'magnet:\?[^"]+' | head -1 || true)

    if [ -n "$magnet" ]; then
        log_i "Dang phat torrent..."
        echo "$(date '+%Y-%m-%d %H:%M') | Anime #$sel" >> "$HISTORY_FILE"
        clear
        mpv --no-input-default-bindings "$magnet" 2>/dev/null || true
        read -r -p "Press Enter..."
    else
        log_i "Khong tim thay magnet, mo trang web..."
        xdg-open "https://nyaa.si/view/$sel" 2>/dev/null || true
    fi
}

play_youtube() {
    local query
    query=$(tui_input "ANIME" "Nhap ten anime:" 8 50) || return
    [ -z "$query" ] && return

    clear
    local url
    url=$(yt-dlp "ytsearch:$query episode 1" --get-id --max-downloads 1 2>/dev/null || true)
    if [ -n "$url" ]; then
        log_i "Dang phat: $query"
        mpv --no-input-default-bindings \
            --ytdl-format="bestvideo[height<=?720]+bestaudio/best" \
            "https://youtube.com/watch?v=$url" 2>/dev/null || true
        echo "$(date '+%Y-%m-%d %H:%M') | [YT] $query" >> "$HISTORY_FILE"
    else
        log_e "Khong tim thay"
    fi
    read -r -p "Press Enter..."
}

main_menu() {
    check_deps
    while true; do
        local c
        c=$(tui_menu "ANIME" "Terminal Anime Player:" 14 48 4 \
            "[1]" "Search Nyaa.si + play" \
            "[2]" "Play from YouTube" \
            "[3]" "Xem lich su" \
            "[B]" "Quay lai") || break
        case "$c" in
            "[1]")
                local q
                q=$(tui_input "ANIME" "Nhap ten anime:" 8 50) || true
                [ -n "$q" ] && { search_nyaa "$q" && select_and_play; }
                ;;
            "[2]") play_youtube ;;
            "[3]")
                if [ -f "$HISTORY_FILE" ]; then
                    log_i "Lich su xem:"
                    cat "$HISTORY_FILE"
                else
                    log_i "Chua co lich su"
                fi
                read -r -p "Press Enter..."
                ;;
            "[B]") break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main_menu
fi
