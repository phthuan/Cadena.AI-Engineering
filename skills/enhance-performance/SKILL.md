---
name: enhance-performance
description: Phân tích và tối ưu hiệu năng ứng dụng (performance optimization) - method chậm, SQL query, database call, CPU, memory và latency. Analyze and optimize application performance, slow methods, SQL queries, database calls, CPU, memory and latency.
---

# Enhance Performance

0. Tuân thủ rules/common/knowledge-base.md, mục 1 (tra cứu bài học trước khi điều tra).
1. Đọc method mục tiêu và trace các caller và callee của nó.
2. Đọc các rule dùng chung áp dụng được trong rules/common/ và rules/performance/.
3. Xác định chính xác các method, SQL query, stored procedure và database call bị lặp lại.
4. Phân biệt sự thật đã đo đạc với giả định; không tự bịa ra bottleneck.
5. Giải thích root cause trước khi đề xuất thay đổi.
6. Thực hiện thay đổi tối thiểu, giữ nguyên hành vi nghiệp vụ (business behavior).
   Không comment code đã sửa (không giải thích lý do tối ưu, không giữ code cũ dạng comment); xem rules/common/common-rules.md.
7. Cân nhắc SQL I/O, N+1 query, batching, allocation và vòng đời tài nguyên (resource lifetime).
8. Thêm hoặc cập nhật test khi khả thi.
9. Chạy các kiểm tra liên quan khi có thể.
10. Báo cáo bằng chứng, các file đã thay đổi, rủi ro và kết quả test thực tế.
11. Tuân thủ rules/common/knowledge-base.md, mục 2 (ghi lại bài học).
