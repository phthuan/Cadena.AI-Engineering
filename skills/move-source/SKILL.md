---
name: move-source
description: Di chuyển source code (move source) sang vị trí mới - thư mục, project, branch hoặc repository khác - và cập nhật reference, import khi cần. Move source code files to a new location, updating references and imports as needed.
---

# Move Source

0. Tuân thủ rules/common/knowledge-base.md, mục 1 (tra cứu bài học trước khi điều tra).
1. Xác định rõ nguồn, đích và phạm vi cần di chuyển (file, thư mục, project, thay đổi chưa commit hay một khoảng commit).
   Nếu chưa rõ, hỏi người dùng trước khi thay đổi.
2. Đọc các rule dùng chung áp dụng được trong rules/common/ và hướng dẫn riêng của project đích.
3. Kiểm tra trạng thái Git ở cả nguồn và đích. Không ghi đè hoặc làm mất thay đổi chưa commit ở đích.
4. Khi chuyển sang branch hoặc repository khác, so sánh các dependency mà code cần (class, constructor, property,
   helper, project reference) với phiên bản ở đích trước khi áp dụng. Kiểm tra patch trước khi áp dụng
   (ví dụ `git apply --check -v`) và merge thủ công những file không áp dụng sạch.
5. Cập nhật mọi reference: namespace, using/import, file project và solution, cấu hình, SQL script và test.
6. Giữ nguyên line ending và encoding của file. Không copy secret hoặc file cấu hình bị git-ignore chứa credential.
7. Build và chạy các kiểm tra liên quan ở đích; chỉ báo cáo kết quả thực tế.
8. Tóm tắt những gì đã di chuyển, những gì phải điều chỉnh để tương thích, rủi ro và phần việc còn lại.
9. Tuân thủ rules/common/knowledge-base.md, mục 2 (ghi lại bài học).
