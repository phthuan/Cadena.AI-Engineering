---
name: new-feature
description: Lập kế hoạch và triển khai tính năng mới (new feature) - API, business logic, chức năng UI và integration. Plan and implement new features, APIs, business logic, UI functionality and integrations.
---

# New Feature

0. Tuân thủ rules/common/knowledge-base.md, mục 1 (tra cứu bài học trước khi điều tra).
1. Đọc các rule dùng chung áp dụng được trong rules/common/, rules/feature-development/
   và các playbook liên quan trong rules/security/, cùng với hướng dẫn riêng của project đích.
2. Tìm hiểu kiến trúc hiện có và các phần triển khai tương tự.
3. Xác định yêu cầu, các thành phần bị ảnh hưởng và ràng buộc tương thích (compatibility).
4. Đề xuất kế hoạch triển khai trước khi thực hiện thay đổi đáng kể.
5. Tuân theo convention đã thiết lập và tránh thêm dependency không cần thiết.
6. Cân nhắc validation, authorization, xử lý lỗi, logging và test.
   Đối chiếu cách xử lý input và output với các playbook security đã đọc ở bước 1.
7. Triển khai giải pháp hoàn chỉnh nhỏ nhất.
   Không comment code đã sửa (không giải thích lý do thay đổi, không giữ code cũ dạng comment); xem rules/common/common-rules.md.
8. Build và chạy các test liên quan; chỉ báo cáo kết quả thực tế.
9. Tóm tắt các thay đổi, rủi ro và phần việc còn lại.
10. Tuân thủ rules/common/knowledge-base.md, mục 2 (đề xuất bài học, chỉ ghi khi người dùng đồng ý).
