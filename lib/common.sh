#!/bin/bash
# ============================================================================
# COMMON.SH — Shared functions cho Arch Linux Auto Installer
# ----------------------------------------------------------------------------
# Su dung: duoc source boi auto-install-arch.sh
# Cung cap: colors, log functions, utils, state management
# ============================================================================

# --- Colors ---
RESET='\033[0m'; BOLD='\033[1m'
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; GRAY='\033[0;90m'

# --- State file ---
STATE_FILE="/tmp/arch-install-state.sh"
PHASE_DONE=-1

# --- Log functions ---
log_info()    { echo -e "${BLUE}>>>${RESET} $*"; }
log_success() { echo -e "${GREEN}[OK]${RESET} $*"; }
log_warn()    { echo -e "${YELLOW}[!!]${RESET} $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*"; }
log_step()    { echo -e "\n${BOLD}${GREEN}=== $* ===${RESET}\n"; }
log_cmd()     { echo -e "  ${BOLD}\$ $*${RESET}"; }

log_fatal() {
    log_error "$*"
    exit 1
}

# --- Utils ---
run_cmd() {
    local desc="$1"
    shift
    echo -e "  → ${desc}..."
    if "$@" >> /tmp/arch-install.log 2>&1; then
        log_success "${desc}"
        return 0
    else
        local ec=$?
        log_warn "${desc} — failed (exit ${ec})"
        return $ec
    fi
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local yn
    if [ "$default" = "y" ]; then
        read -r -p "  ${prompt} [Y/n]: " yn
        case "$yn" in
            [nN]*) return 1 ;;
            *) return 0 ;;
        esac
    else
        read -r -p "  ${prompt} [y/N]: " yn
        case "$yn" in
            [yY]*) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

confirm_dangerous() {
    local prompt="$1"
    echo -e "${RED}${BOLD}⚠ CANH BAO NGUY HIEM!${RESET}"
    echo -e "${RED}$prompt${RESET}"
    echo -e "${YELLOW}Go YES de xac nhan (chu hoa):${RESET} "
    read -r -p "  > " answer
    [ "$answer" = "YES" ]
}

# --- State management ---
save_state() {
    cat > "$STATE_FILE" << EOF
#!/bin/bash
# Arch Install State — auto-generated
INSTALL_MODE=$(printf '%q' "${INSTALL_MODE:-disk}")
INSTALL_DISK=$(printf '%q' "${INSTALL_DISK:-}")
INSTALL_ESP=$(printf '%q' "${INSTALL_ESP:-}")
INSTALL_ROOT=$(printf '%q' "${INSTALL_ROOT:-}")
INSTALL_SWAP=$(printf '%q' "${INSTALL_SWAP:-}")
USE_SWAPFILE=${USE_SWAPFILE:-0}
INSTALL_SWAPFILE=$(printf '%q' "${INSTALL_SWAPFILE:-}")
SWAPFILE_SIZE_MB=${SWAPFILE_SIZE_MB:-8192}
KERNEL_PARAMS=$(printf '%q' "${KERNEL_PARAMS:-nowatchdog processor.max_cstate=4 intel_idle.max_cstate=4 i915.enable_fbc=1 i915.enable_psr=1 i915.enable_rc6=1 i915.fastboot=1 mitigations=off pcie_aspm=force}")
INSTALL_USER=$(printf '%q' "${INSTALL_USER:-}")
INSTALL_PASS=$(printf '%q' "${INSTALL_PASS:-}")
INSTALL_ROOT_PASS=$(printf '%q' "${INSTALL_ROOT_PASS:-}")
INSTALL_HOSTNAME=$(printf '%q' "${INSTALL_HOSTNAME:-}")
INSTALL_TIMEZONE=$(printf '%q' "${INSTALL_TIMEZONE:-}")
HAS_WINDOWS=${HAS_WINDOWS:-0}
HAS_ESP=${HAS_ESP:-0}
IS_CFXZ6=${IS_CFXZ6:-0}
NETWORK_OK=${NETWORK_OK:-0}
PHASE_DONE=${PHASE_DONE:-0}
REFIND_SYNC_ESP=${REFIND_SYNC_ESP:-true}
EOF
}

load_state() {
    [ -f "$STATE_FILE" ] && source "$STATE_FILE"
}

save_phase_progress() {
    local phase="$1"
    PHASE_DONE="$phase"
    save_state
}

is_phase_done() {
    local phase="$1"
    [ "${PHASE_DONE:-0}" -ge "$phase" ] 2>/dev/null
}

# --- Phase guard: skip if phase already done ---
guard_phase() {
    local phase="$1"
    local name="$2"
    if is_phase_done "$phase"; then
        log_info "Phase ${phase} (${name}) already completed, skipping"
        return 1
    fi
    return 0
}
