---
name: new-feature
description: Lập kế hoạch và triển khai tính năng mới (new feature) - API, business logic, chức năng UI và integration. Plan and implement new features, APIs, business logic, UI functionality and integrations.
---

# New Feature

0. Tuân thủ rules/common/knowledge-base.md, mục 1 (tra cứu bài học trước khi điều tra).
1. Tìm hiểu kiến trúc hiện có và các phần triển khai tương tự.
2. Đọc các rule dùng chung áp dụng được trong rules/common/ và rules/feature-development/.
3. Xác định yêu cầu, các thành phần bị ảnh hưởng và ràng buộc tương thích (compatibility).
4. Đề xuất kế hoạch triển khai trước khi thực hiện thay đổi đáng kể.
5. Tuân theo convention đã thiết lập và tránh thêm dependency không cần thiết.
6. Cân nhắc validation, authorization, xử lý lỗi, logging và test.
   Đối chiếu cách xử lý input và output với các playbook trong rules/security/.
7. Triển khai giải pháp hoàn chỉnh nhỏ nhất.
   Không comment code đã sửa (không giải thích lý do thay đổi, không giữ code cũ dạng comment); xem rules/common/common-rules.md.
8. Chạy các kiểm tra liên quan và báo cáo kết quả thực tế.
9. Tóm tắt các thay đổi, rủi ro và phần việc còn lại.
10. Tuân thủ rules/common/knowledge-base.md, mục 2 (ghi lại bài học).
