# HTML Injection / HTML Hyperlink Injection / XSS

## Nhận diện (Recognize)
- Tên trong báo cáo / scanner: HTML Injection, HTML Hyperlink Injection, Link Injection, Content Spoofing,
  Reflected XSS, Stored XSS, DOM-based XSS, Email HTML Injection.
- CWE / OWASP: CWE-79, CWE-80, CWE-116; OWASP A03 Injection.
- Triệu chứng: một giá trị như `<a href="https://evil.example">Click</a>` hoặc `<b>x</b>` nhập vào một field
  bị hiển thị thành HTML thật trong trang, email, PDF, báo cáo hoặc notification thay vì hiển thị dạng text.
  Hyperlink injection hay gặp trong email: tên, tiêu đề, comment hoặc message được chèn vào HTML template.

## Nguồn dữ liệu (Sources)
- Các field của request DTO: Name, Title, Description, Comment, Message, Note, DisplayName, FileName, Email, Url.
- Giá trị query string và route bị phản hồi ngược lại (từ khóa tìm kiếm, thông báo lỗi, returnUrl).
- Dữ liệu do bất kỳ người dùng nào lưu trước đó và hiển thị sau (stored): groups, documents, user profiles, comments.
- File import (Excel/CSV) và response từ API bên thứ ba.

## Sink và mẫu tìm kiếm (Sinks and search patterns)
- C# dựng chuỗi HTML (email, notification, export):
  `$"<`, `"<a href`, `string.Format("<`, `StringBuilder.Append("<`, `.Replace("{{`, `.Replace("[`,
  `IsBodyHtml = true`, `MailMessage`, `Body =`, template engine (`Razor.Parse`, `RazorEngine`, `Scriban`, `Handlebars`).
- Razor / MVC: `Html.Raw(`, `@Html.Raw`, `MvcHtmlString.Create(`, `new HtmlString(`, `IHtmlContent`.
- WebForms: `Response.Write(`, `.InnerHtml =`, `<%= ` (không phải `<%: `), `Literal` với `Mode="PassThrough"`,
  `Label.Text =` / `LiteralControl(` với dữ liệu người dùng, `ClientScript.RegisterStartupScript` với dữ liệu người dùng.
- Web API trả về HTML hoặc nội dung `text/html`; thông báo lỗi phản hồi lại input.
- JavaScript: `.innerHTML`, `.outerHTML`, `insertAdjacentHTML`, `document.write`, jQuery `.html(`, `.append(`
  với chuỗi, `$("<` + dữ liệu, `v-html`, `dangerouslySetInnerHTML`, `[innerHTML]`, DevExpress templates.
- Thuộc tính URL: `href=`, `src=`, `window.location =`, `location.href` được dựng từ dữ liệu (URL `javascript:`).
- Bộ sinh PDF / báo cáo nhận input là HTML.

## Cách sửa đúng (Correct fix)
Encode tại sink, theo đúng ngữ cảnh nơi giá trị được ghi ra:
- HTML body hoặc attribute: `System.Net.WebUtility.HtmlEncode` / `HttpUtility.HtmlEncode`,
  hoặc `System.Text.Encodings.Web.HtmlEncoder.Default.Encode`. Luôn đặt attribute trong dấu nháy.
- Razor `@value` và WebForms `<%: value %>` đã tự encode: hãy bỏ `Html.Raw` / `<%=` thay vì thêm encode thủ công.
- URL trong `href`/`src`: parse bằng `Uri.TryCreate(..., UriKind.Absolute)`, chỉ cho phép `http`/`https`
  (và `mailto` nếu cần) cùng các host mong đợi, sau đó HTML-encode. Query parameter: `Uri.EscapeDataString`.
- Chuỗi JavaScript: `JavaScriptEncoder.Default.Encode` hoặc serialize bằng JSON serializer; trong JS dùng
  `textContent`, `innerText`, jQuery `.text(`, `setAttribute` thay vì chuỗi HTML.
- Email template: encode mọi giá trị placeholder; chỉ dựng link từ base URL tin cậy cộng với ID đã encode.
- Field hợp lệ chứa rich text: sanitize bằng allowlist sanitizer (ví dụ HtmlSanitizer / Ganss.Xss)
  khi lưu và khi hiển thị; không bao giờ chỉ dựa vào encode cho các field này.
- Validation input là lớp phòng thủ bổ sung (defense in depth), không phải cách sửa chính: giới hạn độ dài và ký tự cho tên và mã
  (ví dụ từ chối `<` và `>` trong tên group) bằng validator của project (FluentValidation / DataAnnotations).
- Đặt logic encode trong một helper dùng chung khi project dựng HTML ở nhiều nơi.

## Cách sửa sai (Wrong fixes)
- Thay thế `<script>` hoặc một danh sách tag/từ (blacklist): bị bypass bởi `<a>`, `<img onerror>`, thủ thuật chữ hoa/thường và encoding.
- Chỉ validate ở front-end.
- Encode khi lưu rồi encode lại khi hiển thị (double encoding khiến người dùng thấy `&amp;lt;`).
- HTML-encode một giá trị đặt trong ngữ cảnh JavaScript hoặc URL (sai ngữ cảnh).
- Xóa toàn bộ HTML khỏi một field rich text mà người dùng đang cần.
- Tắt request validation hoặc CSP cho chạy được.

## Payload kiểm thử (Test payloads)
| Payload | Kết quả mong đợi sau khi sửa |
|---|---|
| `<a href="https://example.com">Click here</a>` | Hiển thị dạng text nguyên văn; không có link trong trang hoặc email |
| `<b>bold</b>` | Text nguyên văn |
| `"><img src=x onerror=alert(1)>` | Text nguyên văn; không có ảnh, không chạy script |
| `<script>alert(1)</script>` | Text nguyên văn |
| `javascript:alert(1)` trong field URL | Bị từ chối hoặc không hiển thị thành link |
| `Tom & Jerry's "Group"` (hợp lệ) | Được lưu và hiển thị đúng như đã nhập, không hiện `&amp;` |
| Tên Unicode `Nhóm Kế toán` (hợp lệ) | Không thay đổi |

## Kiểm chứng (Verification)
- Unit test cho encoder/helper và cho từng template/handler với các payload ở trên.
- Kiểm tra mọi kênh hiển thị giá trị: trang web, body và subject email, PDF, export, notification, API consumer.
- Kiểm tra dữ liệu đã lưu có chứa HTML: giờ phải hiển thị dạng text.
- Để retest: gửi cho đội pentest danh sách endpoint và field đã sửa, cùng các payload đã dùng.

## Bài học liên quan (Related lessons)
- knowledge/std5/2026-10-26-csp-remove-unsafe-inline-render-review.md (CSP nonce không ngăn được stored XSS).
