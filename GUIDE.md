## Hướng dẫn sử dụng

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

Nếu muốn cài lại hoặc mở Settings Panel:

```bash
cd ~/calarch
bash start.sh        # TUI Control Center
```

### Menu chính (start.sh)

```
1) Settings   — 3 submenus (System / Services / Apps)
2) Games      — minetest, assaultcube, megaglest
3) Exit
```

### Settings Panel (3 submenus)

**1) System**
| Toggle | ON → | OFF → |
|---|---|---|
| Super Mode Daemon | chạy daemon nền | kill daemon |
| CPU Affinity | start event-monitor | kill process |
| Eco Mode | sạc 80% | sạc 100% |
| Undervolt | apply -50/-20/-50mV | (cần reboot) |
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
| Website Blocker | chặn FB/Reddit/YouTube | restore hosts |
| Notes Manager | mở Obsidian vault manager | (giữ nguyên) |
| Focus Mode | Pomodoro 25/5/4 + chặn web | unblock sites |

### Super Mode Daemon

Monitor CPU load mỗi 2 giây:
- **COOL** (load <30% đủ 10s): powersave governor, eco 80%
- **HOT** (load >70% đủ 5s hoặc có compiler): schedutil governor, eco 100%
- Compiler detection: gcc, rustc, cargo, make -j, npm run build, ninja...

### An toàn

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
