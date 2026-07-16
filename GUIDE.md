## Huong dan su dung

> Phien ban moi (v1.0.5): Unified TUI, post-install rieng, cau truc thu muc gon hon.

### Yeu cau

- Panasonic CF-XZ6 (hoac laptop x86_64 khac)
- 20GB+ free disk, USB 4GB+
- UEFI boot mode
- Arch ISO (tai tu [archlinux.org](https://archlinux.org/download/))

---

## Cai moi (tu Arch ISO)

### Luong 1 — Dung archinstall + post-install (khuyen nghi)

```bash
# 1. Boot Arch USB, kiem tra mang
ping archlinux.org

# 2. Chay archinstall
archinstall

# Cau hinh trong archinstall:
#   - Disk: tu partition (Btrfs khuyen dung)
#   - Bootloader: rEFInd / systemd-boot / GRUB
#   - User: tao user + password
#
# SAU KHI archinstall XONG -> chon "Exit" (KHONG reboot)

# 3. Kiem tra mount point
ls /mnt/etc

# 4. Tai calarch va chay post-install
pacman -Sy git
git clone --depth=1 https://github.com/tpc-pascal/calarch.git
cd calarch
sudo bash lib/post-install.sh post-install /mnt

# 5. Kiem tra PARTUUID
cat /mnt/boot/refind_linux.conf
# Neu thay "PLACEHOLDER_PARTUUID" -> fix:
#   blkid -s PARTUUID -o value /dev/nvme0n1p2
#   sudo bash lib/post-install.sh fix-partuuid /mnt <PARTUUID>

# 6. Reboot
umount -R /mnt
reboot
```

### Luong 2 — Subvolume tuy chinh (thu cong)

Neu ban tu chia Btrfs subvolume (vd @, @home, @snapshots, @cache, @log, @pkg):

```bash
# --- Dinh dang (chi 1 lan) ---
mkfs.fat -F32 /dev/nvme0n1p1      # ESP
mkfs.btrfs -f /dev/nvme0n1p2      # Root

# --- Tao subvolumes ---
mount /dev/nvme0n1p2 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@cache
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
umount /mnt

# --- Mount dung thu tu (QUAN TRONG) ---
mount -o compress=zstd:3,noatime,subvol=@ /dev/nvme0n1p2 /mnt
mkdir -p /mnt/{home,.snapshots,var/cache/pacman/pkg,var/log,boot}
mount -o compress=zstd:3,noatime,subvol=@home /dev/nvme0n1p2 /mnt/home
mount -o compress=zstd:3,noatime,subvol=@snapshots /dev/nvme0n1p2 /mnt/.snapshots
mount -o compress=zstd:3,noatime,subvol=@cache /dev/nvme0n1p2 /mnt/var/cache
mount -o compress=zstd:3,noatime,subvol=@log /dev/nvme0n1p2 /mnt/var/log
mount -o compress=zstd:3,noatime,subvol=@pkg /dev/nvme0n1p2 /mnt/var/cache/pacman/pkg
mount /dev/nvme0n1p1 /mnt/boot     # ESP

# --- Cai Arch Linux base ---
pacstrap /mnt base base-devel linux-zen linux-zen-headers linux-firmware \
  btrfs-progs intel-ucode git networkmanager vim sudo
genfstab -U /mnt >> /mnt/etc/fstab

# --- Chroot va cai bootloader + config ---
arch-chroot /mnt
# Cai bootloader (rEFInd / systemd-boot / GRUB)
# Config mkinitcpio, password, hostname, timezone
# Xem huong dan Arch Wiki: https://wiki.archlinux.org/

# Sau thoat khoi chroot -> chay post-install
sudo bash lib/post-install.sh post-install /mnt

# Reboot
umount -R /mnt
reboot
```

### Luong 3 — Legacy installer (danh cho nang cao)

```bash
# Chuyen den thu muc installer
cd calarch/installer
sudo bash auto-install-arch.sh --advanced
```

> **Luu y:** Legacy installer la phien ban cu (5-phase), giu lai de tham khao.
> Khuyen dung Luong 1 (archinstall + post-install) cho moi truong hop.

---

## Sau reboot lan dau

1. **Login** bang user da tao
2. **God-Mode setup** tu dong chay (neu dang nhap lan dau)
   - Cai Hyprland, thermal, ZRAM, CPU affinity, Super Mode daemon
3. Sau setup xong: `cd ~/calarch && bash start.sh`

---

## Unified TUI (start.sh)

Chay `bash start.sh` de mo menu chinh:

```
CALARCH CONTROL CENTER
  [1] System Monitor
  [2] Settings Panel
  [3] Drive Manager
  [4] Wallpaper Changer
  [5] Focus Mode
  [6] Notes
  [7] Games
  [8] rEFInd Sync
  [9] Profiles
  [P] Post-Install Setup (chay 1 lan)
  [S] Safety Engine
  [Q] Thoat
```

Moi option mo sub-menu tuong ung.

---

## Post-Install Setup

Chay 1 lan sau khi cai Arch Linux. Tu dong:

1. **Detect root device** (findmnt lsblk blkid)
2. **Patch fstab** (them compress=zstd:3,noatime cho Btrfs)
3. **Them kernel params** (nowatchdog, processor.max_cstate,...)
4. **Sinh refind_linux.conf** (PARTUUID tu dong detect)
5. **Sync kernel ra ESP** (neu REFIND_SYNC_ESP=true)
6. **Clone calarch vao home user**
7. **Enable NetworkManager**
8. **Cai first-boot marker** (God-Mode setup tu dong chay lan login dau)

```bash
# Tu ISO (mount san /mnt)
sudo bash lib/post-install.sh post-install /mnt

# Tu he thong da boot (truc tiep)
sudo bash lib/post-install.sh post-install /

# Fix PARTUUID (neu bi loi PLACEHOLDER)
sudo bash lib/post-install.sh fix-partuuid /mnt <PARTUUID>
```

---

## Refind Linux.conf

Cau hinh cho rEFInd auto-detection:

```bash
# Sinh lai (idempotent)
sudo bash lib/post-install.sh refind /mnt

# Kiem tra
cat /mnt/boot/refind_linux.conf
```

File sinh ra co dang:
```
"Boot with defaults"  "root=PARTUUID=xxxx rw rootflags=subvol=@ nowatchdog ..."
"Boot to single-user" "root=PARTUUID=xxxx rw rootflags=subvol=@ single ..."
"Boot with minimal"   "root=PARTUUID=xxxx rw rootflags=subvol=@ ..."
```

---

## rEFInd ESP Kernel Sync

Khi rEFInd khong thay Arch trong menu boot (do khong doc duoc Btrfs nen zstd).

### Kiem tra trang thai

```bash
bash lib/refind-sync.sh --check
```

### Dong bo kernel ra ESP

```bash
# Tu he thong da cai
sudo bash lib/refind-sync.sh

# Tu ISO (mount san /mnt)
sudo bash lib/refind-sync.sh --mnt /mnt

# Chi dinh ESP thu cong
sudo bash lib/refind-sync.sh --mnt /mnt --esp /dev/sdX1
```

### Cac truong hop dac biet

| Truong hop | Cach xu ly |
|------------|------------|
| `/boot` la ESP (FAT32) | Tu dong bo qua copy kernel, chi generate entry + hook |
| Nhieu ESP | Tu dong chon ESP co rEFInd hoac dang mount |
| rEFInd chua cai | Van copy kernel nhung skip entry |
| AMD CPU | Tu dong phat hien, copy amd-ucode |
| Nhieu kernels | Sync tat ca (linux, linux-zen, linux-lts, linux-hardened) |
| ESP sap day | Kiem tra dung luong truoc khi copy |
| FAT32 4GB limit | Kiem tra kich thuoc file initramfs |

### Pacman Hook

Sau khi chay `refind-sync.sh`, hook duoc cai tai:
- `/etc/pacman.d/hooks/calarch-sync-kernel.hook`
- Script: `/usr/local/bin/calarch-sync-kernel.sh`

Tu dong chay sau moi `pacman -Syu` cap nhat kernel.

---

## Config Center

Moi tham so tap trung tai 1 file `calarch.conf`:

| Key | Mo ta | Gia tri mac dinh |
|-----|-------|------------------|
| `AFFINITY_ACTIVE_CORES` | Core cho active window | 0,1 |
| `AFFINITY_BG_CORES` | Core cho background | 2,3 |
| `SUPER_COOL_THRESHOLD` | % load xuong COOL | 30 |
| `SUPER_HOT_THRESHOLD` | % load len HOT | 70 |
| `UNDERVOLT_CPU` | CPU undervolt (mV) | -50 |
| `UNDERVOLT_GPU` | GPU undervolt (mV) | -20 |
| `UNDERVOLT_CACHE` | Cache undervolt (mV) | -50 |
| `ECO_CHARGE_LIMIT` | Gioi han sac pin | 80 |
| `MAX_CSTATE` | C-State thap nhat | 4 |
| `REFIND_SYNC_ESP` | Tu dong sync kernel ra ESP | true |

Thay doi qua dashboard hoac sua tay deu co validate + safety.

---

## Safety Engine

### Grace Period
- Thay doi critical (undervolt, governor) co 5 phut confirm
- Het gio tu dong revert ve gia tri cu
- Confirm qua dashboard (menu C) hoac CLI: `bash lib/core.sh grace_confirm UNDERVOLT_CPU`

### Boot Guard
- Theo doi so lan boot
- Neu boot fail >2 lan lien tiep tu dong rollback config
- Kiem tra: `bash lib/core.sh boot_check`

### Undo / History
```bash
bash lib/core.sh undo            # Hoan tac thay doi cuoi
bash lib/core.sh log 10          # Xem lich su
```

---

## Profiles

```bash
# Qua TUI: start.sh -> Profiles
# Hoac CLI:
bash lib/core.sh profile save my-config
bash lib/core.sh profile load my-config
bash lib/core.sh profile list
bash lib/core.sh profile delete my-config
```

### Profiles mac dinh

| Profile | Mo ta |
|---------|-------|
| **default** | Can bang hieu nang/tiet kiem |
| **performance** | Undervolt -80mV, schedutil, eco OFF |
| **battery** | Eco 60%, powersave, affinity core 0 |

---

## Dashboard (start.sh -m first-boot)

Khi login lan dau, God-Mode setup tu dong chay:
1. Doi network (30 giay)
2. Chay `bash start.sh -m first-boot`
3. Cai Hyprland, thermal, ZRAM, CPU affinity, Super Mode daemon
4. Xoa flag `firstboot-pending`, tao `firstboot-done`

Co the chay lai thu cong:
```bash
bash start.sh -m first-boot
```

---

## Fix loi thuong gap

### PARTUUID bi trong hoac PLACEHOLDER

```bash
# Boot tu Arch ISO
mount -o subvol=@ /dev/nvme0n1p2 /mnt
blkid -s PARTUUID -o value /dev/nvme0n1p2
sudo bash calarch/lib/post-install.sh fix-partuuid /mnt <PARTUUID>
```

### rEFInd khong thay Arch

```bash
# Kiem tra
bash lib/refind-sync.sh --check

# Sync kernel ra ESP
sudo bash lib/refind-sync.sh
```

### Post-install bi loi

```bash
# Chay lai (idempotent)
sudo bash lib/post-install.sh post-install /mnt
```

### God-Mode setup khong chay

```bash
rm -f /var/lib/godmode/firstboot-done
touch /var/lib/godmode/firstboot-pending
# Login lai
```
