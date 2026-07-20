# test_helper.bash — functions extracted from bootstrap.sh for unit testing
# Sourced by .bats files. Does NOT execute bootstrap.sh.

# --- Colors (muted for testing) ---
R=''; B=''; RED=''; GR=''; YEL=''; CY=''
log()   { true; }
ok()    { true; }
warn()  { true; }
err()   { echo "FATAL: $*"; exit 1; }

# --- validate_nonempty ---
validate_nonempty() {
    local var_name="$1" var_val="$2"
    [ -n "$var_val" ] || err "${var_name} is empty"
}

# --- validate_disk ---
validate_disk() {
    local disk="$1"
    [ -b "$disk" ] || err "Disk ${disk} not found"
    if [[ "$disk" =~ [0-9]$ ]] && [[ ! "$disk" =~ "nvme" ]]; then
        warn "${disk} looks like a partition, not a whole disk"
    fi
}

# --- validate_hostname ---
validate_hostname() {
    local h="$1"
    [[ "$h" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || err "Invalid hostname: ${h}"
}

# --- validate_username ---
validate_username() {
    local u="$1"
    [[ "$u" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || err "Invalid username: ${u}"
}

# --- validate_timezone ---
validate_timezone() {
    local tz="$1"
    [ -f "/usr/share/zoneinfo/${tz}" ] || err "Timezone not found: ${tz}"
}

# --- validate_locale ---
validate_locale() {
    local loc="$1"
    [[ "$loc" =~ ^[a-z]{2}_[A-Z]{2}(\.[a-zA-Z0-9-]+)?$ ]] || err "Invalid locale format: ${loc}"
}

# --- safe_sh ---
safe_sh() {
    printf '%q' "$1"
}
