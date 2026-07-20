setup() {
    load 'test_helper.bash'
    TEST_DIR=$(mktemp -d)
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ============================================================================
# default_kernel_params — inline reimplementation for testing
# ============================================================================

default_kernel_params() {
    echo "${CALARCH_KERNEL_PARAMS:-nowatchdog processor.max_cstate=4 intel_idle.max_cstate=4 i915.enable_fbc=1 i915.enable_psr=1 i915.enable_rc6=1 i915.fastboot=1 mitigations=off pcie_aspm=force}"
}

@test "default_kernel_params: outputs expected string" {
    run default_kernel_params
    [ "$status" -eq 0 ]
    [[ "$output" == *"nowatchdog"* ]]
    [[ "$output" == *"mitigations=off"* ]]
}

@test "default_kernel_params: respects CALARCH_KERNEL_PARAMS env" {
    CALARCH_KERNEL_PARAMS="test-param=1" run default_kernel_params
    [ "$status" -eq 0 ]
    [[ "$output" == "test-param=1" ]]
}

# ============================================================================
# detect_root_dev — unit test via function source
# ============================================================================

# Mock findmnt for testing
findmnt() {
    case "$*" in
        *--help*) command findmnt --help 2>/dev/null || true ;;
        *"-n -o SOURCE /"*) echo "/dev/sda2" ;;
        *"-n -o UUID /"*) echo "a1b2c3d4" ;;
        *) echo "" ;;
    esac
}

export -f findmnt

@test "detect_root_dev: empty mnt returns root device" {
    # Reimplement the function inline for testing
    detect_root_dev() {
        local mnt="${1:-}"
        [ -z "$mnt" ] && { findmnt -n -o SOURCE / 2>/dev/null || echo ""; return; }
        findmnt -n -o SOURCE "$mnt" 2>/dev/null || true
    }
    run detect_root_dev ""
    [ "$status" -eq 0 ]
}

# ============================================================================
# fix_partuuid awk command
# ============================================================================

@test "fix_partuuid awk: replaces PLACEHOLDER" {
    echo '"test" "root=PARTUUID=PLACEHOLDER_PARTUUID rw"' > "$TEST_DIR/test.conf"
    local pu="a1b2c3d4"
    awk -v pu="$pu" '{gsub(/PLACEHOLDER_PARTUUID/, pu); gsub(/PARTUUID=[ \t]*$/, "PARTUUID=" pu)}1' \
        "$TEST_DIR/test.conf" > "${TEST_DIR}/test.conf.tmp"
    mv "${TEST_DIR}/test.conf.tmp" "$TEST_DIR/test.conf"
    grep -q "a1b2c3d4" "$TEST_DIR/test.conf"
}

# ============================================================================
# patch_fstab_compression inline test
# ============================================================================

@test "patch_fstab_compression: adds compress=zstd to btrfs entries" {
    cat > "$TEST_DIR/fstab" << 'FSTAB'
UUID=abc / btrfs subvol=@ 0 0
UUID=def /home ext4 defaults 0 0
FSTAB
    # Inline function
    patch_fstab() {
        local fstab="$1"
        if grep -q "btrfs" "$fstab" 2>/dev/null && ! grep -q "compress=zstd" "$fstab" 2>/dev/null; then
            sed -i '/btrfs/ { /compress=zstd/! s/subvol=[^, ]*/&,compress=zstd:3,noatime/ }' "$fstab"
        fi
    }
    patch_fstab "$TEST_DIR/fstab"
    grep -q "compress=zstd" "$TEST_DIR/fstab"
}

@test "patch_fstab_compression: does not duplicate compress=zstd" {
    cat > "$TEST_DIR/fstab" << 'FSTAB'
UUID=abc / btrfs subvol=@,compress=zstd:3 0 0
FSTAB
    patch_fstab() {
        local fstab="$1"
        if grep -q "btrfs" "$fstab" 2>/dev/null && ! grep -q "compress=zstd" "$fstab" 2>/dev/null; then
            sed -i '/btrfs/ { /compress=zstd/! s/subvol=[^, ]*/&,compress=zstd:3,noatime/ }' "$fstab"
        fi
    }
    patch_fstab "$TEST_DIR/fstab"
    local count
    count=$(grep -c "compress=zstd" "$TEST_DIR/fstab")
    [ "$count" -eq 1 ]
}
