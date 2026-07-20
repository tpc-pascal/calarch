# Hướng dẫn sử dụng calarch

> Phiên bản mới nhất: v1.0.11 — Pre-archinstall wizard, guided partition

------------------------------------------------------------------------

## Yêu cầu

- Panasonic CF-XZ6 (hoặc laptop x86_64 khác)
- 20 GB+ dung lượng trống, USB 4 GB+
- UEFI boot mode
- Arch ISO (tải từ [archlinux.org](https://archlinux.org/download/))

------------------------------------------------------------------------

## Cài đặt từ Arch ISO

> Quy trình **bán tự động**: bootstrap.sh chọn đĩa → archinstall TUI (partition/
> filesystem/bootloader/locale/timezone) → chọn Exit → calarch post-install tự động.

### Lệnh duy nhất

```bash
# Boot Arch USB → kiểm tra mạng (iwctl nếu cần WiFi)
bash <(curl -s https://raw.githubusercontent.com/tpc-pascal/calarch/main/bootstrap.sh)
```

### Quy trình

| Bước | Mô tả |
|------|-------|
| `bootstrap.sh` | Kiểm tra UEFI + network → chọn font → chọn **đĩa cài đặt** → mở **archinstall TUI** |
| Trong archinstall | Partition đĩa, chọn Btrfs (khuyên dùng), cài bootloader, đặt locale / timezone |
| Sau archinstall | Chọn **Exit** (KHÔNG chọn Reboot) |
| calarch post-install | Tự động: hostname (cfxz6), user (pascal), passwords (tự sinh), rEFInd, kernel params, console font `ter-132n`, `.bash_login` godmode |
| Sau reboot | Lần đầu login: tự động clone calarch + chạy post-install + god-mode setup |

> **Ghi chú:**
> - Đĩa đã chọn ở bước trước archinstall — khi vào TUI, chọn đúng đĩa đó
> - Trong archinstall chỉ cần partition, filesystem, bootloader, locale, timezone
> - Hostname (cfxz6), user (pascal) và passwords do calarch đặt tự động, lưu tại `/root/calarch-credentials.txt`
> - Console font mặc định `ter-132n` (phù hợp HiDPI), có thể chọn font khác khi chạy bootstrap

### Nâng cao — partition thủ công

Nếu muốn tự chia Btrfs subvolume, partition trước rồi chạy bootstrap.sh — trong
archinstall TUI, chọn các partition có sẵn thay vì tạo mới.

```bash
# Partition thủ công (ví dụ ESP + Btrfs root)
mkfs.fat -F32 /dev/nvme0n1p1
mkfs.btrfs -f /dev/nvme0n1p2

# Tạo subvolumes
mount /dev/nvme0n1p2 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
umount /mnt

# Chạy bootstrap → archinstall TUI → chọn partition có sẵn → Exit
bash <(curl -s https://raw.githubusercontent.com/tpc-pascal/calarch/main/bootstrap.sh)
```

> **Lưu ý:** Nếu dùng `@cache`/`@log`/`@pkg`, mount đúng thứ tự — `@pkg` là
> subvolume con của `@cache`. Xem Arch Wiki.

------------------------------------------------------------------------

## Sau khi reboot lần đầu

1. **Login:** user `pascal` (password đã hiển thị trước reboot, lưu tại
   `/root/calarch-credentials.txt` trên ISO)
2. **Tự động:** `.bash_login` cài git, clone calarch, chạy post-install +
   god-mode setup (ngầm, không block login) — log tại `/tmp/godmode-setup.log`
3. **Kiểm tra:** `cat /tmp/godmode-setup.log` — nếu có lỗi, login sau tự thử lại
4. **Hoàn tất:** `cd ~/calarch && bash start.sh`

------------------------------------------------------------------------

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

------------------------------------------------------------------------

## Các công cụ chi tiết

### System Monitor (`lib/system.sh`)

Hiển thị thông số hệ thống: CPU load, nhiệt độ, tần số, governor, eco mode,
super mode.

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

------------------------------------------------------------------------

## rEFInd ESP Kernel Sync

Khi rEFInd không thấy Arch trong menu boot (do driver EFI không hỗ trợ Btrfs
nén zstd).

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
| **UKI mode** | Phát hiện UKI → skip kernel sync + entry, chỉ cài hook |

### UKI Mode

Nếu dùng UKI (Unified Kernel Image), rEFInd tự động dò tìm file `.efi` trong
ESP. `refind-sync.sh` sẽ tự phát hiện và:

- Bỏ qua copy kernel (kernel đã bundle trong UKI)
- Bỏ qua generate rEFInd entry
- Chỉ cài pacman hook để rebuild UKI sau mỗi kernel update

### Pacman Hook

Sau khi chạy `refind-sync.sh`, hook được cài tại:

- `/etc/pacman.d/hooks/calarch-sync-kernel.hook`
- Script: `/usr/local/bin/calarch-sync-kernel.sh`

Tự động chạy sau mỗi `pacman -Syu`.

------------------------------------------------------------------------

## Fix PARTUUID

> **Không cần nếu dùng UKI** — UKI bundle kernel + initramfs + cmdline,
> rEFInd tự boot được.

Nếu `refind_linux.conf` chứa `PLACEHOLDER_PARTUUID` hoặc để trống:

```bash
# Từ Arch ISO
mount -o subvol=@ /dev/nvme0n1p2 /mnt
blkid -s PARTUUID -o value /dev/nvme0n1p2
sudo bash lib/post-install.sh fix-partuuid /mnt <PARTUUID>

# Hoặc từ hệ thống đã boot
sudo bash start.sh --fix-partuuid /mnt <PARTUUID>
```

------------------------------------------------------------------------

## Config Center — calarch.conf

Mọi tham số tập trung tại một file:

```bash
# ~/calarch/calarch.conf
AFFINITY_ACTIVE_CORES="0,1"       # Core cho active window
AFFINITY_BG_CORES="2,3"           # Core cho background
SUPER_COOL_THRESHOLD=30           # % load để xuống COOL
SUPER_HOT_THRESHOLD=70            # % load để lên HOT
SUPER_COOL_DEBOUNCE=10            # Giây load thấp liên tục
SUPER_HOT_DEBOUNCE=5              # Giây load cao liên tục
SUPER_COOL_GOVERNOR="powersave"   # Governor khi COOL
SUPER_HOT_GOVERNOR="schedutil"    # Governor khi HOT
UNDERVOLT_CPU=-50                 # CPU undervolt (mV)
UNDERVOLT_GPU=-20                 # GPU undervolt (mV)
UNDERVOLT_CACHE=-50               # Cache undervolt (mV)
ECO_CHARGE_LIMIT=80               # % pin khi sạc
MAX_CSTATE=4                      # C-State thấp nhất
POMODORO_WORK_MINUTES=25          # Pomodoro work time
POMODORO_BREAK_MINUTES=5          # Pomodoro break time
POMODORO_CYCLES=4                 # Số cycle Pomodoro
BLOCKER_SITES="facebook.com,twitter.com,..."
KERNEL_PARAMS="nowatchdog processor.max_cstate=4 ..."
WALLPAPER_DIR="$HOME/Pictures/wallpapers"
WALLPAPER_ENGINE="hyprpaper"
REFIND_SYNC_ESP="true"
```

------------------------------------------------------------------------

## Profiles

Lưu và nạp cấu hình từ `profiles/`:

```bash
# Qua TUI: start.sh → Profiles
# Hoặc CLI:
bash lib/core.sh profile save my-config     # Lưu
bash lib/core.sh profile load my-config     # Nạp
bash lib/core.sh profile list               # Danh sách
bash lib/core.sh profile delete my-config   # Xóa
```

### Profiles mặc định

| Profile | Mô tả |
|---------|-------|
| **default** | Cân bằng hiệu năng/tiết kiệm |
| **performance** | Undervolt -80mV, schedutil, eco OFF |
| **battery** | Eco 60%, powersave, affinity core 0 |

------------------------------------------------------------------------

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

------------------------------------------------------------------------

## Fix lỗi thường gặp

### rEFInd không thấy Arch

```bash
bash lib/refind-sync.sh --check
sudo bash lib/refind-sync.sh
```

### PARTUUID bị trống hoặc PLACEHOLDER

> Nếu dùng UKI, bỏ qua mục này (UKI không cần refind_linux.conf).

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
