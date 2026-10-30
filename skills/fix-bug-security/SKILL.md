---
name: fix-bug-security
description: Audit và sửa lỗ hổng bảo mật (security vulnerability, security finding) được báo cáo bởi pentest, scanner hoặc code review - HTML/hyperlink injection, XSS, SQL injection, open redirect, broken access control/IDOR, CSRF, path traversal, unsafe file upload, sensitive data exposure, security headers/CSP. Audit and fix security vulnerabilities reported by pentest, scanners or code review.
---

# Fix Bug - Security

Đóng vai trò Software Architect tập trung vào bảo mật ứng dụng (application security).
Làm việc theo hai giai đoạn: AUDIT, sau đó FIX khi người dùng đã phê duyệt. Nếu người dùng chỉ yêu cầu audit, dừng sau giai đoạn A.

0. Tuân thủ rules/common/knowledge-base.md, mục 1 (tra cứu bài học trước khi điều tra).
   Đồng thời tìm trong knowledge base theo tên lỗ hổng và mã CWE.

## A. Audit (không sửa code)

1. Phân loại finding: tên trong báo cáo, CWE, hạng mục OWASP, URL/API bị ảnh hưởng, parameter, payload.
   Mở playbook tương ứng trong rules/security/ (rules/security/README.md liệt kê các playbook).
   Nếu không có playbook nào khớp, dùng rules/security/_template.md làm checklist và ghi chú rằng đang thiếu playbook.
2. Đọc rules/common/, rules/bug-fixing/ và hướng dẫn riêng của project đích.
3. Xác định vị trí trường hợp được báo cáo: entry point -> data flow -> sink.
   Xác nhận nguồn dữ liệu do attacker kiểm soát và sink sử dụng nó một cách không an toàn. Tách bạch trường hợp đã xác nhận với trường hợp nghi ngờ.
4. Variant analysis (phân tích biến thể): tìm trên toàn bộ repository bằng các mẫu source và sink của playbook
   (controller, handler, validator, query, template email/notification, báo cáo, export,
   front-end JS, SQL script và stored procedure). URL được báo cáo chỉ là một trường hợp.
   Kiểm tra cả luồng dữ liệu đã lưu: input được lưu bây giờ và hiển thị sau đó ở màn hình, email hoặc export khác.
5. Với mỗi trường hợp, chọn đúng lớp (layer) để sửa theo playbook. Ưu tiên một helper,
   encoder, validator hoặc middleware dùng chung thay vì nhiều bản vá cục bộ, nhưng không thay đổi hành vi toàn cục
   khi chưa liệt kê mọi màn hình bị ảnh hưởng.
6. Báo cáo và DỪNG LẠI chờ phê duyệt:
   - Tóm tắt tổng thể: lỗ hổng, pattern root cause, số lượng trường hợp.
   - Bảng: #, file:line, source, sink, mức độ (Critical/High/Medium/Low), trạng thái (confirmed/suspected), cách sửa đề xuất.
   - Các field hợp lệ chứa HTML, URL hoặc ký tự đặc biệt cần xử lý riêng.
   - Những gì chưa được kiểm tra.

## B. Fix (sau khi được phê duyệt, chỉ các mục đã được duyệt)

7. Áp dụng mục "Cách sửa đúng" (Correct fix) của playbook. Không bao giờ dùng bất kỳ cách nào được liệt kê trong mục "Cách sửa sai" (Wrong fixes)
   (blacklist replace, chỉ validate phía client, double encoding, bắt lỗi rồi che giấu lỗi).
   Không comment code đã sửa (không giải thích lý do sửa, không giữ code cũ dạng comment); xem rules/common/common-rules.md.
8. Giữ nguyên dữ liệu hợp lệ và hành vi nghiệp vụ. Dữ liệu đã lưu có thể đã chứa
   payload: quyết định cùng người dùng nên làm sạch dữ liệu đó hay dựa vào output encoding.
9. Thêm test: các payload tấn công của playbook (kỳ vọng bị vô hiệu hóa) cùng với input hợp lệ (kỳ vọng không đổi).
   Chạy các test và build liên quan; chỉ báo cáo kết quả thực tế.
10. Báo cáo: từng mục đã sửa / chưa sửa / cần xác nhận, rủi ro còn lại (residual risk),
    và các bước hoặc payload chính xác để kiểm chứng bằng re-scan hoặc pentest retest.
11. Tuân thủ rules/common/knowledge-base.md, mục 2 (ghi lại bài học).
    Nếu loại lỗ hổng này chưa có playbook, đề xuất một file mới trong rules/security/ dựa trên _template.md.

## An toàn (Safety)

- Giữ các proof-of-concept payload ở mức vô hại (alert, link lành tính, probe không dùng sleep). Không bao giờ chạy chúng trên production.
- Không bao giờ đưa secret, token, connection string thật hoặc dữ liệu khách hàng vào code, test, báo cáo hoặc bài học.
- Không làm suy yếu các cơ chế bảo mật hiện có (CSP, validation, authorization) để cách sửa chạy được.
