# Cadena Engineering — Quy tắc chung (Common Rules)

## Nguyên tắc chung

- Đọc và kiểm tra code hiện có trước khi thay đổi.
- Tuân theo kiến trúc và coding convention đã được thiết lập của project.
- Tránh refactor không liên quan.
- Giải thích root cause (nguyên nhân gốc) trước khi đề xuất cách sửa lỗi.
- Với công việc performance, xác định điểm nghẽn (bottleneck) và đo đạc khi có thể.
- Với tính năng mới, cân nhắc validation, security, xử lý lỗi (error handling) và test.
- Không bao giờ tuyên bố test đã pass nếu test chưa thực sự được chạy.
- Không bao giờ để lộ secret, token hoặc credential.
- Không comment code đã sửa:
  - Không thêm comment giải thích lý do sửa hoặc thay đổi (vd `// fix bug ...`, `// sửa để tránh null`, `// thêm check vì ...`, `// changed because ...`, `// modified by/ngày ...`).
  - Không giữ code cũ dưới dạng comment.
  - Không thêm comment mới vào code đã sửa, trừ khi người dùng yêu cầu. Giữ nguyên comment có sẵn.
  - Lý do sửa chỉ ghi trong phản hồi cho người dùng hoặc commit message; lịch sử thay đổi để git quản lý.
  - Trước khi báo hoàn thành, rà lại diff và xóa mọi comment vi phạm.

## Quy tắc theo loại công việc (Task-specific rules)

- Tác vụ performance: đọc các file liên quan trong `rules/performance/`.
- Tác vụ sửa lỗi (bug fixing): đọc các file liên quan trong `rules/bug-fixing/`.
- Tác vụ tính năng (feature): đọc các file liên quan trong `rules/feature-development/`.
- Tác vụ security: đọc các playbook liên quan trong `rules/security/`.

Trước khi thực hiện thay đổi đáng kể, xem các rule dùng chung áp dụng được và các convention hiện có của project đích.
