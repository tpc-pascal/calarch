# calarch

God-Mode cho Panasonic CF-XZ6 — Arch Linux, Hyprland, CPU Affinity

<p align="center">
  <img src="assets/logo.svg" alt="calarch logo" width="200">
</p>

> Thiet lap Arch Linux toan dien cho CF-XZ6: dual boot voi Windows, Dynamic CPU Affinity, Thermal tuning, Btrfs + ZRAM, Super Mode daemon.

---

## Tinh nang

- **Unified TUI** — 1 entry point duy nhat (`bash start.sh`) cho tat ca: system monitor, settings, drive, wallpaper, focus, notes, games, refind-sync, profiles
- **Post-Install Setup** — chay 1 lan sau khi cai Arch: patch fstab, kernel params, refind_linux.conf, refind-sync, clone calarch, enable services
- **Bulletproof Safety** — backup/rollback, grace period, boot guard, undo history
- **Super Mode Daemon** — tu dong chuyen COOL (powersave) HOT (schedutil) theo CPU load
- **Dynamic CPU Affinity** — Active window Core 0,1; Background Core 2,3
- **Thermal God-Mode** — Undervolt -50/-20/-50mV, thermald + TLP
- **Btrfs + ZRAM 8GB** — Snapper snapshots, scrub timer, fstrim weekly, compress zstd:3
- **Live Dashboard** — Real-time TUI + Web (localhost:8765)
- **Drag-and-drop TUI** — 7 box layout, keo tha bang chuot, an/hien box tuy y
- **Color Palette** — 5 preset mau (Cyan, Matrix, Royal, Amber, Mono) + custom
- **Config Center** — Moi tham so tap trung tai 1 file `calarch.conf`
- **Profile Manager** — Luu/nap cau hinh (default, performance, battery)
- **Safety Engine** — Grace period (auto-revert 5p), boot guard (rollback neu boot fail), undo history
- **Drive Manager** — Liet ke partition, mount/unmount, browse file manager
- **Wallpaper Changer** — Chafa preview thumbnail, set wallpaper (hyprpaper/swaybg/feh)
- **rEFInd ESP Kernel Sync** — Tu dong copy kernel + initramfs ra ESP (FAT32) de rEFInd co the doc duoc (khac phuc loi rEFInd khong ho tro Btrfs nen zstd). Co pacman hook tu dong sync sau moi `pacman -Syu`

---

## Cau truc

```
calarch/
├── calarch.conf                 # Config trung tam
├── start.sh                     # UNIFIED TUI — entry point duy nhat
├── make.sh                      # Builder calarch-v*.run
├── profiles/                    # Preset configs
├── web/                         # Web dashboard (Chart.js)
├── lib/
│   ├── tui.sh                   # Widget library (dialog)
│   ├── tui-core.sh              # TUI engine (ANSI, palette)
│   ├── post-install.sh          # Post-install setup (chay 1 lan)
│   ├── system.sh                # System monitor
│   ├── settings.sh              # Settings panel
│   ├── mount.sh                 # Drive Manager
│   ├── wallpaper.sh             # Wallpaper changer
│   ├── focus.sh                 # Pomodoro + blocker
│   ├── notes.sh                 # Obsidian vault manager
│   ├── games.sh                 # Game launcher
│   ├── refind-sync.sh           # rEFInd ESP kernel sync
│   ├── profiles.sh              # Profile manager
│   ├── safety.sh                # Safety engine
│   ├── super-mode.sh            # Super Mode daemon
│   ├── core.sh                  # Config I/O + Safety + Profile
│   ├── dashboard.sh             # Legacy dashboard
│   ├── common.sh                # Shared libs
│   └── config.sh                # Installer defaults
├── installer/                   # Legacy installer (thay khao)
│   ├── auto-install-arch.sh
│   ├── phase0-detect.sh
│   ├── phase1-disk.sh
│   ├── phase2-pacstrap.sh
│   ├── phase3-chroot.sh
│   ├── phase4-finalize.sh
│   ├── common.sh
│   └── config.sh
├── assets/logo.svg
├── .github/workflows/release.yml
├── CONTRIBUTING.md, CREDITS.md, GUIDE.md, README.md
└── LICENSE
```

---

## Cach dung

### Cai dat tu Arch ISO (khuyen nghi)

1. **Boot Arch USB** kiem tra internet
2. **Chay archinstall** (tu partition, chon Btrfs, bootloader tuy y)
   ```bash
   archinstall
   ```
   Sau khi archinstall xong chon **Exit** (KHONG reboot)
3. **Kiem tra mount point**
   ```bash
   ls /mnt/etc
   ```
   Neu khong co tien hanh mount thu cong
4. **Clone calarch chay post-install**
   ```bash
   pacman -Sy git
   git clone https://github.com/tpc-pascal/calarch.git
   cd calarch
   sudo bash lib/post-install.sh post-install /mnt
   ```
5. **Reboot**
   ```bash
   umount -R /mnt
   reboot
   ```
6. **Sau reboot** login chay `cd ~/calarch && bash start.sh`

### Cai dat — Subvolume tuy chinh

Neu ban tu chia subvolume (vd @, @home, @snapshots, @cache, @log, @pkg):

```bash
# Mount dung thu tu
mount -o subvol=@ /dev/nvme0n1p2 /mnt
mkdir -p /mnt/{home,.snapshots,var/cache/pacman/pkg,var/log,boot}
mount -o subvol=@home /dev/nvme0n1p2 /mnt/home
mount -o subvol=@snapshots /dev/nvme0n1p2 /mnt/.snapshots
mount -o subvol=@cache /dev/nvme0n1p2 /mnt/var/cache
mount -o subvol=@log /dev/nvme0n1p2 /mnt/var/log
mount -o subvol=@pkg /dev/nvme0n1p2 /mnt/var/cache/pacman/pkg
mount /dev/nvme0n1p1 /mnt/boot     # ESP

# Roi chay post-install
sudo bash lib/post-install.sh post-install /mnt
```

### Su dung hang ngay

```bash
cd ~/calarch
bash start.sh                     # Unified TUI menu
```

Menu chinh:
| Option | Chuc nang |
|--------|-----------|
| 1 | System Monitor |
| 2 | Settings Panel |
| 3 | Drive Manager |
| 4 | Wallpaper Changer |
| 5 | Focus Mode |
| 6 | Notes |
| 7 | Games |
| 8 | rEFInd Sync |
| 9 | Profiles |
| P | Post-Install Setup (1 lan) |
| S | Safety Engine |

### rEFInd ESP Kernel Sync

Neu rEFInd khong thay Arch trong menu boot:

```bash
bash lib/refind-sync.sh           # Sync kernel ra ESP + entry + hook
bash lib/refind-sync.sh --check   # Kiem tra trang thai
```

### Fix PARTUUID (neu can)

```bash
bash start.sh --fix-partuuid /mnt <PARTUUID_THAT>
```

---

## Config Center calarch.conf

```bash
AFFINITY_ACTIVE_CORES="0,1"
AFFINITY_BG_CORES="2,3"
SUPER_COOL_THRESHOLD=30
SUPER_HOT_THRESHOLD=70
UNDERVOLT_CPU=-50
ECO_CHARGE_LIMIT=80
REFIND_SYNC_ESP="true"
```

---

## Tech Stack

| Layer | Cong nghe |
|-------|-----------|
| OS | Arch Linux (linux-zen kernel) |
| Shell | Bash 5.0+, set -euo pipefail |
| Desktop | Hyprland (Wayland) via JaKooLit |
| TUI | dialog + ANSI box engine |
| Web | Python + Chart.js |
| CPU | taskset, chrt, ananicy-cpp |
| Thermal | thermald, TLP, intel-undervolt |
| Storage | Btrfs (zstd:3, noatime), ZRAM 8GB (zstd) |
| AI | Ollama (qwen2.5-coder) + OpenCode |
| Safety | Grace period, boot guard, undo |
| rEFInd Sync | Pacman hook PostTransaction |

---

## Tac gia

**tpc-pascal** GitHub

## License

MIT
