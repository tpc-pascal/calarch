# Hướng dẫn sử dụng calarch — Panasonic CF-XZ6 chuyên biệt

> ⚠️ **Repo này chỉ hỗ trợ Panasonic CF-XZ6 (CFXZ6-1 / i5-7300U / HD Graphics 620). Không khuyến nghị dùng trên máy khác.**

> Phiên bản mới nhất: v1.0.16 — CF-XZ6 only, snapper @snapshots fix, God-Mode guided setup

-----------------------------------------------------------------------

## Phần 1 — Cài đặt

### Yêu cầu — CF-XZ6

- **Panasonic CF-XZ6 (CFXZ6-1) duy nhất** — i5-7300U / HD Graphics 620 / 8GB RAM / 244GB GPT
  (đã test: `sda1` ESP 512MiB `C12A7328` giữ nguyên dual-boot Windows, `sda9` Btrfs 68GB `@/@home/@snapshots/@cache/@log/@pkg` `compress=zstd`)
  Không khuyến nghị dùng trên laptop khác (undervolt, thermal, kernel params đã tune cho 7300U/HD620).
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
| Sau reboot | Lần đầu login: chạy post-install + **God-Mode setup (guided)** — menu checklist hiện trực tiếp, không chạy ngầm (dùng bản calarch đã bundle, `git pull` chỉ là fallback) |

> **Cấu hình khuyến nghị trong archinstall (cho newbie):**

| Mục | Chọn | Ghi chú |
|-----|------|---------|
| Network | **Enable + NetworkManager** | Bắt buộc trước khi cài, nếu không mirrors không tải được |
| Disk | Đúng ổ đĩa mình muốn | archinstall cảnh báo xoá toàn bộ dữ liệu |
| Filesystem | **Btrfs** | calarch tối ưu cho Btrfs; ext4/xfs vẫn cài được (boot bình thường) |
| Bootloader | **rEFInd** (CF-XZ6 dùng `ukі:true`, `/boot` = ESP `sda1` 512MiB) | systemd-boot cũng được |
| Btrfs Snapshots | **None** nếu bạn đã tự tạo subvol `@snapshots` (6 subvol CF-XZ6) — calarch tự tạo snapper sau | Chọn **Snapper** → **xoá** `@snapshots` khỏi danh sách subvol trước khi cài |
| User | **Phải tạo user thường** (không chỉ root) | Quên → calarch hỏi chạy lại hoặc tạo giúp |
| Kết thúc | **Exit** (KHÔNG chọn Reboot) | Reboot sẽ thoát luôn khỏi quy trình |

> **Ghi chú CF-XZ6:**
> - Hostname, user và password do **bạn tự đặt trong archinstall** — calarch không ghi đè
> - Disk CF-XZ6 mặc định: `sda1` ESP 512MiB giữ nguyên (dual-boot Windows), `sda9` Btrfs 68GB CF-XZ6 preset 6 subvol `@/@home/@snapshots/@cache/@log/@pkg` `compress=zstd`
> - **Snapper:** đã tự tạo `@snapshots` → chọn **Btrfs Snapshots = None**; nếu chọn **Snapper** trong archinstall thì xoá `@snapshots` khỏi danh sách trước khi cài (calarch sẽ tự `snapper create-config` sau).
> - Console font mặc định `ter-132n` (phù hợp HiDPI CF-XZ6), có thể chọn font khác khi chạy bootstrap
> - Kernel params CF-XZ6 (`i915.enable_fbc/psr/rc6`, `mitigations=off`, `pcie_aspm=force` cho HD620/7300U) áp dụng cho **mọi bootloader** ngay lúc cài
> - Nếu chọn filesystem không phải Btrfs, calarch **tự thích nghi** (không còn ép `rootflags=subvol=@`)

-----------------------------------------------------------------------

### Sau khi reboot lần đầu

1. **Login:** user + password do bạn tự đặt trong archinstall
2. **Tự động:** post-install chạy 1 lần (kernel params, font, rEFInd), sau đó **God-Mode setup hiện menu checklist** (gum) ngay trên màn hình — bạn tick các bước muốn chạy rồi nhấn Enter; calarch chạy từng bước có log + idempotent (chạy lại không lặp)
3. **Thiếu mạng?** calarch in dòng nhắc — kết nối WiFi/ethernet rồi đăng nhập lại để tiếp tục
4. **Hoàn tất:** log tại `/tmp/godmode-setup.log`, trạng thái tại `/var/lib/godmode/godmode-steps.done`; về sau gọi lại bất cứ lúc nào bằng `cd ~/calarch && bash start.sh` → **G**

> **God-Mode Setup gồm 8 bước (tất cả mặc định chọn hết):**
>
> | # | Bước | Tác dụng |
> |---|------|----------|
> | 1 | yay | AUR helper (parallel downloads, build từ PKGBUILD) |
> | 2 | Hyprland JaKooLit | Desktop full HiDPI, animations, app launcher |
> | 3 | ZRAM + sysctl | Nén RAM 8 GB, giảm swap ổ cứng |
> | 4 | intel-undervolt | Giảm điện áp CPU/GPU/cache → mát, tiết kiệm pin |
> | 5 | thermald + TLP | Điều khiển nhiệt độ + quản lý năng lượng |
> | 6 | Super-Mode & Eco | Daemon ưu tiên hiệu năng (Super) / tiết kiệm pin (Eco) |
> | 7 | Tweaks | Pacman/reflector/journal tinh chỉnh |
> | 8 | ananicy-cpp | Ưu tiên IO/CPU cho app (mặc định tắt) |

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
| 6 | Notes — vault manager (theo `NOTES_ENGINE`) |
| 7 | Games — minetest, assaultcube, megaglest |
| 8 | rEFInd Sync — đồng bộ kernel ra ESP |
| 9 | Profiles — lưu/nạp cấu hình |
| P | Post-Install Setup — chạy sau khi cài Arch (một lần) |
| G | God-Mode Setup — yay, Hyprland, ZRAM, undervolt, thermal, super-mode |
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
| Notes | 6 | `lib/notes.sh` | Notes vault manager (Obsidian/Logseq/Emacs/md theo `NOTES_ENGINE`) |
| Games | 7 | `lib/games.sh` | minetest, assaultcube, megaglest |
| rEFInd Sync | 8 | `lib/refind-sync.sh` | Đồng bộ kernel + entry + pacman hook ra ESP |
| Profiles | 9 | `lib/profiles.sh` | Lưu/nạp profile config |
| Post-Install | P | `lib/post-install.sh` | Chạy sau khi cài Arch (một lần) |
| God-Mode Setup | G | `lib/godmode-setup.sh` | Checklist 8 bước setup hệ thống |
| Safety Engine | S | `lib/safety.sh` | Grace period, undo, history |
| Anime Player | — | `lib/anime.sh` | Search Nyaa.si → xem anime (magnet qua web-torrent) |
| YouTube Player | — | `lib/yt-video.sh` | Search/playlist YouTube terminal (yt-dlp + mpv) |
| Spotify | — | `lib/spotify.sh` | Spotify + Spicetify (adblock, Dribbblish) |
| Neovim | — | `lib/neovim.sh` | Neovim + LazyVim (IDE, formatters) |
| Emacs | — | `lib/emacs.sh` | Emacs + Org-mode + org-roam |
| Firefox Config | — | `lib/firefox.sh` | user.js privacy + Sidebery vertical tabs |
| Launcher | — | `lib/launcher.sh` | Rofi Ultrafocus theme |
| Web Dashboard | — | `python3 lib/web.sh` | HTTP server localhost:8765 (config/status API) |

> **Anime Player (magnet):** khi chọn file từ Nyaa.si, magnet được phát qua
> **web-torrent engine** (`webtorrent-cli`, cài tự động qua npm) stream và đẩy lên
> **mpv** — không phát magnet trực tiếp bằng mpv. mpv vẫn dùng cho direct stream
> (YouTube, file thường). Nếu thiếu npm/webtorrent-cli: `sudo npm install -g webtorrent-cli`.

### God-Mode Setup — lib/godmode-setup.sh

Chạy lần đầu ngay khi login sau cài Arch; muốn gọi lại:

```bash
cd ~/calarch && bash start.sh       # chọn G
bash lib/godmode-setup.sh           # hoặc trực tiếp
```

- **Idempotent:** bước nào đã chạy thành công thì ghi vào `/var/lib/godmode/godmode-steps.done` — chạy lại tự bỏ qua
- **Checklist gum:** mặc định chọn hết, bạn chỉ cần Enter
- **Log:** `/tmp/godmode-setup.log`

Verify nhanh sau khi xong:

```bash
zramctl                                    # ZRAM 8 GB đã active
sudo intel-undervolt read                  # current/CPU/GPU/Cache undervolt
sudo systemctl status undervolt thermald tlp.service  # các service đang chạy
```

> **Hyprland JaKooLit:** installer tương tác (chọn GPU Intel, display server SDDM,
> bỏ nvidia). Nếu installer không hoàn tất (lỗi tạm thời), chạy lại option **G**
> — bước 2 sẽ thử lại, các bước khác không bị ảnh hưởng. Sau khi vào desktop,
> script tự cài `hyprland-event-monitor.sh` (affinity + eco theo app đang chạy).

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
NOTES_ENGINE="emacs-org"           # obsidian | logseq | emacs-org | vi/vim/nvim
REFIND_SYNC_ESP="true"             # false = bỏ qua kernel sync ra ESP (rEFInd đọc kernel trực tiếp)
```

> **REFIND_SYNC_ESP=false:** `lib/refind-sync.sh` sẽ bỏ qua toàn bộ bước đồng bộ
> kernel ra ESP (kể cả khi /boot nằm trên Btrfs+zstd). Chỉ dùng khi bạn chắc chắn
> rEFInd đọc được kernel trực tiếp (vd /boot là FAT32/ESP).

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

### God-Mode setup không chạy khi login

```bash
cat /tmp/godmode-setup.log                 # Xem lỗi
rm -f /var/lib/godmode/firstboot-done
touch /var/lib/godmode/firstboot-pending
# Đăng nhập lại — hoặc chạy thủ công:
bash ~/calarch/lib/godmode-setup.sh
```

### Hyprland JaKooLit không hoàn tất

```bash
bash ~/calarch/lib/godmode-setup.sh        # Chạy lại — bước 2 thử lại, bước khác skip
bash ~/calarch/start.sh                    # rồi chọn G
```

Nếu installer chết giữa chừng (lỗi download), check mạng rồi thử lại. Desktop
vẫn vào được bằng bất kỳ WM/DE nào bạn cài sau; calarch không ép buộc Hyprland.

### Kiểm tra god-mode sau khi xong

```bash
zramctl                                   # 8 GB zstd đang hoạt động
sudo intel-undervolt read                 # undervolt đã áp dụng?
sudo systemctl is-enabled undervolt thermald tlp.service
super-mode status                          # super/eco daemon (bước 6)
```
