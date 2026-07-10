# calarch
God-Mode cho Panasonic CF-XZ6 — Arch Linux, Hyprland, CPU Affinity

<p align="center">
  <img src="assets/logo.svg" alt="calarch logo" width="200">
</p>

> Thiết lập Arch Linux toàn diện cho CF-XZ6: dual boot với Windows, Dynamic CPU Affinity, Thermal tuning, Btrfs + ZRAM, Super Mode daemon.

**Lý do ra đời:** Panasonic CF-XZ6 là chiếc laptop mỏng nhẹ hiếm hoi có tỷ lệ 3:2 (2160x1440) lý tưởng cho lập trình viên, nhưng bị giới hạn bởi TDP 15W và cooling mỏng. Dự án này ép từng MHz, từng luồng CPU, và từng watt nhiệt — biến CF-XZ6 thành workstation di động với dynamic CPU affinity, undervolt, ZRAM, và tự động hóa toàn bộ.

---

## Tính năng

- **Auto Install** — Từ Arch ISO → hệ thống hoàn chỉnh (archinstall TUI + calarch post-install, hoặc 5-phase legacy)
- **Bulletproof Safety** — Mọi thay đổi đều được backup/rollback, kiểm tra đầu vào, idempotent (chạy lại an toàn)
- **Super Mode Daemon** — Tự động chuyển COOL (powersave + eco) ↔ HOT (schedutil + full turbo) theo CPU load + compiler process
- **Dynamic CPU Affinity** — Active window → Core 0,1; Background → Core 2,3
- **Thermal God-Mode** — Undervolt -50/-20/-50mV, GPU freq 300-750MHz, thermald + TLP
- **Btrfs + ZRAM 8GB** — Snapper snapshots, scrub timer, fstrim weekly, compress zstd:3
- **Live Dashboard** — Real-time TUI + Web (localhost:8765) hiển thị CPU temp/freq/load, Eco, Super Mode
- **Drag-and-drop TUI** — 7 box layout, kéo thả bằng chuột, ẩn/hiện box tùy ý
- **Color Palette** — 5 preset màu (Cyan, Matrix, Royal, Amber, Mono) + custom
- **Layout Save** — Vị trí box và màu sắc tự động lưu, khôi phục lần sau
- **Config Center** — Mọi tham số tập trung tại 1 file `calarch.conf`, dễ sửa, có validate + safety
- **Profile Manager** — Lưu/nạp cấu hình (default, performance, battery)
- **Safety Engine** — Grace period (auto-revert 5p), boot guard (rollback nếu boot fail), undo history
- **Settings Panel** — 3 submenus: System (6), Services (4), Apps (4)
- **Games** — minetest, assaultcube, megaglest (Arch official repo)
- **Drive Manager** — Liệt kê tất cả partition, mount/unmount với auto-detect fstype (NTFS, exfat, vfat, ext4…), browse file manager
- **Wallpaper Changer** — Chafa preview thumbnail, set wallpaper (hyprpaper/swaybg/feh), random, import custom ảnh

---

## Cấu trúc

```
calarch/
├── calarch.conf                 # ⭐ Config trung tâm — sửa tay thoải mái
├── start.sh                     # Thin wrapper → dashboard.sh
├── make.sh                      # Builder → calarch-v*.run
├── profiles/                    # Preset configs
│   ├── default.conf
│   ├── performance.conf
│   └── battery.conf
├── web/
│   └── index.html               # Web dashboard (Chart.js)
├── lib/
│   ├── core.sh                  # ⭐ Config I/O + Validate + Safety + Profile
│   ├── dashboard.sh             # ⭐ Live TUI dashboard (thay thế start.sh cũ)
│   ├── web.sh                   # Python HTTP server (localhost:8765)
│   ├── tui.sh                   # TUI widget library (dialog — form, tailbox, menu)
│   ├── settings.sh              # Settings panel — 14 toggles
│   ├── super-mode.sh            # Daemon HOT/COOL (đọc từ calarch.conf)
│   ├── hyprland-event-monitor.sh# CPU Affinity Engine (đọc từ calarch.conf)
│   ├── install.sh               # God-Mode setup engine
│   ├── auto-install-arch.sh     # Auto Arch Linux installer
│   ├── focus.sh                 # Pomodoro + blocker (đọc từ calarch.conf)
│   ├── notes.sh                 # Obsidian vault manager
│   ├── games.sh                 # minetest, assaultcube, megaglest
│   ├── mount.sh                 # Drive / Volume Manager
│   ├── wallpaper.sh             # Wallpaper changer + chafa preview
│   ├── anime.sh                 # Terminal anime player (Nyaa/YouTube)
│   ├── common.sh, config.sh     # Shared libraries (installer)
│   └── phase0-detect.sh … phase4-finalize.sh, cf-xz6-rotator.sh, ...
├── assets/logo.svg
├── .github/workflows/release.yml
├── CONTRIBUTING.md, CREDITS.md, GUIDE.md, README.md
└── LICENSE                      # MIT
```

---

## Tech Stack

| Layer | Công nghệ |
|---|---|
| OS | Arch Linux (linux-zen kernel) |
| Shell | Bash 5.0+, `set -euo pipefail` |
| Desktop | Hyprland (Wayland) via JaKooLit |
| TUI | dialog — ANSI box engine, mouse SGR drag-drop, palette |
| Web | Python HTTP server + Chart.js (localhost:8765) |
| CPU | taskset, chrt, ananicy-cpp |
| Thermal | thermald, TLP, intel-undervolt |
| Storage | Btrfs (zstd:3, noatime), ZRAM 8GB (zstd) |
| AI | Ollama (qwen2.5-coder) + OpenCode |
| Safety | Grace period auto-revert, boot guard, undo history, config validation |
| CI/CD | GitHub Actions → .run release |
| Device | Panasonic CF-XZ6 (Core i5-7300U, 8GB LPDDR3, HD620) |

---

## Cách dùng

```bash
# Từ GitHub Releases
bash calarch-v1.0.run               # auto-detect: ISO → menu, installed → setup

# Từ source
git clone https://github.com/tpc-pascal/calarch.git
cd calarch
bash start.sh                       # Live TUI Dashboard

# Cấu hình tập trung tại 1 file
nano calarch.conf                   # Sửa tay thoải mái, có comment

# Web dashboard (localhost:8765)
bash lib/web.sh &

# Auto-installer
bash lib/auto-install-arch.sh       # menu: Full Install / Post-Install / Advanced

# Drive Manager (mount/unmount)
bash lib/mount.sh                   # menu: list, mount, unmount, browse

# Wallpaper Changer (preview + set)
bash lib/wallpaper.sh               # menu: select, random, import, engine
```

### Live Dashboard

Chạy `bash start.sh` bạn sẽ thấy giao diện 6 box:

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

- **Kéo thả**: Click + kéo title bar box bằng chuột để di chuyển
- **Ẩn/hiện**: Bấm `1`-`7` để toggle box tương ứng
- **Palette**: Bấm `P` để đổi màu (Cyan, Matrix, Royal, Amber, Mono, Custom)
- **Quick menu**: Bấm `.` để mở menu nhanh (Grace, History, Undo, Help)
- **Refresh**: Bấm `R` để làm mới dữ liệu
- **Tương tác**: Enter trên box → mở dialog settings tương ứng

### Config Center — `calarch.conf`

Mọi tham số tập trung tại 1 file ở thư mục gốc, có comment đầy đủ:

```bash
# ~/calarch/calarch.conf
AFFINITY_ACTIVE_CORES="0,1"     # Core cho active window
AFFINITY_BG_CORES="2,3"         # Core cho background
SUPER_COOL_THRESHOLD=30         # % load để xuống COOL
SUPER_HOT_THRESHOLD=70          # % load để lên HOT
UNDERVOLT_CPU=-50               # CPU undervolt (mV)
ECO_CHARGE_LIMIT=80             # % pin khi sạc
POMODORO_WORK_MINUTES=25        # Pomodoro work time
BLOCKER_SITES="facebook.com,..."# Sites cần chặn
MOUNT_BASE="/mnt"                   # Thư mục mount
WALLPAPER_DIR="$HOME/Pictures/wallpapers" # Thư mục wallpaper
WALLPAPER_ENGINE="hyprpaper"        # Engine: hyprpaper, swaybg, feh
```

Thay đổi qua dashboard hoặc sửa tay — đều có validate + safety.

### Safety Engine

- **Grace period**: Thay đổi critical (undervolt, governor) có 5 phút để confirm, hết giờ auto-revert
- **Boot guard**: Nếu boot fail 2 lần liên tiếp → tự động rollback config
- **Undo**: `core.sh undo` — hoàn tác thay đổi cuối
- **Validate**: Mọi giá trị được kiểm tra range trước khi apply

---

## Customization

### Layout & Palette

Vị trí các box và màu sắc được lưu tại `~/.config/calarch/layout.conf`:

```ini
system=2,3,40,7,1
services=44,3,40,7,1
focus=2,11,40,6,1
profiles=44,11,40,6,1
tools=2,18,40,6,1
status=44,18,40,6,1
palette=cyan
```

Có thể xóa file này để reset về mặc định.

### Palette Presets

| Preset | Mô tả |
|--------|-------|
| **Cyan** (default) | Xanh cyan chuyên nghiệp |
| **Matrix** | Xanh lá trên nền đen |
| **Royal** | Tím + vàng |
| **Amber** | Cam retro |
| **Mono** | Trắng đen tối giản |
| **Custom** | Tự chọn từng mã ANSI |

---

## Tác giả

**tpc-pascal** — [GitHub](https://github.com/tpc-pascal)

## License

MIT — xem [LICENSE](./LICENSE).
