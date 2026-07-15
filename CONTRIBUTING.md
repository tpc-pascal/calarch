# Hướng dẫn Đóng góp (Contributing Guidelines)

Vui lòng đọc kỹ các hướng dẫn dưới đây trước khi bắt đầu đóng góp.

---

## 🛠 1. Cấu trúc dự án

```
calarch/
├── calarch.conf          # Config trung tâm — sửa tay thoải mái
├── start.sh              # Thin wrapper → dashboard.sh
├── make.sh               # Builder → .run release
├── profiles/             # Preset config snapshots
├── web/index.html        # Web dashboard (Chart.js)
└── lib/
    ├── core.sh           # ⭐ Config I/O + Validate + Safety + Profile
    ├── dashboard.sh      # Live TUI dashboard
    ├── web.sh            # Python HTTP server (localhost:8765)
    ├── tui.sh            # TUI abstraction (dialog/whiptail)
    ├── settings.sh       # Legacy settings panel
    ├── super-mode.sh     # Super Mode daemon
    ├── hyprland-event-monitor.sh  # CPU affinity engine
    ├── focus.sh, notes.sh, games.sh, mount.sh, wallpaper.sh
    ├── anime.sh, launcher.sh, firefox.sh, neovim.sh
    ├── install.sh, auto-install-arch.sh
    └── ...
```

## 🛠 2. Thiết lập môi trường phát triển (Setup)

```bash
git clone https://github.com/tpc-pascal/calarch.git
cd calarch
shellcheck calarch.conf start.sh make.sh lib/*.sh    # Lint
bash -n calarch.conf start.sh make.sh lib/*.sh       # Syntax
bash make.sh                                          # Build release
bash calarch-*.run check                              # Verify
```

---

### Kiến trúc chính

```
core.sh (config I/O + validate + safety)
   ├── super-mode.sh, hyprland-event-monitor.sh, focus.sh   (đọc từ config)
   ├── dashboard.sh, web.sh                                  (giao diện)
   └── settings.sh, start.sh                                 (wrapper)
```

**Luồng dữ liệu:**
1. User thay đổi tham số qua dashboard hoặc sửa `calarch.conf`
2. `core.sh` validate → snapshot → ghi → apply → grace
3. Scripts `super-mode.sh`, `hyprland-event-monitor.sh`, `mount.sh`, `wallpaper.sh` đọc từ `calarch.conf`

## 🌿 3. Quy trình gửi đóng góp (Git Workflow)

1. **Fork** dự án về tài khoản cá nhân của bạn.
2. **Tạo Branch mới:**
   - Tính năng mới: `git checkout -b feat/ten-tinh-nang`
   - Sửa lỗi: `git checkout -b fix/ten-loi`
   - Tài liệu: `git checkout -b docs/ten-tai-lieu`
3. **Commit:** Sử dụng tiếng Việt hoặc tiếng Anh, nhưng phải rõ nghĩa.
   - *Ví dụ:* `feat: thêm game launcher menu`
4. **Push & PR:** Đẩy branch lên GitHub và tạo **Pull Request**.

---

## 📝 4. Quy chuẩn viết mã (Coding Standards)

- **Nhất quán:** Tuân thủ các quy tắc đặt tên đã có sẵn: `snake_case` cho script, `UPPER_CASE` cho hằng số.
- **Comment:** Giải thích các logic phức tạp, comment bằng tiếng Việt.
- **An toàn:** Mọi lệnh sudo/system/package đều có `2>/dev/null; true` — không crash khi fail.
- **set -euo pipefail** ở đầu mọi script.

---

- **Config:** Thêm key mới phải cập nhật `SCHEMA[]` trong `lib/core.sh` và mặc định trong `calarch.conf`
- **Safety:** Mọi thay đổi hệ thống phải qua `core.sh set` (không bypass)

## 🧪 5. Kiểm thử (Testing)

Trước khi gửi Pull Request, vui lòng đảm bảo:

```bash
shellcheck calarch.conf start.sh make.sh lib/*.sh web/index.html 2>/dev/null || true
bash -n calarch.conf start.sh make.sh lib/*.sh
bash make.sh && bash calarch-*.run check
```

### Lưu ý cho contributor
- `lib/core.sh` là file quan trọng nhất — mọi thay đổi config đều qua đây
- `calarch.conf` là config trung tâm — thêm key mới phải:
  1. Thêm vào `calarch.conf` (có comment)
  2. Thêm validation rule trong `core.sh` SCHEMA
  3. Update mặc định trong các profile
  4. Cập nhật `README.md` và `GUIDE.md`

---

## 📧 6. Liên hệ

Nếu có bất kỳ thắc mắc nào:

- [Mở một Issue](https://github.com/tpc-pascal/calarch/issues) trên repo này.
- Gửi câu hỏi qua phần [Thảo luận (Discussions)](https://github.com/tpc-pascal/calarch/discussions) của dự án.
