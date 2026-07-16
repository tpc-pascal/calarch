# Hướng dẫn sử dụng calarch

> Phiên bản mới nhất: v1.0.6 — Unified TUI, post-install độc lập, fix toàn bộ bug.

---

## Yêu cầu

- Panasonic CF-XZ6 (hoặc laptop x86_64 khác)
- 20 GB+ dung lượng trống, USB 4 GB+
- UEFI boot mode
- Arch ISO (tải từ [archlinux.org](https://archlinux.org/download/))

---

## Cài đặt từ Arch ISO

### Luồng 1 — Dùng archinstall + post-install (khuyên dùng)

```bash
# 1. Boot Arch USB, kiểm tra mạng
ping archlinux.org
# Nếu cần WiFi: iwctl

# 2. Chạy archinstall
archinstall
```

**Cấu hình từng mục trong archinstall:**

| Mục | Giá trị | Ghi chú |
|-----|---------|---------|
| **Archinstall language** | English | Giữ mặc định |
| **Disk configuration** | `Manual partitioning` | Chọn ổ đĩa (vd `/dev/nvme0n1`) |
| → **ESP partition** | `fat32`, mount: `/boot`, size: 512MB+ | **Bắt buộc mount `/boot`** nếu không archinstall không cho tiếp tục |
| → **Root partition** | `btrfs`, phần còn lại của disk | Để archinstall tự tạo subvolumes |
| **Bootloader** | `rEFInd` | Hoặc `systemd-boot` / `GRUB` |
| **Swap** | `True` (hoặc tuỳ bạn) | |
| **Hostname** | Nhập tên máy (vd `cfxz6`) | |
| **Root password** | Nhập mật khẩu root | |
| **User account** | Tạo user + password | Nhập username và password |
| **Profile** | `Hyprland` (nếu muốn desktop) | Bỏ qua nếu không cần |
| **Audio** | `pipewire` | |
| **Kernel** | `linux-zen` (khuyên dùng) | Hoặc `linux` mặc định |
| **Network configuration** | `NetworkManager` | |
| **Timezone** | Chọn múi giờ (vd `Asia/Ho_Chi_Minh`) | |
| **Locale** | `en_US.UTF-8` (hoặc `vi_VN`) | |
| **Optional repositories** | `multilib` (nếu cần Steam/Wine) | |

> **SAU KHI archinstall CHẠY XONG → chọn "Exit" (KHÔNG reboot)**

# 3. Kiểm tra mount point
ls /mnt/etc

# 4. Tải calarch và chạy post-install
pacman -Sy git
git clone --depth=1 https://github.com/tpc-pascal/calarch.git
cd calarch
sudo bash lib/post-install.sh post-install /mnt

# 5. Kiểm tra PARTUUID
cat /mnt/boot/refind_linux.conf
# Nếu thấy "PLACEHOLDER_PARTUUID" → fix:
#   blkid -s PARTUUID -o value /dev/nvme0n1p2
#   sudo bash lib/post-install.sh fix-partuuid /mnt <PARTUUID>

# 6. Reboot
umount -R /mnt
reboot
```

### Luồng 2 — Subvolume tùy chỉnh (thủ công)

Dành cho người dùng tự chia Btrfs subvolume (ví dụ `@`, `@home`, `@snapshots`, `@cache`, `@log`, `@pkg`).

```bash
# --- Định dạng (chỉ một lần) ---
mkfs.fat -F32 /dev/nvme0n1p1      # ESP
mkfs.btrfs -f /dev/nvme0n1p2      # Root

# --- Tạo subvolumes ---
mount /dev/nvme0n1p2 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@cache
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
umount /mnt

# --- Mount đúng thứ tự (QUAN TRỌNG) ---
mount -o compress=zstd:3,noatime,subvol=@ /dev/nvme0n1p2 /mnt
mkdir -p /mnt/{home,.snapshots,var/cache/pacman/pkg,var/log,boot}
mount -o compress=zstd:3,noatime,subvol=@home /dev/nvme0n1p2 /mnt/home
mount -o compress=zstd:3,noatime,subvol=@snapshots /dev/nvme0n1p2 /mnt/.snapshots
mount -o compress=zstd:3,noatime,subvol=@cache /dev/nvme0n1p2 /mnt/var/cache
mount -o compress=zstd:3,noatime,subvol=@log /dev/nvme0n1p2 /mnt/var/log
mount -o compress=zstd:3,noatime,subvol=@pkg /dev/nvme0n1p2 /mnt/var/cache/pacman/pkg
mount /dev/nvme0n1p1 /mnt/boot     # ESP

# --- Cài Arch Linux base ---
pacstrap /mnt base base-devel linux-zen linux-zen-headers linux-firmware \
  btrfs-progs intel-ucode git networkmanager vim sudo
genfstab -U /mnt >> /mnt/etc/fstab

# --- Chroot và cấu hình ---
arch-chroot /mnt
#   - Cài bootloader (rEFInd / systemd-boot / GRUB)
#   - Cấu hình mkinitcpio, password, hostname, timezone
#   - Xem hướng dẫn Arch Wiki

# --- Sau khi thoát chroot, chạy post-install ---
sudo bash lib/post-install.sh post-install /mnt

# --- Reboot ---
umount -R /mnt
reboot
```

> **Lưu ý:** `@pkg` là subvolume con của `@cache` (`/var/cache/pacman/pkg`). Phải mount `@cache` trước, sau đó mount `@pkg` chồng lên.

---

## Sau khi reboot lần đầu

1. **Login** bằng user đã tạo
2. **God-Mode setup** tự động chạy nếu là lần đăng nhập đầu tiên
3. Sau khi setup xong, chạy: `cd ~/calarch && bash start.sh`

---

## Unified TUI — bash start.sh

Chạy `bash start.sh` để mở menu chính:

| Option | Chức năng |
|--------|-----------|
| 1 | System Monitor — CPU, temp, freq, eco, super mode |
| 2 | Settings Panel — Super Mode, Affinity, Eco, Services |
| 3 | Drive Manager — mount/unmount partitions |
| 4 | Wallpaper Changer — chafa preview, set wallpaper |
| 5 | Focus Mode — Pomodoro + site blocker |
| 6 | Notes — Obsidian vault manager |
| 7 | Games — minetest, assaultcube, megaglest |
| 8 | rEFInd Sync — đồng bộ kernel ra ESP |
| 9 | Profiles — lưu/nạp cấu hình |
| P | Post-Install Setup — chạy sau khi cài Arch (một lần) |
| S | Safety Engine — grace period, undo, history |

---

## Các công cụ chi tiết

### System Monitor (`lib/system.sh`)

Hiển thị thông số hệ thống: CPU load, nhiệt độ, tần số, governor, eco mode, super mode.

```bash
# Từ TUI: chọn 1
# Hoặc chạy trực tiếp:
bash lib/system.sh
```

### Settings Panel (`lib/settings.sh`)

Ba nhóm cài đặt:

| Nhóm | Các toggle |
|------|------------|
| System | Super Mode, CPU Affinity, Eco Mode, Undervolt, Auto-rotate, Touchpad |
| Services | Docker, KVM/libvirtd, Ollama, Auto-maintenance |
| Apps | Obsidian, Website Blocker, Notes, Focus, Launcher, Firefox, Neovim, Spotify, Emacs |

```bash
# Từ TUI: chọn 2
bash lib/settings.sh
```

### Drive Manager (`lib/mount.sh`)

Quản lý tất cả partition/volume:

- List partitions (màu xanh = mounted, vàng = unmounted)
- Mount tự động theo fstype (NTFS, exfat, vfat, ext4, btrfs)
- Unmount an toàn, hỗ trợ lazy unmount
- Browse file manager

```bash
# Từ TUI: chọn 3
bash lib/mount.sh
```

### Wallpaper Changer (`lib/wallpaper.sh`)

- Chafa preview thumbnail ngay trong terminal
- Set wallpaper (hyprpaper/swaybg/feh)
- Random wallpaper
- Import custom ảnh

```bash
# Từ TUI: chọn 4
bash lib/wallpaper.sh
```

### Focus Mode (`lib/focus.sh`)

- Pomodoro timer (25/5/4 mặc định)
- Website blocker (chặn Facebook, Twitter, Reddit, YouTube...)
- Cấu hình trong `calarch.conf`

```bash
# Từ TUI: chọn 5
bash lib/focus.sh
```

### Notes (`lib/notes.sh`)

- Obsidian vault manager
- Tạo vault tại `~/notes/`

```bash
# Từ TUI: chọn 6
bash lib/notes.sh
```

### Games (`lib/games.sh`)

- minetest, assaultcube, megaglest (từ Arch official repo)

```bash
# Từ TUI: chọn 7
bash lib/games.sh
```

---

## rEFInd ESP Kernel Sync

Khi rEFInd không thấy Arch trong menu boot (do driver EFI không hỗ trợ Btrfs nén zstd).

### Kiểm tra trạng thái

```bash
bash lib/refind-sync.sh --check
```

### Đồng bộ kernel ra ESP

```bash
# Từ hệ thống đã cài
sudo bash lib/refind-sync.sh

# Từ ISO (mount sẵn /mnt)
sudo bash lib/refind-sync.sh --mnt /mnt

# Chỉ định ESP thủ công
sudo bash lib/refind-sync.sh --mnt /mnt --esp /dev/sdX1
```

### Các trường hợp đặc biệt

| Trường hợp | Xử lý |
|------------|-------|
| `/boot` là ESP (FAT32) | Tự động bỏ qua copy kernel, chỉ generate entry + hook |
| Nhiều ESP | Tự động chọn ESP có rEFInd hoặc đang mount |
| rEFInd chưa cài | Vẫn copy kernel nhưng skip entry |
| AMD CPU | Tự động copy amd-ucode |
| Nhiều kernels | Sync tất cả (linux, linux-zen, linux-lts, linux-hardened) |
| ESP sắp đầy | Kiểm tra dung lượng trước khi copy |

### Pacman Hook

Sau khi chạy `refind-sync.sh`, hook được cài tại:
- `/etc/pacman.d/hooks/calarch-sync-kernel.hook`
- Script: `/usr/local/bin/calarch-sync-kernel.sh`

Tự động chạy sau mỗi `pacman -Syu`.

---

## Fix PARTUUID

Nếu `refind_linux.conf` chứa `PLACEHOLDER_PARTUUID` hoặc để trống:

```bash
# Từ Arch ISO
mount -o subvol=@ /dev/nvme0n1p2 /mnt
blkid -s PARTUUID -o value /dev/nvme0n1p2
sudo bash lib/post-install.sh fix-partuuid /mnt <PARTUUID>

# Hoặc từ hệ thống đã boot
sudo bash start.sh --fix-partuuid /mnt <PARTUUID>
```

---

## Config Center — calarch.conf

Mọi tham số tập trung tại một file:

```bash
# ~/calarch/calarch.conf
AFFINITY_ACTIVE_CORES="0,1"     # Core cho active window
AFFINITY_BG_CORES="2,3"         # Core cho background
SUPER_COOL_THRESHOLD=30         # % load để xuống COOL
SUPER_HOT_THRESHOLD=70          # % load để lên HOT
SUPER_COOL_DEBOUNCE=10          # Giây load thấp liên tục
SUPER_HOT_DEBOUNCE=5            # Giây load cao liên tục
SUPER_COOL_GOVERNOR="powersave" # Governor khi COOL
SUPER_HOT_GOVERNOR="schedutil"  # Governor khi HOT
UNDERVOLT_CPU=-50               # CPU undervolt (mV)
UNDERVOLT_GPU=-20               # GPU undervolt (mV)
UNDERVOLT_CACHE=-50             # Cache undervolt (mV)
ECO_CHARGE_LIMIT=80             # % pin khi sạc
MAX_CSTATE=4                    # C-State thấp nhất
POMODORO_WORK_MINUTES=25        # Pomodoro work time
POMODORO_BREAK_MINUTES=5        # Pomodoro break time
POMODORO_CYCLES=4               # Số cycle Pomodoro
BLOCKER_SITES="facebook.com,twitter.com,..." # Sites cần chặn
KERNEL_PARAMS="nowatchdog processor.max_cstate=4 ..."
WALLPAPER_DIR="$HOME/Pictures/wallpapers"
WALLPAPER_ENGINE="hyprpaper"
REFIND_SYNC_ESP="true"          # Tự động sync kernel ra ESP
```

---

## Profiles (Quản lý cấu hình)

Lưu và nạp cấu hình từ `profiles/`:

```bash
# Qua TUI: start.sh → Profiles
# Hoặc CLI:
bash lib/core.sh profile save my-config   # Lưu
bash lib/core.sh profile load my-config   # Nạp
bash lib/core.sh profile list             # Danh sách
bash lib/core.sh profile delete my-config # Xóa
```

### Profiles mặc định

| Profile | Mô tả |
|---------|-------|
| **default** | Cân bằng hiệu năng/tiết kiệm |
| **performance** | Undervolt -80mV, schedutil, eco OFF |
| **battery** | Eco 60%, powersave, affinity core 0 |

---

## Safety Engine

### Grace Period

Khi thay đổi tham số critical (undervolt, governor, cstate):
1. Dashboard hiển thị countdown
2. Bạn có **5 phút** để xác nhận
3. Hết giờ → tự động revert về giá trị cũ
4. Confirm qua CLI: `bash lib/core.sh grace_confirm UNDERVOLT_CPU`

### Boot Guard

- Mỗi lần boot, calarch đếm số lần boot
- Nếu boot fail > 2 lần → tự động rollback config
- Kiểm tra: `bash lib/core.sh boot_check`

### Undo / History

```bash
bash lib/core.sh undo        # Hoàn tác thay đổi cuối
bash lib/core.sh log 10      # Xem lịch sử
```

---

## Fix lỗi thường gặp

### rEFInd không thấy Arch

```bash
bash lib/refind-sync.sh --check
sudo bash lib/refind-sync.sh
```

### PARTUUID bị trống hoặc PLACEHOLDER

```bash
mount -o subvol=@ /dev/nvme0n1p2 /mnt
blkid -s PARTUUID -o value /dev/nvme0n1p2
sudo bash lib/post-install.sh fix-partuuid /mnt <PARTUUID>
```

### Post-install bị lỗi

```bash
# Chạy lại (idempotent)
sudo bash lib/post-install.sh post-install /mnt
```

### God-Mode setup không chạy

```bash
rm -f /var/lib/godmode/firstboot-done
touch /var/lib/godmode/firstboot-pending
# Đăng nhập lại
```
