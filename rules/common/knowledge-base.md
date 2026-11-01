# Quy trình Knowledge Base (Knowledge Base Procedure)

Knowledge base (cơ sở tri thức) là thư mục `knowledge/` của repository Cadena.AI-Engineering.
Đường dẫn tuyệt đối của nó được ghi ở dòng "Knowledge base" trong file global `~/.claude/CLAUDE.md` của người dùng.
Không được suy ra đường dẫn này tương đối theo thư mục skill: skills được liên kết qua Junction,
nên `..` tính từ đường dẫn skill sẽ dẫn tới `~/.claude`, không phải tới repository.

File này là nguồn sự thật duy nhất (single source of truth) quy định khi nào tra cứu và khi nào ghi lại bài học (lesson).
CLAUDE.md, các common rules và skills chỉ trỏ tới đây; chỉ thay đổi hành vi này trong file này.

Project key là tên thư mục gốc của repository sản phẩm hiện tại, viết thường
(`git rev-parse --show-toplevel`, lấy phần cuối cùng của đường dẫn).

Branch key là tên branch đang checkout của repository sản phẩm (`git branch --show-current`),
viết thường, thay `/` và `\` bằng `-`. Ví dụ branch `HAS260102_5.3.145.0` → `has260102_5.3.145.0`,
branch `feature/rate-limit` → `feature-rate-limit`.

Phạm vi bài học (lesson scope):
- `knowledge/<project-key>/<branch-key>/`: bài học riêng của branch. Đây là nơi mặc định.
- `knowledge/<project-key>/_shared/`: bài học chung cho mọi branch của project.
- `knowledge/common/`: bài học chung cho mọi project.

Nếu đang ở trạng thái detached HEAD (`git branch --show-current` trả về rỗng) thì không có branch key:
chỉ tra cứu `knowledge/<project-key>/_shared/` và `knowledge/common/`, và hỏi người dùng branch nào trước khi ghi bài học.

## 1. Tra cứu trước khi điều tra

1. Thu thập từ khóa tìm kiếm: nguyên văn thông báo lỗi, loại exception, tên class, method, table và stored procedure.
2. Tìm các từ khóa đó (theo nội dung file, bao gồm cả dòng `keywords`) chỉ trong ba nơi:
   - `knowledge/<project-key>/<branch-key>/`
   - `knowledge/<project-key>/_shared/`
   - `knowledge/common/`

   Không đọc thư mục của branch khác và của project khác: code ở branch khác có thể khác,
   nên bài học ở đó dễ dẫn tới kết luận sai. Chỉ mở rộng sang branch khác khi người dùng yêu cầu rõ,
   hoặc khi skill move-source di chuyển code từ branch đó (đọc thêm bài học của branch nguồn).
3. Đọc mọi bài học khớp. Bỏ qua các bài học có `status: outdated`.
4. Trước khi dựa vào một bài học, xác minh rằng các file và symbol mà bài học nêu vẫn còn tồn tại và vẫn đúng như mô tả.
   Nếu code đã thay đổi khiến bài học không còn áp dụng, đặt `status: outdated` và nói rõ điều đó.
5. Bắt đầu từ hướng đi trong mục "Lần sau" (Next time) của bài học. Không lặp lại bất kỳ điều gì đã liệt kê trong mục "Hướng đi sai" (Dead ends)
   trừ khi có bằng chứng mới; nếu vẫn làm, phải nêu lý do.
6. Cho người dùng biết những bài học nào đã được sử dụng.

## 2. Ghi lại bài học

Nguyên tắc: không lưu "Claude đã làm gì" (What Claude did), chỉ lưu "Claude đã học được gì" (What Claude learned).
Một bài học tốt giúp Claude tránh lặp lại sai lầm hoặc ra quyết định kỹ thuật tốt hơn trong task sau.

### 2.1. Thời điểm ghi

Claude không tự ghi bài học: Claude đề xuất, người dùng quyết định.

| Lúc | Claude làm gì |
|---|---|
| Kết thúc task dùng skill (`fix-bug`, `fix-bug-security`, `enhance-performance`, `new-feature`, `review-code`, `move-source`) | Đánh giá theo mục 2.2 đến 2.5; nếu có bài học đạt thì đề xuất ở cuối phản hồi, chưa ghi |
| Kết thúc task không dùng skill nhưng có điều tra hoặc thay đổi kỹ thuật đáng kể | Như trên (CLAUDE.md toàn cục yêu cầu) |
| Đang làm task thì phát hiện một bài học kỹ thuật quan trọng đã được xác minh | Giữ lại và đề xuất cùng lúc ở cuối task |
| Người dùng đồng ý với đề xuất, hoặc gõ `/record-lesson` | Ghi theo mục 2.5 đến 2.7 |

Đề xuất gồm: tiêu đề ngắn, điều kiện ở mục 2.2 mà bài học đáp ứng, `confidence`, và nơi sẽ ghi
(file mới hay cập nhật bài học nào). Kết thúc bằng câu hỏi có ghi hay không.
- Không có bài học đạt mục 2.2 đến 2.4 thì không đề xuất và không cần nhắc tới việc ghi bài học.
- Người dùng từ chối hoặc bỏ qua đề xuất thì không ghi, và không đề xuất lại bài học đó.
- Nhiều câu hỏi hoặc task liên tiếp về cùng một vấn đề chỉ tạo ra một đề xuất. Nếu task sau có thêm thông tin,
  đề xuất cập nhật bài học đã có hoặc đã đề xuất trước đó, không đề xuất một bài học mới.

### 2.2. Điều kiện để ghi

Chỉ cần một trong các điều kiện sau đúng:
1. Root cause khó nhận biết: triệu chứng không thể hiện trực tiếp nguyên nhân, hoặc phải điều tra nhiều bước mới xác định được.
2. Loại bỏ giả thuyết sai: đã kiểm chứng và loại bỏ ít nhất một giả thuyết có vẻ hợp lý.
3. Framework / library / platform behavior: phát hiện behavior, giới hạn hoặc đặc điểm ít hiển nhiên của framework, thư viện, runtime, database hoặc platform.
4. Security finding: lỗ hổng hoặc sai sót trong xác thực, phân quyền, xử lý dữ liệu hay cơ chế bảo mật có khả năng tái diễn.
5. Performance finding: bottleneck hoặc vấn đề về concurrency, memory, connection pool, database hay hiệu năng đã có bằng chứng kiểm chứng.
6. Configuration / environment / data trap: cách sửa phụ thuộc vào cấu hình, môi trường triển khai, phiên bản, dữ liệu hoặc thứ tự thực thi đặc biệt.
7. Reusable engineering pattern: pattern, giải pháp hoặc quy tắc kỹ thuật áp dụng lại được cho nhiều module hoặc task khác.

Chỉ ghi khi kết luận kỹ thuật đủ tin cậy (mục 2.4) và nội dung có giá trị tái sử dụng.

### 2.3. Trường hợp KHÔNG ghi

- Sửa lỗi chính tả, format code hoặc thay đổi cú pháp đơn giản.
- Sửa lỗi trực tiếp, nguyên nhân đã rõ ràng và không phát hiện kiến thức mới.
- Chỉ ghi lại quá trình làm task, danh sách file thay đổi hoặc kết quả build/test.
- Chỉ diễn giải lại documentation chính thức mà không có phát hiện hoặc lưu ý kỹ thuật mới.
- Root cause hoặc giải pháp chưa được xác minh.
- Nội dung đã có trong knowledge và không có thông tin mới đáng kể.

### 2.4. Mức độ xác minh (confidence)

Mỗi bài học phải có trường `confidence` trong frontmatter:
- `verified`: đã reproduce hoặc kiểm chứng thực tế và xác nhận được kết luận.
- `high`: có bằng chứng rõ ràng từ code, log hoặc test nhưng chưa kiểm chứng toàn bộ.
- `hypothesis`: giả thuyết đang điều tra, chưa được xác nhận.

Knowledge base chỉ chứa `verified` và `high`. Không ghi bài học `hypothesis`; nói với người dùng điều gì còn thiếu để xác minh.
Bài học cũ chưa có trường `confidence` vẫn được tra cứu; khi cập nhật bài học đó thì bổ sung trường này.

### 2.5. Chống trùng lặp

Trước khi tạo file mới, tìm bài học liên quan trong đúng ba nơi ở mục 1.
- Đã có bài học cùng root cause: cập nhật bài học đó nếu có thêm thông tin, bằng chứng hoặc cách xử lý có giá trị; không có gì mới thì không ghi.
- Chỉ tạo bài học mới khi root cause khác, hoặc phạm vi áp dụng khác biệt đáng kể.
- Không tạo nhiều bài học chỉ vì cùng một vấn đề xuất hiện ở các module hoặc task khác nhau.
- Nếu lỗi nằm ở code dùng chung đã được clone sang nhiều branch (ví dụ code gốc của các branch khách hàng),
  hỏi người dùng có muốn ghi vào `knowledge/<project-key>/_shared/` (`branch: all`) không, thay vì ghi riêng một bài học ở mỗi branch.
  Bài học chung liệt kê các branch đã xác nhận bị ảnh hưởng hoặc đã sửa.

### 2.6. Nội dung và chất lượng

Ưu tiên ghi:
- Root cause thực sự.
- Vì sao cách tiếp cận thông thường không hiệu quả.
- Điều kiện hoặc hoàn cảnh khiến vấn đề xảy ra.
- Cách xác minh và giải pháp đã được kiểm chứng.
- Phạm vi áp dụng và những trường hợp không nên áp dụng.

Không ghi lại toàn bộ lịch sử debug hoặc nội dung task nếu chúng không giúp giải quyết vấn đề tương tự sau này.

### 2.7. Các bước ghi

1. Nếu không có bài học cùng root cause (mục 2.5), copy `knowledge/_template.md` thành
   `knowledge/<project-key>/<branch-key>/YYYY-MM-DD-short-slug.md` và điền `branch: <tên branch nguyên văn>`.
   - Chỉ ghi vào `knowledge/<project-key>/_shared/YYYY-MM-DD-short-slug.md` (chung cho mọi branch, `branch: all`)
     khi người dùng yêu cầu rõ là ghi cho tất cả branch. Không tự quyết định một bài học là chung cho mọi branch.
   - Chỉ ghi vào `knowledge/common/` khi người dùng yêu cầu rõ là ghi cho mọi project.
2. Điền đầy đủ mọi mục và trường `confidence`. Đưa nguyên văn thông báo lỗi vào `keywords` để có thể tìm thấy bằng tìm kiếm.
   Điền mục "Hướng đi sai" (Dead ends) một cách trung thực, bao gồm cả những hướng sai đã đi trong chính task này.
3. Không bao giờ đưa secret, connection string, token hoặc dữ liệu khách hàng vào bài học.
4. Không commit. Cho người dùng biết đường dẫn file để họ review, commit và push.

## 3. Nâng các bài học lặp lại thành rule

Khi có từ ba bài học trở lên cùng một pattern root cause, đề xuất với người dùng một rule để ngăn lỗi đó.
Chỉ tạo rule khi người dùng đồng ý.

Cách đếm:
- Chỉ đếm các lần lỗi xảy ra ở những chỗ code khác nhau. Cùng một đoạn code bị clone sang nhiều branch chỉ tính là một lần.
- Chỉ tìm pattern lặp lại trên nhiều branch khi người dùng yêu cầu, vì mục 1 chỉ đọc branch hiện tại.

Nơi đặt rule, theo trường `type` của các bài học:

| `type` | Nơi đặt rule |
|---|---|
| `bug` | `rules/bug-fixing/` |
| `performance` | `rules/performance/` |
| `feature` | `rules/feature-development/` |
| `security` | `rules/security/`: bổ sung vào playbook cùng loại lỗ hổng nếu đã có; nếu chưa có thì tạo playbook mới từ `_template.md` và thêm một dòng vào `README.md` |
| `other` | Thư mục phù hợp nhất với nội dung |

Sau khi tạo rule, ghi vào mục "Lần sau" (Next time) của các bài học đó rằng chúng đã được rule này bao phủ.

## Quy ước tiêu đề mục

Các tiêu đề mục trong bài học và playbook được viết theo dạng `Tiếng Việt (English)`, ví dụ `## Hướng đi sai (Dead ends)`.
Khi tham chiếu tới một mục, có thể dùng tên tiếng Việt hoặc tên tiếng Anh trong ngoặc; cả hai cùng chỉ một mục.
Các bài học cũ có tiêu đề chỉ bằng tiếng Anh vẫn hợp lệ.
