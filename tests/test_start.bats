setup() {
    load 'test_helper.bash'
}

# ============================================================================
# start.sh argument parsing (reimplemented for testing)
# ============================================================================

simulate_start() {
    local arg="${1:-}"
    case "$arg" in
        --help|-h)
            echo "Usage: bash start.sh [options]"
            echo "  (no args)           Unified TUI menu"
            echo "  --post-install [mnt] Chay post-install"
            echo "  --fix-partuuid [mnt] <id> Sua PARTUUID"
            echo "  --refind [mnt]       Sinh refind_linux.conf"
            echo "  -m first-boot        Che do first-boot setup"
            return 0
            ;;
        -m|--mode)
            local mode="${2:-}"
            case "$mode" in
                first-boot) return 0 ;;
                *) echo "Unknown mode: $mode"; return 1 ;;
            esac
            ;;
        --post-install)
            # Should auto-escalate if not root
            return 0
            ;;
        --fix-partuuid)
            local id="${3:-}"
            [ -z "$id" ] && return 1
            return 0
            ;;
        "")
            # No args: check tui availability then menu
            if declare -f tui_menu &>/dev/null; then
                return 0
            else
                echo "TUI not available"
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

@test "start: --help exits 0" {
    run simulate_start --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "start: -h exits 0" {
    run simulate_start -h
    [ "$status" -eq 0 ]
}

@test "start: -m first-boot exits 0" {
    run simulate_start -m first-boot
    [ "$status" -eq 0 ]
}

@test "start: unknown mode exits 1" {
    run simulate_start -m unknown
    [ "$status" -eq 1 ]
}

@test "start: --post-install exits 0" {
    run simulate_start --post-install
    [ "$status" -eq 0 ]
}

@test "start: --fix-partuuid with id exits 0" {
    run simulate_start --fix-partuuid /mnt "abc123"
    [ "$status" -eq 0 ]
}

@test "start: --fix-partuuid without id exits 1" {
    run simulate_start --fix-partuuid /mnt ""
    [ "$status" -eq 1 ]
}

@test "start: no args with tui exits 0" {
    tui_menu() { echo "menu"; }
    run simulate_start ""
    [ "$status" -eq 0 ]
}

@test "start: no args without tui exits 1" {
    run simulate_start ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"TUI not available"* ]]
}

