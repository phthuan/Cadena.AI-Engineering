# <Tên lỗ hổng>

## Nhận diện (Recognize)
- Tên trong báo cáo / scanner: <các tên được dùng trong báo cáo pentest và công cụ>
- CWE / OWASP: <CWE-xxx, hạng mục OWASP Top 10>
- Triệu chứng: <những gì tester đã thấy>

## Nguồn dữ liệu (Sources)
<Nơi dữ liệu do attacker kiểm soát đi vào: request body, query, route, header, cookie,
file upload, file import, dữ liệu do người dùng khác lưu trước đó, API bên thứ ba.>

## Sink và mẫu tìm kiếm (Sinks and search patterns)
<Code sử dụng dữ liệu một cách không an toàn, kèm mẫu tìm kiếm chính xác theo từng stack.>
- C# / .NET:
- Razor / WebForms:
- JavaScript:
- SQL / stored procedures:

## Cách sửa đúng (Correct fix)
<Theo từng ngữ cảnh. Nêu tên helper hoặc thư viện của project cần dùng.>

## Cách sửa sai (Wrong fixes)
<Các cách sửa trông có vẻ đúng nhưng có thể bị bypass hoặc làm hỏng dữ liệu.>

## Payload kiểm thử (Test payloads)
| Payload | Kết quả mong đợi sau khi sửa |
|---|---|

## Kiểm chứng (Verification)
<Unit/integration test, các bước kiểm tra thủ công, những gì cần gửi cho đội pentest để retest.>

## Bài học liên quan (Related lessons)
<Liên kết tới các bài học trong knowledge/.>
