# Quy trình Knowledge Base (Knowledge Base Procedure)

Knowledge base (cơ sở tri thức) là thư mục `knowledge/` của repository Cadena.AI-Engineering.
Đường dẫn tuyệt đối của nó được ghi ở dòng "Knowledge base" trong file global `~/.claude/CLAUDE.md` của người dùng.
Không được suy ra đường dẫn này tương đối theo thư mục skill: skills được liên kết qua Junction,
nên `..` tính từ đường dẫn skill sẽ dẫn tới `~/.claude`, không phải tới repository.

File này là nguồn sự thật duy nhất (single source of truth) quy định khi nào tra cứu và khi nào ghi lại bài học (lesson).
CLAUDE.md, các common rules và skills chỉ trỏ tới đây; chỉ thay đổi hành vi này trong file này.

Project key là tên thư mục gốc của repository sản phẩm hiện tại, viết thường
(`git rev-parse --show-toplevel`, lấy phần cuối cùng của đường dẫn).

## 1. Tra cứu trước khi điều tra

1. Thu thập từ khóa tìm kiếm: nguyên văn thông báo lỗi, loại exception, tên class, method, table và stored procedure.
2. Tìm các từ khóa đó trong `knowledge/<project-key>/` và `knowledge/common/` (tìm theo nội dung file, bao gồm cả dòng `keywords`).
3. Đọc mọi bài học khớp. Bỏ qua các bài học có `status: outdated`.
4. Trước khi dựa vào một bài học, xác minh rằng các file và symbol mà bài học nêu vẫn còn tồn tại và vẫn đúng như mô tả.
   Nếu code đã thay đổi khiến bài học không còn áp dụng, đặt `status: outdated` và nói rõ điều đó.
5. Bắt đầu từ hướng đi trong mục "Lần sau" (Next time) của bài học. Không lặp lại bất kỳ điều gì đã liệt kê trong mục "Hướng đi sai" (Dead ends)
   trừ khi có bằng chứng mới; nếu vẫn làm, phải nêu lý do.
6. Cho người dùng biết những bài học nào đã được sử dụng.

## 2. Ghi lại sau khi hoàn thành

Ghi lại một bài học khi có ít nhất một điều sau đúng:
- Root cause không hiển nhiên khi chỉ nhìn triệu chứng.
- Đã điều tra và loại bỏ một hoặc nhiều giả thuyết.
- Cách sửa phụ thuộc vào một "bẫy" (gotcha) về cấu hình, môi trường hoặc dữ liệu.
- Pattern này nhiều khả năng sẽ xuất hiện lại trong project này hoặc project khác.

Bỏ qua các tác vụ tầm thường (lỗi chính tả, sửa một dòng hiển nhiên).

Các bước:
1. Tìm bài học đã có với cùng root cause. Cập nhật bài học đó thay vì tạo bản trùng lặp.
2. Nếu không có, copy `knowledge/_template.md` thành `knowledge/<project-key>/YYYY-MM-DD-short-slug.md`
   (dùng `knowledge/common/` khi bài học không gắn riêng với một project).
3. Điền đầy đủ mọi mục. Đưa nguyên văn thông báo lỗi vào `keywords` để có thể tìm thấy bằng tìm kiếm.
   Điền mục "Hướng đi sai" (Dead ends) một cách trung thực, bao gồm cả những hướng sai đã đi trong chính tác vụ này.
4. Không bao giờ đưa secret, connection string, token hoặc dữ liệu khách hàng vào bài học.
5. Không commit. Cho người dùng biết đường dẫn file để họ review, commit và push.

## 3. Nâng các bài học lặp lại thành rule

Khi có từ ba bài học trở lên cùng một pattern root cause, đề xuất một rule trong
`rules/bug-fixing/`, `rules/performance/` hoặc `rules/feature-development/` để ngăn lỗi đó,
và đánh dấu các bài học là đã được rule đó bao phủ trong mục "Lần sau" (Next time) của chúng.

## Quy ước tiêu đề mục

Các tiêu đề mục trong bài học và playbook được viết theo dạng `Tiếng Việt (English)`, ví dụ `## Hướng đi sai (Dead ends)`.
Khi tham chiếu tới một mục, có thể dùng tên tiếng Việt hoặc tên tiếng Anh trong ngoặc; cả hai cùng chỉ một mục.
Các bài học cũ có tiêu đề chỉ bằng tiếng Anh vẫn hợp lệ.
