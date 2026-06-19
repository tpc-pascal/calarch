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

### Màn hình chính

```
┌──────── CALARCH DASHBOARD ────── real-time ────────┐
│  CPU [━━━━━━━━━━━━━━━━━━░░░] 62%  52°C  2.81GHz    │
│  MEM [━━━━━━━━━━━━━━━━━━━━━━] 6.2/7.5 GB           │
│  Eco: ON 80% | Super: COOL | Affinity: ACTIVE      │
├─────────────────────────────────────────────────────┤
│  1 System     CPU | Eco | Undervolt | Thermal       │
│  2 Services   Docker | KVM | Ollama | Maintenance   │
│  3 Profiles   Save | Load | Delete                  │
│  4 Focus      Pomodoro | Website Blocker            │
│  5 Web        http://localhost:8765                 │
│  6 Games      minetest | assaultcube | megaglest    │
│  7 History    Xem / Undo thay đổi                   │
│  0 Exit                                             │
├─────────────────────────────────────────────────────┤
│  ⏳ Grace: undervolt còn 3:42 — Vào menu C confirm  │
│  🔒 Boot guard: OK (3 boots ổn định)               │
└─────────────────────────────────────────────────────┘
```

Dashboard tự động refresh mỗi lần bạn quay lại (sau khi chọn menu).

### System Settings — chỉnh tham số

Chọn **1 (System)** → các tùy chọn:

| Mục | Tham số có thể chỉnh |
|---|---|
| CPU Affinity | Core cho active window, core cho background, scheduling policy, priority |
| Super Mode | Cool/Hot threshold (%), debounce (giây), governor (powersave/schedutil/...) |
| Undervolt | CPU/GPU/Cache (mV, từ -150 đến 0) — **có grace period 5 phút** |
| Eco Mode | Charge limit % (0-100) |
| Thermal | Max cstate (1-10) |
| Pomodoro | Work time, break time, cycles |
| Blocker | Danh sách site cần chặn (comma-separated) |

**Cách chỉnh:**
1. Chọn mục → nhập giá trị mới (Enter để giữ nguyên)
2. Giá trị được validate tự động (range check)
3. Nếu là critical (undervolt) → grace period 5 phút bắt đầu
4. Vào menu **C (Confirm Grace)** để xác nhận giữ thay đổi

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

Hoặc từ dashboard TUI chọn **5 (Web)**.

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
