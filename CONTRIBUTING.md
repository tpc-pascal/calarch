# Hướng dẫn đóng góp (Contributing Guidelines)

Vui lòng đọc kỹ các hướng dẫn dưới đây trước khi bắt đầu đóng góp.

---

## 1. Thiết lập môi trường phát triển

```bash
git clone https://github.com/tpc-pascal/calarch.git
cd calarch
bash lib/tui.sh           # Kiểm tra gum có sẵn
bash lib/core.sh get KERNEL_PARAMS  # Đọc config
```

---

## 2. Quy trình gửi đóng góp (Git Workflow)

1. **Fork** dự án về tài khoản cá nhân.
2. **Tạo branch mới:**
   - Tính năng mới: `git checkout -b feat/ten-tinh-nang`
   - Sửa lỗi: `git checkout -b fix/ten-loi`
   - Tài liệu: `git checkout -b docs/ten-tai-lieu`
3. **Commit:** Một commit duy nhất cho một feature. Title format:
   ```
   feat: v<version> - <mô tả>
   ```
   Ví dụ: `feat: v1.0.6 - fix boot guard, CPU freq NaN, docs rewrite`
4. **Push & PR:** Đẩy branch lên GitHub và tạo Pull Request vào nhánh `dev`.

---

## 3. Quy chuẩn viết mã (Coding Standards)

- **Bash 5.0+** — Luôn đặt `set -euo pipefail` ở đầu script
- **Snake_case** — Function name: `snake_case`, biến: `local_name`, hằng: `UPPER_CASE`
- **`has()`** — Dùng `has() { command -v "$1" &>/dev/null; }` để kiểm tra lệnh
- **Không comment giải thích code** — Trừ khi thật sự cần thiết
- **Check return code** — Luôn kiểm tra exit code trước khi in success message
- **Idempotent** — Mọi script có thể chạy lại nhiều lần mà không gây lỗi

---

## 4. Cấu trúc thư mục

```
calarch/
├── bootstrap.sh                 # Bootstrap installer — archinstall TUI + calarch post-install
├── start.sh                     # Unified TUI — entry point duy nhất
├── make.sh                      # Builder
├── lib/                         # Thư viện chính
│   ├── tui.sh                   # TUI engine (gum)
│   ├── core.sh                  # Config I/O + Safety + Profile
│   ├── config-load.sh           # Config loader
│   ├── post-install.sh          # Post-install setup
│   ├── godmode-setup.sh         # God-Mode guided setup (8 bước, idempotent)
│   ├── system.sh                # System monitor
│   ├── settings.sh              # Settings panel
│   ├── mount.sh                 # Drive manager
│   ├── wallpaper.sh             # Wallpaper changer
│   ├── focus.sh                 # Focus mode
│   ├── notes.sh                 # Notes manager
│   ├── games.sh                 # Games launcher
│   ├── refind-sync.sh           # rEFInd ESP kernel sync
│   ├── anime.sh                 # Anime player (Nyaa + web-torrent)
│   ├── yt-video.sh              # YouTube player (yt-dlp + mpv)
│   ├── spotify.sh               # Spotify + Spicetify
│   ├── neovim.sh                # Neovim + LazyVim
│   ├── emacs.sh                 # Emacs + Org-mode
│   ├── firefox.sh               # Firefox config
│   ├── launcher.sh              # Rofi launcher
│   ├── safety.sh                # Safety engine
│   ├── profiles.sh              # Profile manager
│   ├── dashboard.sh             # Legacy dashboard
│   └── ... (các script khác)
├── tests/                       # Bats test suite (bash tests/run.sh)
├── calarch.conf                 # Config trung tâm
├── .github/workflows/
│   ├── release.yml
│   └── deploy-pages.yml
```

---

## 5. Kiểm thử (Testing)

Trước khi gửi Pull Request, vui lòng đảm bảo:

- Code chạy được trên máy cá nhân không lỗi.
- Không làm ảnh hưởng đến các tính năng cũ.
- Các toggle trong settings panel hoạt động đúng.
- `bash lib/tui.sh` — gum TUI còn hoạt động.
- **Chạy test suite** (bắt buộc):
  ```bash
  bash tests/run.sh     # syntax check toàn bộ *.sh + Bats unit tests
  ```
  Yêu cầu `bats` (`npm install -g bats`). Thêm test mới vào `tests/test_*.bats`
  cho mọi logic mới (xem `test_post_install.bats`, `test_refind_sync.bats`...).

---

## 6. Build

```bash
VERSION=<version> bash make.sh
# Output: calarch-v<version>.run
```

### Bump version (khi phát hành bản mới)

Sửa đồng bộ **3 chỗ**:

- `bootstrap.sh` → `VERSION="<version>"` (dòng ~15)
- `start.sh` → `echo "calarch <version>"` (dòng ~103)
- `GUIDE.md` → dòng tagline "Phiên bản mới nhất: v<version>" (dòng 3)

Ví dụ: v1.0.13 → v1.0.14 sửa cả `bootstrap.sh:15`, `start.sh:103`, `GUIDE.md:3`.

---

## Liên hệ

- [Mở một Issue](https://github.com/tpc-pascal/calarch/issues)
- [Thảo luận (Discussions)](https://github.com/tpc-pascal/calarch/discussions)
