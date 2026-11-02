# Cadena Engineering — Quy tắc chung (Common Rules)

Áp dụng cho mọi task, có dùng skill hay không. Rule và playbook theo loại công việc (`rules/bug-fixing/`, `rules/performance/`,
`rules/feature-development/`, `rules/security/`) được chỉ định trong CLAUDE.md toàn cục và trong từng skill.

## Nguyên tắc chung

- Đọc và kiểm tra code hiện có trước khi thay đổi.
- Tuân theo kiến trúc, coding convention và hướng dẫn riêng (CLAUDE.md) của project đích.
  Nếu hướng dẫn của project mâu thuẫn với rule dùng chung, nêu ra và hỏi người dùng.
- Giữ nguyên hành vi nghiệp vụ (business behavior) trừ khi được yêu cầu thay đổi một cách rõ ràng.
- Tránh refactor không liên quan.
- Giải thích root cause (nguyên nhân gốc) trước khi đề xuất cách sửa lỗi.
- Với công việc performance, xác định điểm nghẽn (bottleneck) và đo đạc khi có thể.
- Với tính năng mới, cân nhắc validation, security, xử lý lỗi (error handling) và test.
- Phân biệt rõ sự thật đã kiểm chứng với giả định.
- Không bao giờ tuyên bố test đã pass nếu test chưa thực sự được chạy.
- Khi viết hoặc chạy test, tuân thủ rules/common/testing.md (baseline, phân loại lỗi, Database testing, báo cáo).
- Không bao giờ để lộ secret, token hoặc credential.

## Không comment code đã sửa

- Không thêm comment giải thích lý do sửa hoặc thay đổi (vd `// fix bug ...`, `// sửa để tránh null`, `// thêm check vì ...`, `// changed because ...`, `// modified by/ngày ...`).
- Không giữ code cũ dưới dạng comment.
- Không thêm comment mới vào code đã sửa, trừ khi người dùng yêu cầu. Giữ nguyên comment có sẵn.
- Lý do sửa chỉ ghi trong phản hồi cho người dùng hoặc commit message; lịch sử thay đổi để git quản lý.
- Trước khi báo hoàn thành, rà lại diff và xóa mọi comment vi phạm.
