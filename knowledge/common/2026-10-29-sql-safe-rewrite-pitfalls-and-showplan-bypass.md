---
title: Rewrite SQL "an toàn" vẫn đổi kết quả (ISNULL với bit, NOT IN qua outer join, N'' với so sánh khoảng) và SET SHOWPLAN_XML OFF làm estimated capture thực thi SQL
project: common
type: security
keywords: [SET SHOWPLAN_XML OFF, SHOWPLAN_ALL, NOEXEC, PARSEONLY, FMTONLY, estimated plan, ISNULL, bit, NOT IN, NOT EXISTS, LEFT JOIN, OUTER APPLY, CONVERT_IMPLICIT, nvarchar literal, COUNT(*) OVER, OLD_PASSWORD, sp_setapprole, sp_addlogin, InvalidCastException]
files: [src/PerfTracker.Core/Analysis/StaticAnalyzer.cs, src/PerfTracker.Data/PlanCapture.cs, src/PerfTracker.Core/History/SecretRedactor.cs]
commit: 74a7f00 (repo SSMS Performance Tracker)
date: 2026-10-29
author: Claude (SQL Server Performance Tracker)
status: active
---

## Triệu chứng (Symptom)
- Auto-fix gắn nhãn "Safe" nhưng query sau khi rewrite trả về số dòng khác query gốc.
- Estimated plan capture (chạy `SET SHOWPLAN_XML ON` rồi gửi script của người dùng) báo `InvalidCastException` khi đọc cột plan. Lý do: một batch phía sau đã thực sự chạy và trả về dữ liệu thay vì plan.
- Query history và AI payload vẫn chứa mật khẩu ở một số dạng câu lệnh.

## Nguyên nhân gốc (Root cause)
- `ISNULL(col, a) = b` → `col = b` (hoặc `(col = b OR col IS NULL)`) chỉ tương đương khi `col` là kiểu số nguyên và `a` vừa miền giá trị. ISNULL đổi `a` sang kiểu của `col`: với `bit`, `ISNULL(IsActive, 2) = 1` biến 2 thành 1, nên dòng NULL vẫn khớp. Với decimal/char cũng có thể bị làm tròn hoặc cắt.
- `x NOT IN (SELECT c ...)` → `NOT EXISTS` cần cả `x` và `c` không bao giờ NULL. Cột ngoài có thể là NOT NULL trong schema nhưng vẫn NULL trong query nếu bảng của nó nằm ở phía tùy chọn của LEFT/RIGHT/FULL JOIN hoặc OUTER APPLY.
- Bỏ tiền tố `N` khi so sánh với cột varchar: tương đương với `=`/`<>` và literal ASCII, nhưng không chắc với `<`/`>`. Với SQL collation, varchar và nvarchar sắp xếp một số dấu câu khác nhau.
- `(SELECT COUNT(*) OVER () ...) > 0` không giống EXISTS (có thể trả về nhiều dòng hoặc NULL).
- `SET SHOWPLAN_XML ON` chỉ có hiệu lực cho tới khi bị tắt. Script của người dùng có một batch `SET SHOWPLAN_XML OFF` (hoặc `SHOWPLAN_ALL`/`SHOWPLAN_TEXT`) thì các batch sau chạy thật, kể cả DML.
- Regex `\bPASSWORD` không khớp `OLD_PASSWORD` (`_` là ký tự word). Mật khẩu truyền theo vị trí (`sp_setapprole 'r', 'pw'`) hoặc qua `@rmtpassword = N'...'` không có từ khóa PASSWORD.

## Cách sửa (Fix)
- Chỉ gắn Safe khi schema chứng minh được điều kiện: kiểu số nguyên + miền giá trị cho ISNULL; NOT NULL cho cả hai cột **và** binding của bảng ngoài không nullable do join (lưu cờ `NullableByJoin` khi bind FROM: LeftOuter → bảng phải, RightOuter → bảng trái, FullOuter → cả hai, OuterApply → bảng phải). Với N-prefix, chỉ Safe khi so sánh `=`/`<>`. Bỏ qua COUNT có `OVER`/`FOR`/`WINDOW`.
- Estimated capture: trước khi mở kết nối, quét token của script, từ chối `SET` theo sau bởi `SHOWPLAN_XML|SHOWPLAN_ALL|SHOWPLAN_TEXT|STATISTICS|NOEXEC|PARSEONLY|FMTONLY`. Quét token bắt được cả lệnh SET nằm trong IF/BEGIN.
- Redactor: `\b(?:OLD_)?PASSWORD`, `PASSWORD = 0x...`, `@\w*(password|pwd|secret)\w* [type] = '...'`, và che mọi string literal sau tên các procedure nhận mật khẩu theo vị trí.

## Kiểm chứng (Verification)
- Test trên dữ liệu thật: `VALUES (NULL),(1),(0)` cho thấy `ISNULL(b,2)=1` và `b=1` trả số dòng khác nhau. LEFT JOIN + NOT IN và NOT EXISTS cũng cho số dòng khác nhau. 10 rewrite Safe còn lại cho tập kết quả giống hệt.
- Test capture dùng bảng tạm toàn cục `##probe` giữ bởi một kết nối riêng: script `SET SHOWPLAN_XML OFF / GO / INSERT ##probe` → trước khi sửa thì câu lệnh chạy; sau khi sửa thì bị từ chối và `COUNT(*) = 0`.

## Hướng đi sai (Dead ends)
- Tin rằng "schema nói NOT NULL" là đủ cho NOT IN → NOT EXISTS: sai khi có outer join.
- Coi ISNULL với literal số nguyên là an toàn mà không cần biết kiểu cột: sai với bit.
- Kiểm tra guard bằng `Assert.ThrowsAny<InvalidOperationException>` lúc chưa sửa: test báo `InvalidCastException`. Đó chính là bằng chứng SQL đã chạy, không phải lỗi của test.

## Lần sau (Next time)
Với mọi rewrite SQL tự động, liệt kê các điều kiện tương đương (kiểu, NULL do join, collation, số dòng của subquery) và chỉ gắn Safe khi có metadata chứng minh. Viết test chạy cả hai phiên bản trên dữ liệu có NULL. Với mọi chế độ "không thực thi" dựa trên SET session option, chặn các lệnh SET tắt chế độ đó trong input của người dùng.
