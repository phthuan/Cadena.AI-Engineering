---
name: fix-bug
description: Điều tra và sửa lỗi (bug fixing) - bug, exception, regression, kết quả sai và hành vi bất thường của ứng dụng. Investigate and fix bugs, exceptions, regressions, incorrect results and unexpected application behavior.
---

# Fix Bug

0. Tuân thủ rules/common/knowledge-base.md, mục 1 (tra cứu bài học trước khi điều tra).
1. Đọc các rule dùng chung áp dụng được trong rules/common/ và rules/bug-fixing/, cùng với hướng dẫn riêng của project đích.
2. Tái hiện (reproduce) lỗi khi có thể.
   Tìm test project và chạy test baseline liên quan trước khi sửa; xem rules/common/testing.md.
3. Trace call path thực tế và kiểm tra các method, query và log liên quan.
4. Tách bạch sự thật đã xác nhận với giả thuyết.
5. Xác định root cause trước khi sửa code.
6. Thực hiện cách sửa nhỏ nhất và an toàn, không refactor không liên quan.
   Không comment code đã sửa (không giải thích lý do sửa, không giữ code cũ dạng comment); xem rules/common/common-rules.md.
7. Thêm regression test tái hiện đúng lỗi: test phải FAIL trên code chưa sửa (vì đúng root cause) và PASS sau khi sửa.
   Nên viết test trước bước 6; nếu viết sau, tạm hoàn tác bản sửa để xác nhận test FAIL.
   Nếu không viết được test tự động, nêu lý do và các bước tái hiện, kiểm chứng thay thế.
8. Build và chạy các test liên quan theo rules/common/testing.md; so sánh với baseline,
   báo cáo command thực tế và kết quả PASS/FAIL/SKIP.
9. Tóm tắt root cause, các thay đổi, rủi ro và những điểm còn chưa chắc chắn.
10. Tuân thủ rules/common/knowledge-base.md, mục 2 (đề xuất bài học, chỉ ghi khi người dùng đồng ý).
