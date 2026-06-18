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
- **Settings Panel** — 3 submenus: System (6), Services (4), Apps (4)
- **Games** — minetest, assaultcube, megaglest (Arch official repo)

---

## Cấu trúc

```
calarch/
├── start.sh                     # TUI Control Center (1=Settings, 2=Games, 3=Exit)
├── make.sh                      # Builder → calarch-v*.run
├── lib/
│   ├── tui.sh                   # TUI abstraction (dialog / whiptail)
│   ├── settings.sh              # Settings panel — 14 toggles
│   ├── super-mode.sh            # Daemon HOT/COOL tự động
│   ├── install.sh               # God-Mode setup engine
│   ├── auto-install-arch.sh     # Auto Arch Linux installer (menu + archinstall TUI)
│   ├── focus.sh                 # Pomodoro timer + website blocker
│   ├── notes.sh                 # Obsidian vault manager
│   ├── games.sh                 # minetest, assaultcube, megaglest
│   ├── common.sh, config.sh     # Shared libraries
│   ├── phase0-detect.sh … phase4-finalize.sh  # 5 install phases
│   ├── hyprland-event-monitor.sh, cf-xz6-rotator.sh, cfxz6-stylus-calibrate.sh
│   ├── godmode-cleanup.sh, godmode-recovery.sh
│   ├── godmode-clean.{service,timer}
│   └── ollama-override.conf
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
| TUI | dialog (preferred) / whiptail (fallback) — via `lib/tui.sh` |
| CPU | taskset, chrt, ananicy-cpp |
| Thermal | thermald, TLP, intel-undervolt |
| Storage | Btrfs (zstd:3, noatime), ZRAM 8GB (zstd) |
| AI | Ollama (qwen2.5-coder) + OpenCode |
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
bash start.sh                       # 1=Settings, 2=Games, 3=Exit

# Hoặc chạy auto-installer trực tiếp
bash lib/auto-install-arch.sh       # menu: Full Install / Post-Install / Advanced
```

### Menu Settings (3 submenus)

**1) System** — 6 toggles
| Toggle | Mô tả |
|---|---|
| Super Mode Daemon | auto COOL/HOT theo CPU load |
| CPU Affinity | window → core 0,1; bg → 2,3 |
| Eco Mode | 80% charge limit |
| Undervolt | -50/-20/-50mV |
| Auto-rotate | screen rotation sensor |
| Touchpad | tapping + scroll |

**2) Services** — 4 toggles
| Toggle | Mô tả |
|---|---|
| Docker | container runtime |
| KVM/libvirtd | virtual machine host |
| Ollama AI | local LLM + OpenCode |
| Maintenance timer | dọn dẹp CN 23:00 |

**3) Apps** — 4 toggles
| Toggle | Mô tả |
|---|---|
| Obsidian Notes | cài + tạo vault ~/notes/ |
| Website Blocker | chặn FB, Reddit, YouTube |
| Notes Manager | Obsidian vault manager |
| Focus Mode | Pomodoro timer + site blocker |

---

## Tác giả

**tpc-pascal** — [GitHub](https://github.com/tpc-pascal)

## License

MIT — xem [LICENSE](./LICENSE).
