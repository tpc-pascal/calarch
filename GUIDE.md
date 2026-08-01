# Hướng dẫn sử dụng calarch

> Phiên bản mới nhất: v1.0.13 — Newbie-friendly archinstall: dynamic rootflags, kernel params mọi bootloader, bundle calarch

-----------------------------------------------------------------------

## Phần 1 — Cài đặt

### Yêu cầu

- Panasonic CF-XZ6 (hoặc laptop x86_64 khác)
- 20 GB+ dung lượng trống, USB 4 GB+
- UEFI boot mode
- Arch ISO (tải từ [archlinux.org](https://archlinux.org/download/))

-----------------------------------------------------------------------

### Cài đặt từ Arch ISO

> Quy trình **bán tự động**: bootstrap.sh tự kết nối mạng (hỏi SSID/password nếu
> cần) → archinstall TUI (bạn tự đặt disk, hostname, user, password, bootloader,
> locale, timezone) → chọn Exit → calarch post-install tự động.

```bash
# Boot Arch USB → chạy (script tự kết nối WiFi nếu chưa có mạng)
bash <(curl -s https://tpc-pascal.github.io/calarch/install)
```

> **Fallback** (nếu GitHub Pages không truy cập được):
> ```bash
> bash <(curl -s https://raw.githubusercontent.com/tpc-pascal/calarch/main/bootstrap.sh)
> ```
>
> **Verify checksum** (tùy chọn):
> ```bash
> curl -sO https://tpc-pascal.github.io/calarch/install
> echo "$(curl -s https://tpc-pascal.github.io/calarch/install.sha256)  install" | sha256sum -c - && bash install
> ```

| Bước | Mô tả |
|------|-------|
| `bootstrap.sh` | Kiểm tra UEFI + network (tự hỏi SSID/password nếu chưa có mạng) → chọn font → xem cheat-sheet → mở **archinstall TUI** |
| Trong archinstall | Bạn tự đặt: disk, partition, filesystem (Btrfs khuyên dùng), bootloader, locale, timezone, **hostname, user, password** |
| Sau archinstall | Chọn **Exit** (KHÔNG chọn Reboot); calarch tự kiểm tra kết quả (fstab, user, bootloader) |
| calarch post-install | Tự động: kernel params (mọi bootloader), console font, rEFInd (nếu dùng), bundle calarch vào `~/calarch`, `.bash_login` godmode |
| Sau reboot | Lần đầu login: chạy post-install + god-mode setup (dùng bản calarch đã bundle, `git pull` chỉ là fallback) |

> **Cấu hình khuyến nghị trong archinstall (cho newbie):**

| Mục | Chọn | Ghi chú |
|-----|------|---------|
| Network | **Enable + NetworkManager** | Bắt buộc trước khi cài, nếu không mirrors không tải được |
| Disk | Đúng ổ đĩa mình muốn | archinstall cảnh báo xoá toàn bộ dữ liệu |
| Filesystem | **Btrfs** | calarch tối ưu cho Btrfs; ext4/xfs vẫn cài được (boot bình thường) |
| Bootloader | **rEFInd** (dễ nhất) hoặc systemd-boot | GRUB cũng được |
| User | **Phải tạo user thường** (không chỉ root) | Quên → calarch hỏi chạy lại hoặc tạo giúp |
| Kết thúc | **Exit** (KHÔNG chọn Reboot) | Reboot sẽ thoát luôn khỏi quy trình |

> **Ghi chú:**
> - Hostname, user và password do **bạn tự đặt trong archinstall** — calarch không ghi đè
> - Disk cũng do bạn tự chọn trong archinstall
> - Console font mặc định `ter-132n` (phù hợp HiDPI), có thể chọn font khác khi chạy bootstrap
> - Kernel params tinh chỉnh (i915, mitigations...) áp dụng cho **mọi bootloader** ngay lúc cài
> - Nếu chọn filesystem không phải Btrfs, calarch **tự thích nghi** (không còn ép `rootflags=subvol=@`)

-----------------------------------------------------------------------

### Sau khi reboot lần đầu

1. **Login:** user + password do bạn tự đặt trong archinstall
2. **Tự động:** `.bash_login` chạy post-install + god-mode setup (ngầm, không block login) — dùng bản calarch đã bundle sẵn tại `~/calarch`; nếu chưa có mạng sẽ in dòng nhắc, đăng nhập lại để chạy tiếp. Log tại `/tmp/godmode-setup.log`
3. **Kiểm tra:** `cat /tmp/godmode-setup.log` — nếu có lỗi, login sau tự thử lại
4. **Hoàn tất:** `cd ~/calarch && bash start.sh`

-----------------------------------------------------------------------

## Phần 2 — Sử dụng

### Unified TUI — bash start.sh

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

### Các công cụ chi tiết

Mọi công cụ đều mở được từ TUI (số tương ứng) hoặc chạy trực tiếp:

| Công cụ | TUI | Script | Mô tả |
|---------|-----|--------|-------|
| System Monitor | 1 | `lib/system.sh` | CPU, temp, freq, governor, eco/super mode |
| Settings Panel | 2 | `lib/settings.sh` | Super Mode, Affinity, Eco, Undervolt, Services, Apps |
| Drive Manager | 3 | `lib/mount.sh` | Mount/unmount partition theo fstype |
| Wallpaper Changer | 4 | `lib/wallpaper.sh` | Chafa preview, hyprpaper/swaybg/feh |
| Focus Mode | 5 | `lib/focus.sh` | Pomodoro + website blocker |
| Notes | 6 | `lib/notes.sh` | Obsidian vault manager |
| Games | 7 | `lib/games.sh` | minetest, assaultcube, megaglest |

-----------------------------------------------------------------------

### rEFInd ESP Kernel Sync

Khi rEFInd không thấy Arch trong menu boot (do driver EFI không hỗ trợ Btrfs
nén zstd).

```bash
bash lib/refind-sync.sh --check    # Kiểm tra trạng thái
sudo bash lib/refind-sync.sh       # Đồng bộ kernel ra ESP
```

| Trường hợp | Xử lý |
|------------|-------|
| `/boot` là ESP (FAT32) | Tự động bỏ qua copy kernel, chỉ generate entry + hook |
| Nhiều ESP | Tự động chọn ESP có rEFInd hoặc đang mount |
| rEFInd chưa cài | Vẫn copy kernel nhưng skip entry |
| AMD CPU | Tự động copy amd-ucode |
| Nhiều kernels | Sync tất cả (linux, linux-zen, linux-lts, linux-hardened) |
| ESP sắp đầy | Kiểm tra dung lượng trước khi copy |
| **UKI mode** | Phát hiện UKI → skip kernel sync + entry, chỉ cài hook |

> **UKI Mode:** rEFInd tự dò file `.efi` trong ESP — bỏ qua copy kernel/entry,
> chỉ cài pacman hook rebuild UKI sau mỗi kernel update.
>
> **Pacman Hook:** sau khi sync, hook tự chạy mỗi `pacman -Syu` tại
> `/etc/pacman.d/hooks/calarch-sync-kernel.hook` + `/usr/local/bin/calarch-sync-kernel.sh`.

-----------------------------------------------------------------------

### Config Center — calarch.conf

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

-----------------------------------------------------------------------

### Profiles

Lưu và nạp cấu hình từ `profiles/`:

```bash
bash lib/core.sh profile save my-config     # Lưu
bash lib/core.sh profile load my-config     # Nạp
bash lib/core.sh profile list               # Danh sách
bash lib/core.sh profile delete my-config   # Xóa
```

| Profile | Mô tả |
|---------|-------|
| **default** | Cân bằng hiệu năng/tiết kiệm |
| **performance** | Undervolt -80mV, schedutil, eco OFF |
| **battery** | Eco 60%, powersave, affinity core 0 |

-----------------------------------------------------------------------

### Safety Engine

- **Grace Period:** thay đổi tham số critical (undervolt, governor, cstate) →
  đếm ngược 5 phút, hết giờ tự revert. Confirm: `bash lib/core.sh grace_confirm UNDERVOLT_CPU`
- **Boot Guard:** boot fail > 2 lần → tự rollback config.
  Kiểm tra: `bash lib/core.sh boot_check`
- **Undo / History:**
  ```bash
  bash lib/core.sh undo        # Hoàn tác thay đổi cuối
  bash lib/core.sh log 10      # Xem lịch sử
  ```

-----------------------------------------------------------------------

## Phần 3 — Xử lý sự cố

### Quên tạo user trong archinstall

Bootstrap báo **"CHUA tao user thuong (uid>=1000)"**. Chọn:

- `Y` — chạy lại archinstall để tạo user
- `c` — để calarch tự tạo user + đặt hostname/locale/timezone giúp
- `n` — thoát, boot lại và chạy lại

### Chọn nhầm Reboot trong archinstall

Máy sẽ reboot luôn trước khi calarch kịp chạy post-install. Xử lý:

1. Boot lại USB Arch, chạy lại `bash <(curl -s https://tpc-pascal.github.io/calarch/install)`
2. Hoặc chroot vào hệ thống đã cài và chạy `sudo bash lib/post-install.sh post-install /mnt`

### Filesystem không phải Btrfs

- Hệ thống **vẫn boot bình thường** — calarch tự phát hiện và không ép `rootflags=subvol=@`
- Kernel params tinh chỉnh (i915, mitigations...) chỉ áp dụng **đủ** khi dùng rEFInd; hệ thống chưa có Btrfs thì một số tính năng (snapshot) bị bỏ qua

### rEFInd không thấy Arch

```bash
bash lib/refind-sync.sh --check
sudo bash lib/refind-sync.sh
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
