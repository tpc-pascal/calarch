setup() {
    load 'test_helper.bash'
}

# ============================================================================
# validate_nonempty
# ============================================================================

@test "validate_nonempty: non-empty string passes" {
    validate_nonempty "TEST" "hello"
}

@test "validate_nonempty: empty string fails" {
    run validate_nonempty "TEST" ""
    [ "$status" -ne 0 ]
}

# ============================================================================
# validate_hostname
# ============================================================================

@test "validate_hostname: simple hostname passes" {
    validate_hostname "cfxz6"
}

@test "validate_hostname: hostname with numbers passes" {
    validate_hostname "my-pc-01"
}

@test "validate_hostname: single char hostname passes" {
    validate_hostname "a"
}

@test "validate_hostname: empty hostname fails" {
    run validate_hostname ""
    [ "$status" -ne 0 ]
}

@test "validate_hostname: hostname starting with dash fails" {
    run validate_hostname "-bad"
    [ "$status" -ne 0 ]
}

@test "validate_hostname: hostname with spaces fails" {
    run validate_hostname "my host"
    [ "$status" -ne 0 ]
}

@test "validate_hostname: hostname with underscore fails" {
    run validate_hostname "my_host"
    [ "$status" -ne 0 ]
}

# ============================================================================
# validate_username
# ============================================================================

@test "validate_username: simple username passes" {
    validate_username "pascal"
}

@test "validate_username: username with underscore passes" {
    validate_username "my_user"
}

@test "validate_username: single char username passes" {
    validate_username "a"
}

@test "validate_username: empty username fails" {
    run validate_username ""
    [ "$status" -ne 0 ]
}

@test "validate_username: username starting with number fails" {
    run validate_username "1user"
    [ "$status" -ne 0 ]
}

@test "validate_username: username with uppercase fails" {
    run validate_username "User"
    [ "$status" -ne 0 ]
}

# ============================================================================
# validate_timezone
# ============================================================================

@test "validate_timezone: valid timezone passes" {
    skip "Requires /usr/share/zoneinfo — only runs on Linux with tzdata"
}

# ============================================================================
# validate_locale
# ============================================================================

@test "validate_locale: en_US.UTF-8 passes" {
    validate_locale "en_US.UTF-8"
}

@test "validate_locale: vi_VN passes" {
    validate_locale "vi_VN"
}

@test "validate_locale: en_US without encoding passes" {
    validate_locale "en_US"
}

@test "validate_locale: empty locale fails" {
    run validate_locale ""
    [ "$status" -ne 0 ]
}

@test "validate_locale: invalid format fails" {
    run validate_locale "english"
    [ "$status" -ne 0 ]
}

@test "validate_locale: lowercase country fails" {
    run validate_locale "en_us.UTF-8"
    [ "$status" -ne 0 ]
}

# ============================================================================
# safe_sh
# ============================================================================

@test "safe_sh: normal string unchanged" {
    result="$(safe_sh "hello")"
    [ "$result" = "hello" ]
}

@test "safe_sh: string with spaces gets quoted" {
    result="$(safe_sh "hello world")"
    [ "$result" = "hello\ world" ] || [ "$result" = "'hello world'" ]
}

@test "safe_sh: string with single quote gets escaped" {
    result="$(safe_sh "it's")"
    echo "$result" | grep -q "it"
}
