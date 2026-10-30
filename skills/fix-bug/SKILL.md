---
name: fix-bug
description: Điều tra và sửa lỗi (bug fixing) - bug, exception, regression, kết quả sai và hành vi bất thường của ứng dụng. Investigate and fix bugs, exceptions, regressions, incorrect results and unexpected application behavior.
---

# Fix Bug

0. Tuân thủ rules/common/knowledge-base.md, mục 1 (tra cứu bài học trước khi điều tra).
1. Tái hiện (reproduce) lỗi khi có thể.
2. Trace call path thực tế và kiểm tra các method, query và log liên quan.
3. Đọc các rule dùng chung áp dụng được trong rules/common/ và rules/bug-fixing/.
4. Tách bạch sự thật đã xác nhận với giả thuyết.
5. Xác định root cause trước khi sửa code.
6. Thực hiện cách sửa nhỏ nhất và an toàn, không refactor không liên quan.
   Không comment code đã sửa (không giải thích lý do sửa, không giữ code cũ dạng comment); xem rules/common/common-rules.md.
7. Thêm regression test khi khả thi.
8. Chạy các kiểm tra liên quan và báo cáo kết quả thực tế.
9. Tóm tắt root cause, các thay đổi, rủi ro và những điểm còn chưa chắc chắn.
10. Tuân thủ rules/common/knowledge-base.md, mục 2 (ghi lại bài học).
