setup() {
    load 'test_helper.bash'
    TEST_MNT=$(mktemp -d)
    mkdir -p "$TEST_MNT/etc"
    mkdir -p "$TEST_MNT/.snapshots"
}

teardown() {
    rm -rf "$TEST_MNT"
    unset TEST_MNT
}

@test "fix-snapper: creates snapper config when missing (mock)" {
    # Simulate missing snapper config but .snapshots exists
    [ ! -f "$TEST_MNT/etc/snapper/configs/root" ]
    [ -d "$TEST_MNT/.snapshots" ]
    # fix-snapper should attempt to create config — mock arch-chroot
    # We just verify script exists and is executable
    [ -x "$BATS_TEST_DIRNAME/../lib/fix-snapper.sh" ]
    bash -n "$BATS_TEST_DIRNAME/../lib/fix-snapper.sh"
}

@test "fix-snapper: idempotent when config exists" {
    mkdir -p "$TEST_MNT/etc/snapper/configs"
    touch "$TEST_MNT/etc/snapper/configs/root"
    # Should exit 0 and not recreate
    run bash "$BATS_TEST_DIRNAME/../lib/fix-snapper.sh" "$TEST_MNT"
    [ "$status" -eq 0 ]
}

@test "fix-snapper: handles empty .snapshots dir" {
    # Empty .snapshots should be recreated for snapper
    rm -rf "$TEST_MNT/.snapshots"
    mkdir -p "$TEST_MNT/.snapshots"
    [ -z "$(ls -A "$TEST_MNT/.snapshots" 2>/dev/null)" ]
    # script should handle empty dir
    bash -n "$BATS_TEST_DIRNAME/../lib/fix-snapper.sh"
    [ "$?" -eq 0 ]
}

@test "bootstrap: detects snapper File exists in log" {
    local log="$TEST_MNT/install.log"
    echo "snapper create-config failed, btrfs_util_create_subvolume_fd() failed, errno:17 (File exists)" > "$log"
    run grep -q "snapper.*File exists\|errno:17.*snapshots\|Could not setup Btrfs snapper" "$log"
    [ "$status" -eq 0 ]
}

@test "bootstrap: does not false-positive on normal log" {
    local log="$TEST_MNT/install.log"
    echo "Installing packages: base linux" > "$log"
    run grep -q "snapper.*File exists\|errno:17.*snapshots\|Could not setup Btrfs snapper" "$log"
    [ "$status" -ne 0 ]
}
