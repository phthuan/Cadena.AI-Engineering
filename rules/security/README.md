# Security Playbooks

Mỗi loại lỗ hổng (vulnerability) một file. Được dùng bởi skill fix-bug-security (audit và sửa),
và bởi review-code, new-feature để ngăn các lỗi tương tự.

| Playbook | Phạm vi |
|---|---|
| [html-injection-xss.md](html-injection-xss.md) | HTML injection, HTML hyperlink injection, XSS dạng reflected / stored / DOM (CWE-79, CWE-80) |
| [rate-limiting.md](rate-limiting.md) | Lack of rate limiting, brute force, OTP brute force, email bombing, resource exhaustion (CWE-307, CWE-770) |

Để thêm playbook: copy `_template.md` thành `<vulnerability>.md`, điền đầy đủ mọi mục, rồi thêm một dòng vào bảng trên.
Chỉ thêm playbook khi đã gặp loại lỗ hổng đó trong một tác vụ thực tế, không tạo trước.
