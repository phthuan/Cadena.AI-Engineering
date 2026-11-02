# Quy tắc Testing (Testing Rules)

Áp dụng cho các skill `fix-bug`, `fix-bug-security`, `enhance-performance`, `move-source`, `new-feature`
và mọi task có chạy test. File này là nguồn sự thật duy nhất cho quy tắc testing chung;
mỗi skill chỉ bổ sung yêu cầu riêng theo đặc thù của nó.

## 1. Tìm test và cách chạy

- Tìm test project liên quan tới code bị ảnh hưởng (vd `*.Tests.csproj`, `*.UnitTests`, `*.IntegrationTests`,
  project tham chiếu xUnit/NUnit/MSTest, script `test` trong `package.json`).
- Ưu tiên chạy test theo hướng dẫn của project (CLAUDE.md, README, script build, pipeline CI).
  Chỉ tự dựng command khi project không có hướng dẫn.
- Chạy nhóm test liên quan trước, sau đó mở rộng theo mức độ ảnh hưởng của thay đổi.

## 2. Baseline

- Trước khi sửa code, chạy test liên quan để lấy baseline nếu khả thi.
- Ghi lại các test đang FAIL hoặc SKIP sẵn trước khi thay đổi, để so sánh sau khi sửa.

## 3. Không làm sai lệch kết quả test

- Không sửa, xóa, skip hoặc vô hiệu hóa test chỉ để đạt PASS (vd thêm `[Ignore]`/`Skip`, comment assertion,
  nới lỏng assertion, tăng timeout tùy tiện, loại test khỏi project).
- Chỉ sửa test có sẵn khi yêu cầu nghiệp vụ thay đổi làm kỳ vọng cũ không còn đúng; nêu rõ test nào, lý do,
  và hỏi người dùng nếu chưa chắc.

## 4. Phân loại lỗi

Với mỗi test FAIL hoặc lỗi khi chạy, phân loại rõ:

- **Lỗi có sẵn (pre-existing):** đã FAIL ở baseline, không liên quan tới thay đổi.
- **Lỗi do thay đổi (regression):** PASS ở baseline nhưng FAIL sau khi sửa. Phải xử lý trước khi báo hoàn thành.
- **Lỗi môi trường (environment):** thiếu SDK/package, không kết nối được DB hoặc service, thiếu cấu hình, lỗi quyền.

Nếu không có baseline thì không được khẳng định một lỗi là "có sẵn"; nêu rõ là chưa xác định.

## 5. Khi không thể chạy test

Nêu lý do cụ thể và phương án xác minh thay thế, ví dụ: build thành công, chạy unit test không phụ thuộc DB,
kiểm tra thủ công theo các bước cụ thể, hoặc command để người dùng tự chạy trên môi trường phù hợp.

## 6. Báo cáo

- Command thực tế đã chạy.
- Kết quả: số PASS / FAIL / SKIP, so sánh với baseline (nếu có).
- Phân loại các FAIL theo mục 4.
- Những gì chưa được kiểm tra và lý do.

Không bao giờ tuyên bố test đã pass nếu test chưa thực sự được chạy.

## 7. Database Testing

Áp dụng khi integration test cần Database.

- Ưu tiên đọc connection string từ `connectstring.config` của project. Nếu có nhiều file, xác định đúng file
  mà test project thực sự dùng khi chạy.
- Trước khi chạy, xác định server, database và môi trường (local, dev, test, staging, production).
  Nếu không chắc, hỏi người dùng.
- Không hardcode connection string vào test code; dùng cơ chế đọc cấu hình hiện có của project.
- Không tự ý thay đổi connection string hoặc cấu hình DB, kể cả tạm thời.
- Không chạy test có khả năng INSERT, UPDATE, DELETE hoặc thay đổi dữ liệu (gọi stored procedure ghi dữ liệu,
  migration, seed, truncate) trên DB thật khi chưa xác định đó là môi trường test an toàn
  (DB local hoặc DB test riêng, được người dùng xác nhận).
- Nếu không kết nối được DB hoặc không xác định được môi trường an toàn: không tự ý chạy test, ghi rõ lý do
  và đề xuất phương án thay thế (unit test với mock/fake, DB local hoặc container, nhờ người dùng xác nhận
  DB test, hoặc command để người dùng tự chạy).
- Không hiển thị username, password hoặc thông tin nhạy cảm trong log, output và báo cáo. Chỉ nêu server và
  tên database; che phần credential (vd `User ID=***;Password=***`). Không in nguyên file cấu hình ra terminal.
