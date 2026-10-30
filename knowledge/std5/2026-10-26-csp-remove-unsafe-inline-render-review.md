---
title: CSP không dùng unsafe-inline - nonce được thêm vào mọi script sau khi render, csp-inline-fix.js bật lại inline handler; review performance và UX
project: std5
type: other
keywords: [unsafe-inline, csp_nonce, Content-Security-Policy, HtmlResponseRewriter, BasePage.Render, csp-inline-fix.js, migrateInlineEventsToListeners, allControlConvertInlineEventToListener, JavascriptUrlReplacement, Report-To]
files: [Cadena HRM 5.0/Cadena.WebApp/Global.asax.cs, Cadena HRM 5.0/Cadena.Web/Framework/BasePage.cs, Cadena HRM 5.0/Cadena.Web/Framework/HtmlResponseRewriter.cs, Cadena HRM 5.0/Cadena.WebApp/Scripts/csp-inline-fix.js, Cadena HRM 5.0/Cadena.WebApp/Scripts/devexpress-csp-fix.js, Cadena HRM 5.0/Cadena.WebApp/Web.config]
commit:
date: 2026-10-26
author: Thuan Pham Ngoc (with Claude)
status: active
---

## Triệu chứng (Symptom)
Câu hỏi review: thay đổi cách render HTML để bỏ 'unsafe-inline' khỏi script-src có làm ảnh hưởng tới performance hoặc trải nghiệm người dùng không?

## Nguyên nhân gốc (Root cause)
Cách thiết lập CSP hoạt động:
- Application_BeginRequest trong Global.asax gửi `script-src 'self' 'nonce-X' 'unsafe-eval' ...` ở mọi request và lưu nonce vào Request.Headers["csp_nonce"].
- BasePage.Render (HtmlResponseRewriter) thêm nonce vào mọi <script> trong trang đã render, sau khi render.
- Scripts/csp-inline-fix.js chạy ở window load. Nó biến mọi attribute on* inline và mọi href="javascript:" thành addEventListener(new Function(code)), cách này chỉ chạy được nhờ 'unsafe-eval'.

Các phát hiện:
- Chi phí phía server không phải vấn đề. Đo bằng csc /optimize+ trên một Cadena.Web.dll bản Debug, với HTML tổng hợp 0.5 / 2 / 5 MB ký tự:
  - regex cũ: 18.7 / 76.9 / 195.9 ms, cấp phát 6.7 / 27.4 / 68.4 MB
  - HtmlResponseRewriter: 8.3 / 35.0 / 88.9 ms, cấp phát 2.8 / 11.1 / 27.7 MB
  - Sink của benchmark là một StringBuilder, nên một phần allocation mới là của sink.
  - TTFB không thay đổi, vì ASP.NET mặc định buffer response.
- Rủi ro UX nằm ở phía client:
  - Inline handler không làm gì cho tới window.load (click "chết" trong khi một trang nặng đang tải).
  - Toàn bộ document bị quét lại sau mỗi UpdatePanel endRequest, mỗi DevExpress EndCallback và mỗi mutation `disabled`.
  - `return false` trong handler không còn hủy được hành động mặc định.
  - Code onblur gốc bị bỏ mất.
  - Một `function onblur` toàn cục trở thành window.onblur.
  - `allControlConvertInlineEventToListener(rootDoc)` bỏ qua rootDoc và quét `document`.
- BasicForm và ForgotPassword thay thế href="javascript:..." ở phía server (JavascriptUrlReplacement), nên bộ chuyển đổi phía client không bao giờ thấy các link đó và hành động của chúng bị mất.
- Các trang không tải csp-inline-fix.js giữ lại inline handler mà CSP chặn: Form.aspx, PayTimeMain(Cloud).aspx, MasterDataFormEdit.aspx, RptBasicForm.aspx, TransactionDetailView.aspx.
- Các trang không kế thừa BasePage hoàn toàn không có nonce: FormView.aspx và Security/*.aspx, là các trang DevExpress nặng.
- Security: nonce được thêm vào sau đó cho mọi script, kể cả script bị inject, và client chuyển mọi inline handler hoặc URL javascript: thành code. Vì vậy stored hoặc reflected XSS vẫn chạy, nên mức bảo vệ thực tế gần như tương đương 'unsafe-inline'.
- Header Report-To trong Web.config dùng dấu nháy đơn, là JSON không hợp lệ, nên báo cáo vi phạm CSP nhiều khả năng không bao giờ tới nơi. Team không thể thấy những gì bị hỏng với người dùng.

Lượt thứ hai, review UI của csp-inline-fix.js:
- Handler dựng bằng `new Function(code)` bỏ qua `return false`. Trường hợp đã xác nhận: `<button onclick="return false;">` không có type, bên trong form WebForms, trong ESSMyPerformanceNewView.ascx và ESSMyProbationaryEvaluationView.ascx (6 chỗ). Click vào nó giờ sẽ submit form.
- Listener không bao giờ bị gỡ. Khi DevExpress SetEnabled xóa hoặc thêm lại attribute onclick, kết quả nhiều khả năng là một control bị disable nhưng vẫn phản hồi, hoặc một handler chạy hai lần. Cần test trên trình duyệt.
- Phần override innerHTML thêm nonce vào các thẻ <script> bên trong markup của HTML editor. Khi đó HTML do người dùng soạn có thể chạy script.

- Phần thay thế URL javascript: của HtmlResponseRewriter (và regex cũ trước nó) chỉ khớp với chuỗi nguyên văn "javascript:" có dấu nháy. Trình duyệt còn chấp nhận dạng entity-encode (`&#106;avascript:`), dạng tách bằng tab (`java&#9;script:`) và dạng không có dấu nháy. Hãy coi nó là một lớp đệm (shim) cho UX, không bao giờ coi là cơ chế kiểm soát XSS (xem rules/security/html-injection-xss.md, mục Cách sửa sai (Wrong fixes)).

## Cách sửa (Fix)
Chưa sửa (chỉ review). Thứ tự khuyến nghị:
1. Làm cho việc báo cáo vi phạm hoạt động: JSON hợp lệ cùng Reporting-Endpoints và report-uri.
2. Trong csp-inline-fix: chạy ở DOMContentLoaded, tôn trọng `return false` và argument `event`, sửa bug rootDoc, và giới hạn việc quét lại trong panel hoặc control vừa được cập nhật.
3. Thêm script sửa lỗi vào các trang đang thiếu.
4. Ngừng thay thế href="javascript:" ở phía server.
5. Dài hạn: chỉ thêm nonce cho các script mà ứng dụng tự đăng ký, và whitelist các pattern handler được chuyển đổi.

## Kiểm chứng (Verification)
- Benchmark đã được chạy như mô tả ở trên.
- Mọi thứ khác đến từ việc đọc code. Chưa test trên trình duyệt, chưa kiểm tra log vi phạm CSP.

## Hướng đi sai (Dead ends)
- Giả định header csp_nonce có thể bị client inject. Đã loại trừ: Global.asax ghi đè Request.Headers["csp_nonce"] ở mọi request.

## Lần sau (Next time)
Với mọi câu hỏi về CSP hoặc nonce, đọc Application_BeginRequest trong Global.asax và Scripts/csp-inline-fix.js trước BasePage.Render. Hành vi mà người dùng thấy được quyết định ở phía client, không phải phía server.
