---
name: review-code
description: Review code thay đổi với vai trò Software Architect (code review) - kiểm tra chất lượng code và thiết kế, tối ưu, performance, và xem mọi nơi bị ảnh hưởng (caller, luồng liên quan, dữ liệu, cấu hình, test) đã được cập nhật chưa. Review code changes as a Software Architect - check code quality and design, optimization, performance, and whether every affected place (callers, related flows, data, configuration, tests) has been updated.
---

# Review Code

Đóng vai trò Software Architect. Chỉ review; không sửa code trừ khi người dùng yêu cầu sửa.

0. Tuân thủ rules/common/knowledge-base.md, mục 1 (tra cứu bài học trước khi điều tra).
1. Xác định phạm vi review: diff hiện tại (`git diff`, cả staged và unstaged), một branch,
   một khoảng commit hoặc các file người dùng chỉ định. Nêu rõ phạm vi trước khi review.
2. Đọc các rule dùng chung áp dụng được trong rules/common/, rules/performance/, rules/bug-fixing/
   và rules/feature-development/, cùng với hướng dẫn riêng của project đích.
3. Hiểu mục đích của thay đổi và đọc code xung quanh, không chỉ các dòng đã thay đổi.

## A. Code có tốt không?

4. Tính đúng đắn (correctness): lỗi logic, edge case, xử lý null, xử lý lỗi, transaction,
   concurrency, dùng sai async/await, giải phóng tài nguyên (resource disposal).
5. Thiết kế: đặt trách nhiệm đúng chỗ, phân lớp (controller / application / domain / infrastructure),
   coupling, trùng lặp với helper đã có, nhất quán với convention đã thiết lập của project.
6. Khả năng đọc và bảo trì: đặt tên, kích thước method, dead code, magic value, độ phức tạp không cần thiết.
7. Security: validation, authorization, injection, dữ liệu nhạy cảm trong log hoặc response.
   Dùng các playbook trong rules/security/ (mẫu tìm kiếm và mục "Cách sửa sai" (Wrong fixes)) cho phần code đã thay đổi.

## B. Code đã được tối ưu và có hiệu năng tốt chưa?

8. Database: N+1 query, gọi lặp trong vòng lặp, thiếu batching, lấy thừa cột
   hoặc dòng (over-fetching), thiếu filter hoặc paging, SQL hoặc stored procedure kém hiệu quả, thiếu index.
9. Memory và CPU: allocation không cần thiết, materialize lặp lại (`ToList`, enumerate hai lần),
   object lớn trong memory, blocking call trên luồng async, thuật toán kém hiệu quả.
10. I/O và network: gọi external thừa, thiếu cache khi dữ liệu ổn định, API "nói nhiều" (chatty).
11. Phân biệt sự thật đã đo đạc với giả định. Không tự bịa ra bottleneck; đánh dấu các vấn đề
    nghi ngờ là nghi ngờ (suspected) và nêu cách xác nhận.

## C. Mọi nơi bị ảnh hưởng đã được cập nhật chưa?

12. Trace mọi method, class, DTO, request/response, entity, table, column,
    stored procedure, configuration key và constant đã thay đổi.
13. Tìm trên toàn bộ repository các caller, implementation, override, mapping
    và reference (bao gồm SQL script, stored procedure, file cấu hình và test).
14. Kiểm tra các luồng liên quan phải thay đổi cùng nhau: các biến thể create/update/delete/query,
    các handler cùng nhóm, validator, mapper, API contract, migration, front-end consumer.
15. Kiểm tra tương thích ngược (backward compatibility): public API contract, dữ liệu đã serialize, các dòng dữ liệu đã có trong database.
16. Kiểm tra test: test hiện có đã được cập nhật chưa, và hành vi mới đã có test chưa?
17. Liệt kê từng nơi bị ảnh hưởng với trạng thái: đã cập nhật (updated), còn thiếu (missing) hoặc cần xác nhận (needs confirmation).

## Báo cáo

18. Bắt đầu bằng kết luận tổng thể: ready / ready with minor comments / needs changes
    (sẵn sàng / sẵn sàng kèm góp ý nhỏ / cần sửa).
19. Liệt kê các phát hiện theo mức độ nghiêm trọng (Critical, Major, Minor, Suggestion). Với mỗi phát hiện, nêu
    file và dòng, vấn đề, vì sao quan trọng, và cách sửa cụ thể.
20. Đưa ra một bảng riêng các nơi bị ảnh hưởng từ bước 17.
21. Nêu rõ những gì chưa được review hoặc không thể kiểm chứng. Không bao giờ tuyên bố test đã pass
    nếu test chưa thực sự được chạy.
22. Tuân thủ rules/common/knowledge-base.md, mục 2 (ghi lại bài học) khi quá trình review
    phát hiện một pattern không hiển nhiên đáng chia sẻ.
