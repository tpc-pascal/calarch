#!/bin/bash
# ============================================================================
# FIREFOX.SH — Firefox Ultrafocus Config
# Vertical tabs (Sidebery), uBlock Origin, Unhook (YouTube), privacy user.js
# ============================================================================
set -euo pipefail

R='\033[0m'; B='\033[1m'; D='\033[0;90m'
RED='\033[0;31m'; GR='\033[0;32m'; YEL='\033[1;33m'; CY='\033[0;36m'; MG='\033[0;35m'

log_i() { echo -e "${CY}>>>${R} $*"; }
log_ok() { echo -e "${GR}[OK]${R} $*"; }
log_e()  { echo -e "${RED}[EE]${R} $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/tui.sh"
CONFIG_FILE="$SCRIPT_DIR/../calarch.conf"
source "$SCRIPT_DIR/config-load.sh"
calarch_load_config "$CONFIG_FILE"

find_profile() {
    local d
    for d in "$HOME/.mozilla/firefox/"*.default-release "$HOME/.mozilla/firefox/"*.default; do
        if [ -d "$d" ]; then
            echo "$d"
            return 0
        fi
    done
    return 1
}

setup_userjs() {
    local profile
    profile=$(find_profile) || { log_e "Khong tim thay Firefox profile"; return 1; }
    log_i "Dang cau hinh Firefox tai: $profile"

    local userjs="$profile/user.js"
    if [ -f "$userjs" ] && [ ! -f "${userjs}.bak" ]; then
        cp "$userjs" "${userjs}.bak"
        log_ok "Da backup user.js"
    fi

    cat > "$userjs" << 'USERJS_EOF'
// === Ultrafocus: Firefox Privacy & Vertical Tabs ===
// user.js — arkenfox-inspired, tinh gon cho lap trinh vien

// --- Telemetry & Data Collection ---
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.server", "data:,");
user_pref("browser.ping-centre.telemetry", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);

// --- Privacy ---
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
user_pref("privacy.trackingprotection.cryptomining.enabled", true);
user_pref("privacy.trackingprotection.fingerprinting.enabled", true);
user_pref("privacy.firstparty.isolate", true);
user_pref("privacy.resistFingerprinting", false);
user_pref("privacy.clearOnShutdown.cache", true);
user_pref("privacy.clearOnShutdown.cookies", false);
user_pref("privacy.clearOnShutdown.history", false);
user_pref("privacy.sanitize.sanitizeOnShutdown", false);

// --- Security ---
user_pref("security.ssl.enable_ocsp_stapling", true);
user_pref("security.ssl.require_safe_negotiation", true);
user_pref("security.tls.enable_0rtt_data", false);
user_pref("security.mixed_content.block_active_content", true);
user_pref("security.mixed_content.block_display_content", true);
user_pref("media.autoplay.blocking_policy", 2);
user_pref("media.autoplay.default", 5);
user_pref("media.videocontrols.picture-in-picture.enabled", true);

// --- Performance ---
user_pref("gfx.webrender.all", true);
user_pref("gfx.webrender.enabled", true);
user_pref("layers.acceleration.force-enabled", true);
user_pref("media.hardware-video-decoding.enabled", true);
user_pref("browser.sessionhistory.max_entries", 50);
user_pref("browser.sessionhistory.max_total_viewers", 8);
user_pref("dom.ipc.processCount", 4);
user_pref("network.http.max-connections", 256);
user_pref("network.http.max-persistent-connections-per-server", 12);
user_pref("network.dnsCacheEntries", 1024);
user_pref("network.dnsCacheExpiration", 3600);
user_pref("network.prefetch-next", false);
user_pref("network.http.speculative-parallel-limit", 0);

// --- Vertical Tabs (Sidebery) support ---
user_pref("sidebar.revamp", true);
user_pref("sidebar.verticalTabs", true);
user_pref("browser.uiCustomization.state", "{\"placements\":{\"widget-overflow-fixed-list\":[],\"nav-bar\":[\"back-button\",\"forward-button\",\"stop-reload-button\",\"urlbar-container\",\"downloads-button\",\"library-button\",\"sidebar-button\",\"unified-extensions-button\"],\"toolbar-menubar\":[\"menubar-items\"],\"TabsToolbar\":[\"tabbrowser-tabs\",\"new-tab-button\",\"alltabs-button\"],\"PersonalToolbar\":[\"personal-bookmarks\"]}}");
user_pref("browser.tabs.drawInTitlebar", false);
user_pref("browser.tabs.allow_transparent_browser", true);
user_pref("browser.tabs.inTitlebar", 0);

// --- Appearance ---
user_pref("browser.uidensity", 1);
user_pref("browser.compactmode.show", true);
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// --- Developer ---
user_pref("devtools.theme", "dark");
user_pref("devtools.toolbox.host", "right");
user_pref("devtools.toolbox.sidebar.width", 400);
user_pref("devtools.inspector.showAllAnonymousContent", true);
user_pref("devtools.console.timestampMessages", true);

// --- Download ---
user_pref("browser.download.useDownloadDir", true);
user_pref("browser.download.manager.addToRecentDocs", false);
user_pref("browser.download.manager.resumeOnWakeDelay", 5000);
USERJS_EOF
    log_ok "user.js configured — privacy + vertical tabs"
}

setup_sidebery() {
    local profile
    profile=$(find_profile) || { log_e "Khong tim thay Firefox profile"; return 1; }
    local chrome_dir="$profile/chrome"
    mkdir -p "$chrome_dir"

    cat > "$chrome_dir/userChrome.css" << 'CHROME_EOF'
/* Ultrafocus: Hide native tab strip — Sidebery handles tabs */
#TabsToolbar {
    visibility: collapse !important;
    margin-bottom: -2px !important;
}

/* Hide title bar in favor of Sidebery */
#titlebar {
    visibility: collapse !important;
}

/* Keep navigation bar clean */
#nav-bar {
    margin-top: -2px !important;
    border-top: none !important;
}

/* Smaller URL bar */
#urlbar-container {
    --urlbar-container-height: 32px !important;
}

#urlbar-background {
    border-radius: 4px !important;
}

/* Compact sidebar */
#sidebar-box {
    --sidebar-width: 280px !important;
    min-width: 200px !important;
    max-width: 400px !important;
    border-right: 1px solid #313244 !important;
}
CHROME_EOF
    log_ok "userChrome.css configured — tab strip hidden"

    local sidebery_dir="$profile/sidebery"
    mkdir -p "$sidebery_dir"
    cat > "$sidebery_dir/config.json" << 'SIDEBERY_EOF'
{
  "version": 1,
  "general": {
    "theme": "dark",
    "navBar": "top",
    "navBarPos": 0,
    "sidebarPos": "left",
    "sidebarWidth": 280,
    "tabsPanelWidth": 280,
    "bookmarksPanelWidth": 280,
    "containerColors": true,
    "sideberyIcon": "simple"
  },
  "tabs": {
    "treeStyle": true,
    "treeLevelOffset": 20,
    "showTreeLevelIcons": true,
    "faviconPosition": "left",
    "closeButton": "hover",
    "pinnedTabs": "top",
    "unreadMark": true,
    "highlightActive": true,
    "soundButton": true,
    "tabActionsClick": "menu",
    "tabActionsDblClick": "reload",
    "scrollable": true
  },
  "snapshots": {
    "enable": false
  },
  "bookmarks": {
    "show": false
  },
  "navigation": {
    "openNewTabAfterActive": true,
    "audibleTabs": "show",
    "discardedTabs": "show"
  },
  "style": {
    "bg": "#1e1e2e",
    "fg": "#cdd6f4",
    "accent": "#89b4fa",
    "border": "#313244",
    "activeTabBg": "#313244",
    "hoverBg": "#2e2e3e",
    "borderRadius": 6,
    "fontSize": 13,
    "tabHeight": 34
  }
}
SIDEBERY_EOF
    log_ok "Sidebery config created"
}

setup_addons() {
    log_i "Addons can cai thu cong (Firefox se mo trang about:addons):"
    echo ""
    echo "  1. Sidebery — Vertical Tabs (nhap tay)"
    echo "     https://addons.mozilla.org/firefox/addon/sidebery/"
    echo ""
    echo "  2. uBlock Origin — Quang cao + malware"
    echo "     https://addons.mozilla.org/firefox/addon/ublock-origin/"
    echo ""
    echo "  3. Unhook — Xoa YouTube Shorts, de xuat, trend"
    echo "     https://addons.mozilla.org/firefox/addon/unhook/"
    echo ""
    echo "  4. Violentmonkey — User scripts"
    echo "     https://addons.mozilla.org/firefox/addon/violentmonkey/"
    echo ""
    read -r -p "  Nhan Enter khi da cai xong (hoac bo qua)..."
    log_ok "Addons list displayed"
}

main_menu() {
    while true; do
        local c
        c=$(tui_menu "FIREFOX" "Ultrafocus Firefox Config:" 14 54 5 \
            "[1]" "Setup user.js (privacy + performance)" \
            "[2]" "Setup Sidebery + hide tab strip" \
            "[3]" "Addon danh sach (cai thu cong)" \
            "[4]" "Mo Firefox profile folder" \
            "[B]" "Quay lai") || break
        case "$c" in
            "[1]") setup_userjs; read -r -p "Press Enter..." ;;
            "[2]") setup_sidebery; read -r -p "Press Enter..." ;;
            "[3]") setup_addons ;;
            "[4]")
                local p
                p=$(find_profile) && xdg-open "$p" 2>/dev/null || log_e "No profile found"
                sleep 1
                ;;
            "[B]") break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main_menu
fi
