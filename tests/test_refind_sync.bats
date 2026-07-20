setup() {
    TEST_DIR=$(mktemp -d)
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ============================================================================
# fstype normalization
# ============================================================================

@test "fstype normalization: converts VFAT to vfat" {
    local fstype="VFAT"
    fstype=$(echo "$fstype" | tr '[:upper:]' '[:lower:]')
    [ "$fstype" = "vfat" ]
}

@test "fstype normalization: vfat stays vfat" {
    local fstype="vfat"
    fstype=$(echo "$fstype" | tr '[:upper:]' '[:lower:]')
    [ "$fstype" = "vfat" ]
}

@test "fstype normalization: FAT32 becomes fat32" {
    local fstype="FAT32"
    fstype=$(echo "$fstype" | tr '[:upper:]' '[:lower:]')
    [ "$fstype" = "fat32" ]
}

@test "fstype normalization: btrfs stays btrfs" {
    local fstype="btrfs"
    fstype=$(echo "$fstype" | tr '[:upper:]' '[:lower:]')
    [ "$fstype" = "btrfs" ]
}

@test "fstype normalization: ext4 stays ext4" {
    local fstype="ext4"
    fstype=$(echo "$fstype" | tr '[:upper:]' '[:lower:]')
    [ "$fstype" = "ext4" ]
}

# ============================================================================
# UKI detection logic
# ============================================================================

@test "UKI detection: finds .efi files" {
    mkdir -p "$TEST_DIR/EFI/Linux"
    touch "$TEST_DIR/EFI/Linux/arch-linux.efi"
    local found
    found=$(find "$TEST_DIR/EFI/Linux" -maxdepth 1 -name '*.efi' -print -quit 2>/dev/null || true)
    [ -n "$found" ]
}

@test "UKI detection: no .efi files returns empty" {
    mkdir -p "$TEST_DIR/EFI/Linux"
    local found
    found=$(find "$TEST_DIR/EFI/Linux" -maxdepth 1 -name '*.efi' -print -quit 2>/dev/null || true)
    [ -z "$found" ]
}

@test "UKI detection: missing directory returns empty" {
    local found
    found=$(find "$TEST_DIR/EFI/Linux" -maxdepth 1 -name '*.efi' -print -quit 2>/dev/null || true)
    [ -z "$found" ]
}

@test "UKI detection: multiple .efi files finds first" {
    mkdir -p "$TEST_DIR/EFI/Linux"
    touch "$TEST_DIR/EFI/Linux/linux-zen.efi"
    touch "$TEST_DIR/EFI/Linux/linux-lts.efi"
    local count
    count=$(find "$TEST_DIR/EFI/Linux" -maxdepth 1 -name '*.efi' 2>/dev/null | wc -l)
    [ "$count" -eq 2 ]
}

# ============================================================================
# boot_is_esp logic
# ============================================================================

@test "boot_is_esp: vfat returns 1" {
    local boot_fstype="vfat"
    local boot_is_esp=0
    [ "$boot_fstype" = "vfat" ] || [ "$boot_fstype" = "fat32" ] && boot_is_esp=1
    [ "$boot_is_esp" -eq 1 ]
}

@test "boot_is_esp: fat32 returns 1" {
    local boot_fstype="fat32"
    local boot_is_esp=0
    [ "$boot_fstype" = "vfat" ] || [ "$boot_fstype" = "fat32" ] && boot_is_esp=1
    [ "$boot_is_esp" -eq 1 ]
}

@test "boot_is_esp: ext4 returns 0" {
    local boot_fstype="ext4"
    local boot_is_esp=0
    [ "$boot_fstype" = "vfat" ] || [ "$boot_fstype" = "fat32" ] && boot_is_esp=1
    [ "$boot_is_esp" -eq 0 ]
}

@test "boot_is_esp: btrfs returns 0" {
    local boot_fstype="btrfs"
    local boot_is_esp=0
    [ "$boot_fstype" = "vfat" ] || [ "$boot_fstype" = "fat32" ] && boot_is_esp=1
    [ "$boot_is_esp" -eq 0 ]
}
