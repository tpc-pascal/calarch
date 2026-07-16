# Legacy Installer

> **Khuyen dung:** Su dung `lib/post-install.sh` + `archinstall` thay the.
> Xem `GUIDE.md` hoac `README.md` de biet huong dan chi tiet.

Thu muc nay chua phien ban cu cua calarch installer (auto-install-arch.sh + 5-phase installer). Duoc giu lai de tham khao cho nhung ai muon tu dong hoa toan bo qua trinh cai dat.

## Cach dung (khong khuyen nghi)

```bash
cd installer
sudo bash auto-install-arch.sh --advanced
```

## Noi dung

| File | Mo ta |
|------|-------|
| `auto-install-arch.sh` | Entry point: archinstall TUI + post-install |
| `phase0-detect.sh` | Phat hien moi truong |
| `phase1-disk.sh` | Phan vung dinh dang |
| `phase2-pacstrap.sh` | Cai goi co ban |
| `phase3-chroot.sh` | Cau hinh trong chroot |
| `phase4-finalize.sh` | Hoan tat cai dat |
| `common.sh` | Ham dung chung |
| `config.sh` | Gia tri mac dinh |
