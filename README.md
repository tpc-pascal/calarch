# calarch

<p align="center">
  <img src="assets/logo.svg" alt="calarch logo" width="200">
</p>

> Thiết lập Arch Linux toàn diện cho Panasonic CF-XZ6: dual boot với Windows,
> Dynamic CPU Affinity, Thermal tuning, Btrfs + ZRAM, Super Mode daemon.

------------------------------------------------------------------------

## Tính năng

- **Unified TUI** — `bash start.sh` là entry point duy nhất cho tất cả:
  system monitor, settings, drive manager, wallpaper, focus mode, notes, games,
  rEFInd sync, profiles
- **Newbie-friendly Bootstrap** — Một lệnh cài đặt, auto WiFi connect, cheat-sheet
  archinstall, tự thích nghi bootloader/filesystem (dynamic rootflags)
- **Post-Install Setup** — Chạy tự động ở lần boot đầu tiên (live mode),
  không cần ISO chroot
- **Super Mode Daemon** — Tự động chuyển COOL (powersave) ↔ HOT (schedutil)
  theo CPU load
- **Dynamic CPU Affinity** — Active window → Core 0,1; Background → Core 2,3
- **Thermal God-Mode** — Undervolt -50/-20/-50mV, thermald + TLP
- **Btrfs + ZRAM 8GB** — Snapper snapshots, scrub timer, fstrim weekly,
  compress zstd:3
- **Bulletproof Safety** — Backup/rollback, grace period, boot guard,
  undo history
- **Config Center** — Mọi tham số tập trung tại một file `calarch.conf`
- **rEFInd ESP Kernel Sync** — Tự động copy kernel + initramfs ra ESP (FAT32),
  có pacman hook

------------------------------------------------------------------------

## Cài đặt nhanh

Boot Arch USB (UEFI) rồi chạy một lệnh:

```bash
bash <(curl -s https://tpc-pascal.github.io/calarch/install)
```

Script tự kết nối mạng (hỏi SSID/password nếu chưa có) → archinstall TUI (bạn tự đặt
disk, hostname, user, bootloader) → chọn Exit → calarch post-install tự động.

> **Fallback:** `bash <(curl -s https://raw.githubusercontent.com/tpc-pascal/calarch/main/bootstrap.sh)`
>
> **Verify checksum:** `curl -sO https://tpc-pascal.github.io/calarch/install && echo "$(curl -s https://tpc-pascal.github.io/calarch/install.sha256)  install" | sha256sum -c - && bash install`

-----------------------------------------------------------------------

## Cấu trúc thư mục

```
calarch/
├── calarch.conf                 Config trung tâm
├── bootstrap.sh                 Bootstrap installer → archinstall TUI → post-install
├── start.sh                     Unified TUI — entry point duy nhất
├── make.sh                      Builder → calarch-v*.run
├── profiles/                    Preset configs
├── web/                         Web dashboard (Chart.js)
├── lib/
│   ├── tui.sh                   TUI engine (gum)
│   ├── post-install.sh          Post-install setup
│   ├── system.sh                System monitor
│   ├── settings.sh              Settings panel
│   ├── mount.sh                 Drive manager
│   ├── wallpaper.sh             Wallpaper changer
│   ├── focus.sh                 Pomodoro + blocker
│   ├── notes.sh                 Notes manager
│   ├── games.sh                 Games launcher
│   ├── refind-sync.sh           rEFInd ESP kernel sync
│   ├── profiles.sh              Profile manager
│   ├── safety.sh                Safety engine
│   ├── super-mode.sh            Super Mode daemon
│   ├── core.sh                  Config I/O + Safety + Profile
│   ├── dashboard.sh             Legacy dashboard
│   └── ... (các script khác)
├── assets/logo.svg
├── .github/workflows/
│   ├── release.yml
│   └── deploy-pages.yml
├── CONTRIBUTING.md
├── CREDITS.md
├── GUIDE.md
├── README.md
└── LICENSE
```

------------------------------------------------------------------------

## Tech Stack

| Layer   | Công nghệ                                          |
|---------|-----------------------------------------------------|
| OS      | Arch Linux (linux-zen kernel)                       |
| Shell   | Bash 5.0+, `set -euo pipefail`                      |
| Desktop | Hyprland (Wayland) via JaKooLit                     |
| TUI     | gum (charmbracelet) — modern terminal UI            |
| Web     | Python + Chart.js                                   |
| CPU     | taskset, chrt, ananicy-cpp                          |
| Thermal | thermald, TLP, intel-undervolt                      |
| Storage | Btrfs (zstd:3, noatime), ZRAM 8GB (zstd)            |
| AI      | Ollama (qwen2.5-coder) + OpenCode                   |
| Safety  | Grace period, boot guard, undo, history             |

------------------------------------------------------------------------

## Tác giả

**tpc-pascal** — [GitHub](https://github.com/tpc-pascal)

## License

MIT
