# Hướng dẫn Đóng góp (Contributing Guidelines)

Vui lòng đọc kỹ các hướng dẫn dưới đây trước khi bắt đầu đóng góp.

---

## 🛠 1. Thiết lập môi trường phát triển (Setup)

```bash
git clone https://github.com/tpc-pascal/calarch.git
cd calarch
bash make.sh                          # Build calarch-v*.run
bash make.sh && bash calarch-*.run check  # Build + verify (lint, syntax)
```

---

## 🌿 2. Quy trình gửi đóng góp (Git Workflow)

1. **Fork** dự án về tài khoản cá nhân của bạn.
2. **Tạo Branch mới:**
   - Tính năng mới: `git checkout -b feat/ten-tinh-nang`
   - Sửa lỗi: `git checkout -b fix/ten-loi`
   - Tài liệu: `git checkout -b docs/ten-tai-lieu`
3. **Commit:** Sử dụng tiếng Việt hoặc tiếng Anh, nhưng phải rõ nghĩa.
   - *Ví dụ:* `feat: thêm game launcher menu`
4. **Push & PR:** Đẩy branch lên GitHub và tạo **Pull Request**.

---

## 📝 3. Quy chuẩn viết mã (Coding Standards)

- **Nhất quán:** Tuân thủ các quy tắc đặt tên đã có sẵn: `snake_case` cho script, `UPPER_CASE` cho hằng số.
- **Comment:** Giải thích các logic phức tạp, comment bằng tiếng Việt.
- **An toàn:** Mọi lệnh sudo/system/package đều có `2>/dev/null; true` — không crash khi fail.
- **set -euo pipefail** ở đầu mọi script.

---

## 🧪 4. Kiểm thử (Testing)

Trước khi gửi Pull Request, vui lòng đảm bảo:

```bash
shellcheck make.sh lib/*.sh start.sh              # Lint
bash -n make.sh lib/*.sh start.sh                  # Syntax check
bash make.sh && bash calarch-v*.run check  # Build + verify
```

---

## 📧 Liên hệ

Nếu có bất kỳ thắc mắc nào:

- [Mở một Issue](https://github.com/tpc-pascal/calarch/issues) trên repo này.
- Gửi câu hỏi qua phần [Thảo luận (Discussions)](https://github.com/tpc-pascal/calarch/discussions) của dự án.
