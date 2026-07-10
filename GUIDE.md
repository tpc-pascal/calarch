## Hướng dẫn sử dụng

> **Phiên bản mới (v2.0):** Dashboard real-time + Config center + Safety engine.
> Xem hướng dẫn chi tiết bên dưới.

### Yêu cầu

- Panasonic CF-XZ6 (hoặc laptop x86_64 khác)
- 20GB+ free disk, USB 4GB+
- UEFI boot mode
- Arch ISO (tải từ [archlinux.org](https://archlinux.org/download/))

### Cài mới hoàn toàn (từ Arch ISO)

```bash
# 1. Boot Arch USB, kiểm tra mạng
ping archlinux.org          # iwctl nếu cần WiFi

# 2. Tải calarch
pacman -Sy git
git clone https://github.com/tpc-pascal/calarch.git
cd calarch

# 3. Chạy
bash lib/auto-install-arch.sh
```

**Chọn option 1** (Full Install) → `archinstall` TUI mở ra, bạn tự chọn:
- Partition (dual-boot với Windows an toàn)
- Bootloader (rEFInd / systemd-boot / GRUB)
- Filesystem (Btrfs khuyên dùng)
- User & password

Sau khi `archinstall` xong → **chọn "Exit"** (đừng reboot) → calarch tự chạy post-install: kernel params, @snapshots, clone repo, first-boot service → reboot.

### Cài từ .run (release)

```bash
bash calarch-v1.0.run               # auto-detect: ISO → menu, installed → setup
bash calarch-v1.0.run install       # menu (Full Install / Post-Install / Advanced)
bash calarch-v1.0.run setup         # God-Mode setup (Hyprland, CPU affinity...)
bash calarch-v1.0.run post-install  # calarch post-install trên /mnt
bash calarch-v1.0.run refind        # sinh refind_linux.conf
bash calarch-v1.0.run shell         # extracted env
bash calarch-v1.0.run check         # kiểm tra trạng thái
```

### Đã có Arch + rEFInd

```bash
cd calarch
bash lib/auto-install-arch.sh --post-install /mnt   # chạy post-install
# Hoặc chỉ generate refind_linux.conf:
bash lib/auto-install-arch.sh --refind /mnt
```

### Sau reboot — tự động hoàn toàn

1. **NetworkManager** đã được enable → máy tự động kết nối internet
2. **God-Mode setup** tự chạy ngay khi bạn login lần đầu: cài Hyprland, thermal, ZRAM, CPU affinity, Super Mode daemon
3. Sau khi setup xong → **System ready!**

> Quá trình này chạy hoàn toàn tự động. Không cần can thiệp.

## Dashboard (start.sh)

Chạy lệnh sau để mở live dashboard:

```bash
cd ~/calarch
bash start.sh
```

### Giao diện

Dashboard hiển thị 7 box trong 1 màn hình duy nhất:

```
┌─ CALARCH CONTROL CENTER ──────────────────────────────────────────────┐
│ [1]SYSTEM [2]SERVICES [3]FOCUS [4]PROFILES [5]TOOLS [6]STATUS  P . Q │
├───────────────────────────────────────────────────────────────────────┤
│ ┌── SYSTEM ─────────────┐ ┌── SERVICES ────────────┐                 │
│ │ CPU 62% 52°C 2.81GHz  │ │ Docker:ON KVM:OFF      │                 │
│ │ Eco:ON 80% Super:COOL  │ │ Ollama:ON Maint:ON     │                 │
│ │ UV:-50/-20/-50 CState4 │ │ Rotate:OFF Touch:ON    │                 │
│ │ Enter=edit Drag=title  │ │ Enter=toggle           │                 │
│ └────────────────────────┘ └────────────────────────┘                 │
│ ┌── FOCUS ──────────────┐ ┌── PROFILES ────────────┐                 │
│ │ Pomodoro 25/5/4        │ │ default performance    │                 │
│ │ Blocker:OFF Focus:OFF  │ │ Enter=manage           │                 │
│ │ Enter=open              │ │                        │                 │
│ └────────────────────────┘ └────────────────────────┘                 │
│ ┌── TOOLS ──────────────┐ ┌── STATUS ──────────────┐                 │
│ │ Notes Games Mount Wall │ │ CPU ████████░░ 62%     │                 │
│ │ Web:8765 AutoInstall   │ │ MEM █████████░ 6.2/7.5 │                 │
│ │ Enter=open              │ │ Enter=live view  R=ref │                 │
│ └────────────────────────┘ └────────────────────────┘                 │
├───────────────────────────────────────────────────────────────────────┤
│ Grace:undervolt(247s)  History:12  Boot:OK(1)                        │
└───────────────────────────────────────────────────────────────────────┘
```

**Các box:**

| # | Box | Chức năng | Enter để |
|---|-----|-----------|----------|
| 1 | **SYSTEM** | CPU, Super Mode, Eco, Undervolt, Thermal | Mở menu → edit form |
| 2 | **SERVICES** | Docker, KVM, Ollama, Maint, Rotate, Touch | Checklist toggle |
| 3 | **FOCUS** | Pomodoro, Website Blocker | Menu Pomodoro/Blocker |
| 4 | **PROFILES** | Save/Load config profiles | Menu chọn profile |
| 5 | **TOOLS** | Notes, Games, Mount, Wallpaper, Web, AutoInstall | Menu tool |
| 6 | **STATUS** | Real-time CPU/MEM bars, Eco, Super | Live full-screen view |

### Mouse Drag-and-Drop

Kéo thả box bằng chuột — click + giữ trên **title bar** (dòng ┌── TÊN BOX ─) và kéo:

1. **Click** giữ title bar → bắt đầu kéo
2. **Di chuột** → box di chuyển theo
3. **Thả chuột** → vị trí được lưu tự động

Vị trí box được ghi vào `~/.config/calarch/layout.conf` và khôi phục lần sau.

### Keyboard Shortcuts

| Phím | Hành động |
|------|-----------|
| `1`-`6` | Ẩn/hiện box tương ứng |
| `P` | Mở palette picker (đổi màu) |
| `.` | Mở quick menu (Grace, History, Undo, Help) |
| `R` | Refresh toàn bộ màn hình |
| `Q` | Thoát (có confirm) |

### Palette — đổi màu giao diện

Bấm `P` để mở palette picker:

| Preset | Tone |
|--------|------|
| **Cyan** (default) | Xanh cyan chuyên nghiệp |
| **Matrix** | Xanh lá hacker |
| **Royal** | Tím + vàng |
| **Amber** | Cam retro terminal |
| **Mono** | Trắng đen tối giản |
| **Custom** | Tự nhập mã ANSI từng màu |

Màu sắc được lưu và khôi phục lần sau.

### System Settings — chỉnh tham số

Enter trên box **SYSTEM (1)** → chọn mục:

| Mục | Fields | Ghi chú |
|-----|--------|---------|
| CPU Affinity | Active cores, bg cores, sched policy, priority, ionice | Form 6 field |
| Super Mode | Cool/Hot threshold, debounce, governor | Form 6 field |
| Undervolt | CPU/GPU/Cache (mV, -150 đến 0) | Grace 5 phút |
| Eco / Charge | Charge limit % (0-100) | Form 1 field |
| Thermal | Max cstate, kernel params | Form 2 field |
| Display | Scale, resolution, refresh | Form 3 field |

**Cách chỉnh:**
1. Một **form dialog** hiện ra với tất cả field — sửa giá trị, Tab chuyển field
2. Enter để lưu (validate tự động)
3. Nếu critical (undervolt) → grace period 5 phút bắt đầu
4. Vào `.` menu → **Grace** để xác nhận giữ thay đổi

## Config Center — `calarch.conf`

Mọi tham số tập trung tại 1 file duy nhất ở thư mục gốc:

```bash
nano ~/calarch/calarch.conf
```

File có comment đầy đủ, dễ hiểu. Thay đổi được áp dụng qua `core.sh`:

```bash
# Xem giá trị hiện tại
bash lib/core.sh list

# Thay đổi 1 giá trị (có validate + safety)
bash lib/core.sh set UNDERVOLT_CPU -80

# Undo thay đổi cuối
bash lib/core.sh undo

# Xem lịch sử
bash lib/core.sh log 10
```

## Web Dashboard

Mở web dashboard trên trình duyệt (kể cả điện thoại trong cùng LAN):

```bash
bash lib/web.sh &
```

Truy cập: [http://localhost:8765](http://localhost:8765)

Hoặc từ dashboard TUI chọn **Tools → Web**.

## Drive Manager

Quản lý tất cả partition / volume trên hệ thống:

```bash
# Từ dashboard: chọn Tools → Drive Manager
# Hoặc chạy trực tiếp:
bash lib/mount.sh
```

### Chức năng

| Mục | Mô tả |
|-----|-------|
| **List partitions** | Hiển thị tất cả partition: device, label, size, fstype, mountpoint (màu xanh = mounted, vàng = unmounted) |
| **Mount** | Chọn partition → tự động mount vào `/mnt/<label>` với options phù hợp (NTFS → ntfs-3g, exfat → exfat-utils, ext4/btrfs → defaults) |
| **Unmount** | Unmount an toàn, hỗ trợ lazy unmount nếu device busy, hiển thị process đang giữ |
| **Browse** | Mở file manager tại mount point (thunar/nautilus/dolphin/xdg-open) |
| **Mount All** | Mount tất cả partition chưa mount (có confirm từng cái) |
| **Unmount All** | Unmount tất cả partition đã mount (có confirm từng cái) |
| **Info** | Xem chi tiết partition: UUID, label, kích thước, loại filesystem |

### Mount options tự động theo fstype

| FSType | Mount options |
|--------|-------------|
| NTFS / ntfs3 | `-t ntfs-3g -o uid=1000,gid=1000,umask=022,big_writes` |
| exFAT | `-t exfat -o uid=1000,gid=1000,umask=022` |
| vfat / FAT32 | `-t vfat -o uid=1000,gid=1000,umask=022` |
| ext4 / btrfs / xfs | `defaults` |

## Wallpaper Changer

Chọn và đổi wallpaper với preview thumbnail ngay trong terminal:

```bash
# Từ dashboard: chọn Tools → Wallpaper
# Hoặc chạy trực tiếp:
bash lib/wallpaper.sh
```

### Chức năng

| Mục | Mô tả |
|-----|-------|
| **List + Select** | Quét thư mục `~/Pictures/wallpapers/`, chọn ảnh → preview bằng chafa | Apply |
| **Preview (chafa)** | Render thumbnail ngay trong terminal — xem trước trước khi set (bấm A = Apply, R = Random) |
| **Random** | Chọn ngẫu nhiên 1 wallpaper từ thư viện |
| **Import custom** | Copy các file `pascal_*` (Rei Ayanami) vào thư mục wallpapers |
| **Change engine** | Chuyển giữa hyprpaper (default), swaybg, feh |
| **Open folder** | Mở thư mục wallpaper trong file manager |

### Wallpaper Engine

- **hyprpaper** (default) — Native Hyprland wallpaper daemon
- **swaybg** — Dùng cho Sway / Wayland
- **feh** — Dùng cho X11

Cấu hình trong `calarch.conf`:
```bash
WALLPAPER_DIR="$HOME/Pictures/wallpapers"
WALLPAPER_ENGINE="hyprpaper"
```

### Custom Wallpaper (Rei Ayanami)

Đặt file `pascal_wallpaper_win.jpg`, `pascal_phone.png`, `pascal_psp.png`, `arch_linux_wallpaper.png` trong thư mục gốc `calarch/`, sau đó dùng **Import custom** trong menu Wallpaper để copy vào thư mục wallpapers.

## Profiles

Lưu cấu hình hiện tại thành profile để nạp lại sau:

```bash
# Từ dashboard: chọn 3 (Profiles)
#   Save → nhập tên → lưu
#   Load → chọn profile → nạp

# Hoặc từ CLI:
bash lib/core.sh profile save my-config
bash lib/core.sh profile load my-config
bash lib/core.sh profile list
bash lib/core.sh profile delete my-config
```

Các profile mặc định:
- **default**: Cân bằng hiệu năng/tiết kiệm
- **performance**: Undervolt -80mV, schedutil, eco OFF, max cstate=1
- **battery**: Eco 60%, powersave, affinity core 0, max cstate=8

## Safety Engine

### Grace Period
Khi thay đổi các tham số critical (undervolt, governor, cstate):
1. Dashboard hiển thị countdown: `⏳ Grace: undervolt còn 4:32`
2. Bạn có **5 phút** để xác nhận (menu **C** trong dashboard)
3. Nếu hết giờ → tự động revert về giá trị cũ
4. Cũng có thể confirm từ CLI: `bash lib/core.sh grace_confirm UNDERVOLT_CPU`

### Boot Guard
- Mỗi lần boot, calarch đếm số lần boot
- Nếu boot fail >2 lần (không vào được dashboard) → tự động rollback config đến bản snapshot cuối
- Dashboard hiển thị trạng thái: `🔒 Boot guard: OK (3 boots ổn định)`

### Undo / History
```bash
# Hoàn tác thay đổi cuối
bash lib/core.sh undo

# Xem 10 thay đổi gần nhất
bash lib/core.sh log 10
```

## Super Mode Daemon

Monitor CPU load mỗi 2 giây:
- **COOL** (load dưới ngưỡng đủ thời gian): governor tiết kiệm, eco ON
- **HOT** (load trên ngưỡng hoặc có compiler): governor hiệu năng cao, eco OFF
- Ngưỡng COOL/HOT, debounce, governor có thể tùy chỉnh trong `calarch.conf`
- Compiler detection: gcc, rustc, cargo, make -j, npm run build, ninja...

### Settings Panel (3 submenus) — legacy

> **Chú ý**: Các chức năng này đã được tích hợp vào box **SYSTEM** và **SERVICES** trên dashboard mới.

**1) System**
| Toggle | ON → | OFF → |
|---|---|---|
| Super Mode Daemon | chạy daemon nền | kill daemon |
| CPU Affinity | start event-monitor | kill process |
| Eco Mode | sạc 80% | sạc 100% |
| Undervolt | apply từ config (có grace) | (cần reboot) |
| Auto-rotate | enable iio-sensor-proxy | disable |
| Touchpad | tapping + scroll | disable |

**2) Services**
| Toggle | ON → | OFF → |
|---|---|---|
| Docker | enable --now | disable --now |
| KVM/libvirtd | enable --now | disable --now |
| Ollama AI | enable --now | disable --now |
| Maintenance timer | enable timer CN 23:00 | disable |

**3) Apps**
| Toggle | ON → | OFF → |
|---|---|---|
| Obsidian Notes | cài + tạo vault ~/notes/ | (giữ nguyên) |
| Website Blocker | chặn từ config | restore hosts |
| Notes Manager | mở Obsidian vault manager | (giữ nguyên) |
| Focus Mode | Pomodoro + chặn web | unblock sites |

## An toàn (Installer & .run)

#### Installer (auto-install-arch.sh)
- **Backup/rollback**: mọi file hệ thống được backup trước khi sửa, tự động restore nếu lỗi
- **Pre-flight checks**: kiểm tra môi trường ISO, network, mount point trước khi làm gì
- **Idempotent**: chạy lại bao nhiêu lần cũng không hỏng
- **Cleanup trap**: SIGINT/SIGTERM → rollback sạch sẽ
- **fstab an toàn**: chỉ ghi nếu UUID detect được, không ghi trùng

#### .run file
- SHA256 checksum
- Persistent cache (không giải nén lại)
- Fallback: base64/openssl/python3/perl + tar/bsdtar + git clone
- Từ chối chạy root
- flock mutex, resume flags
