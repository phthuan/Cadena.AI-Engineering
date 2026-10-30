---
title: HTML Injection in ESS Request Leave Remark - WebAPI bodies bypass ASP.NET request validation; fixed with a global full-width input sanitizer
project: std5
type: security
keywords: [HTML Injection, Hyperlink Injection, CWE-79, CWE-80, Remark, Request Leave, eleave/leave/submit, validateRequest, HtmlInputSanitizer, HtmlInputSanitizingHandler, DelegatingHandler, MessageHandlers, full-width, U+FF1C, ReplacePlaceholders, form-urlencoded]
files: [Cadena HRM 5.0/Cadena.Library/Security/HtmlInputSanitizer.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/DelegatingHandlers/HtmlInputSanitizingHandler.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/App_Start/WebApiConfig.cs, Cadena HRM 5.0/Modules/Cadena.Modules.ELeave/Scripts/Model/model.requestleave.js]
commit:
date: 2026-10-27
author: Thuan Pham Ngoc (with Claude)
status: active
---

## Triệu chứng (Symptom)
Pentest (Medium): nhập `<a href="https://...">Click4Surprise</a>` vào Remark ở ESS > Leave Management > Request Leave, bấm Submit.
Payload được lưu và hiện thành link thật trong email duyệt phép và màn Leave History.

## Nguyên nhân gốc (Root cause)
- WebForms đã bật `<pages validateRequest="true">`, nên form post có HTML bị ASP.NET chặn.
  Nhưng màn ESS gửi qua jQuery tới WebAPI (`eleave/leave/submit`), và WebAPI tự đọc body nên request validation không áp dụng.
- Phía hiển thị: email dùng `ASPxHtmlEditor.ReplacePlaceholders` chèn thẳng `Remark`/`Reason` vào template HTML (17 chỗ);
  ESS JS dùng `.html(item.remark)` vào div/span (ELeave, EOvertime, ETraining).

## Cách sửa (Fix)
Theo yêu cầu: chỉ xử lý input từ UI, không báo lỗi, cho người dùng đi tiếp.
- `HtmlInputSanitizer` (Cadena.Library): khi giá trị có `<` theo sau là chữ, `!`, `/` hoặc `?` (cùng quy tắc với ASP.NET),
  thay mọi `<` `>` trong giá trị đó bằng `＜` `＞` (U+FF1C/U+FF1E). Độ dài không đổi nên không tràn cột nvarchar(250).
  Bỏ qua field mật khẩu/token: chỉ xét đoạn cuối của tên field, khớp theo từ (`ConfirmPassword`, `access_token`)
  hoặc đuôi tên (`newpwd`); `SecretaryRemark` vẫn được lọc. `5 < 10`, `Tom & Jerry` giữ nguyên.
- `HtmlInputSanitizingHandler`: global DelegatingHandler trong `config.MessageHandlers` (WebApiConfig.Register).
  Form-urlencoded thì xử lý theo form; body JSON thì xử lý bất kể Content-Type (kể cả text/plain hoặc không có header);
  bỏ qua multipart/binary. Giữ nguyên Content-Type gốc khi ghi lại body.
- Bypass đã chặn (phát hiện khi review):
  - JSON escape `<...>`: bước kiểm tra nhanh phải tìm cả `<`, không chỉ `<`.
  - Đổi Content-Type sang text/plain: CommandDelegatingHandler/QueryDelegatingHandler/DynamicCommand đọc body như JSON bất kể header.
- `%u003C` trong form KHÔNG phải bypass: đã kiểm chứng FormUrlEncodedMediaTypeFormatter (ReadAsFormDataAsync) không giải mã `%uXXXX`,
  giống WebUtility.UrlDecode. Không dùng HttpUtility.UrlDecode (nó giải mã `%u`) để tránh lệch với Web API.
- Lý do chọn full-width thay vì `&lt;`: encode lúc lưu làm grid, report, export và MobileApp (vốn tự encode) hiện `&amp;`/`&lt;`
  và có thể tràn độ dài cột.

## Kiểm chứng (Verification)
- MSBuild Cadena.WebAPI.csproj kèm references: thành công.
- Harness console (không có project test trong repo) gọi DLL đã build: 57/57 pass. Gồm payload của playbook, dữ liệu hợp lệ,
  password giữ nguyên, ngày và decimal trong JSON giữ nguyên, các cặp form khác giữ nguyên từng byte, handler thật trong pipeline HttpMessageInvoker,
  và các case bypass `<`, text/plain, không Content-Type, multipart, `%u003C`, tên field credential.
- Chưa test end-to-end trên IIS.

## Hướng đi sai (Dead ends)
- ActionFilter: bỏ sót route động `api/commands/{command}`, `api/queries/{query}` và route chung của MobileApp (DelegatingHandler riêng theo route).
- Chỉ xử lý JSON: màn Request Leave gửi `data: item` của jQuery, tức là form-urlencoded (`leaveAssignment[remark]=...`).
- Encode toàn bộ input thành `&lt;`/`&amp;`: hiện encode hai lần ở các màn đã tự encode, và làm tràn cột.
- Parse JSON bằng setting mặc định của Newtonsoft: ngày bị đổi format khi ghi lại. Cần DateParseHandling.None và FloatParseHandling.Decimal.
- Chỉ lọc theo Content-Type khai báo, và kiểm tra nhanh chỉ tìm `<`: bị bypass bằng text/plain và `<` (xem Cách sửa).
- Loại trừ field credential theo chuỗi con (`IndexOf("secret")`): bỏ sót field như `SecretaryRemark`.

## Lần sau (Next time)
- Lỗi HTML/XSS từ màn ESS hoặc MobileApp: kiểm tra handler này trước (WebApiConfig.Register).
  WebForms: kiểm tra validateRequest trong Cadena.WebApp/Web.config.
- Chưa được bảo vệ: query string, tham số gọi hub SignalR, import Excel, và dữ liệu đã lưu trước khi sửa
  (dùng script SELECT tìm cột Remark/Reason/... LIKE N'%<[a-zA-Z!/?]%').
- Không dùng string.Normalize(FormKC/FormKD) trên dữ liệu người dùng: nó đổi `＜` lại thành `<`.
- Review 2026-10-28 (chưa kiểm chứng): WebApiConfig không gỡ XmlMediaTypeFormatter mặc định của Web API.
  Body `application/xml`/`text/xml` không phải JSON/form nên handler bỏ qua, mà XML formatter lại giải mã `&lt;a&gt;` thành `<a>`
  khi bind vào action có tham số body. Kiểm tra bằng POST XML tới một controller action; nếu bypass được thì
  gỡ XmlFormatter (`config.Formatters.Remove(config.Formatters.XmlFormatter)`) hoặc lọc cả XML.

## Cập nhật 2026-10-28: đổi sang CHẶN (thay cho full-width sanitizer)
- Handler/sanitizer ở trên đã bị gỡ. Thay bằng `Services/Cadena.WebAPI/ActionFilters/ValidateRequestBodyFilter.cs`
  (global, `config.Filters.Add` trong WebApiConfig), port từ master và sửa lỗi. Cùng thư mục: `HtmlInputDetector.cs`
  (tìm field có HTML), `ErrorResultResponse.cs` (response 200 + messageReturnType), `AllowHtmlInputAttribute.cs`.
- Filter master có bug: kết quả regex HTML không được return (HTML không bao giờ bị chặn); kiểm tra body thô nên
  bị bypass bằng `<`/`%3C`; regex SQL (`'...#`, `#`) chặn nhầm text thường; trả 400 nên ESS không hiện gì.
- Cách mới: duyệt `actionContext.ActionArguments` (giá trị đã bind và đã decode) bằng reflection, nên chặn được
  JSON escape, form `%3C`, XML `&lt;`, mà không cần đọc lại body. Bỏ qua field credential, cho phép bằng `[AllowHtmlInput]`.
  Body: chỉ xét tham số có `ParameterBinding.WillReadBody == true`. Query string: duyệt `Request.GetQueryNameValuePairs()`
  (đã decode `%3C`), kiểm tra cả key và value, bỏ qua tên field credential. Route value và header không bị kiểm tra.
  Lưu ý: `token` trong danh sách loại trừ là tên field trong body (`access_token`), không phải validate token ở header.
- Response khi chặn: HTTP 200, `messageReturnType: 2` + `contentResult`, đặt ở top-level và dưới mọi key bao
  (`submitResult`, `cancelResult`, `result`, `updateResult`...), vì ESS chỉ hiện lỗi qua `showMeassage` với HTTP 200;
  `request.fail` 400 không có listener (`eventSubmitRequestLeaveError`). Message là hằng `RejectMessage` trong filter (không dùng config).
- `Log` (Cadena.Core) ném exception ở static ctor nếu thiếu section `cadena/logging`: bọc try/catch khi log trong filter.
- `[AllowHtmlInput]` gắn được trên property của DTO (khuyến nghị, giống `[AllowHtml]` của MVC: chỉ bỏ qua field đó,
  gồm cả object con nếu gắn trên property kiểu object) hoặc trên action/controller (bỏ qua cả request, kể cả query).
  Gắn trên property không bỏ qua query string. Field được phép HTML phải sanitize theo whitelist ở server trước khi lưu.
  WebForms ASPxHtmlEditor (Email template, Recruitment, Job) lưu bằng postback, không qua WebAPI nên filter không ảnh hưởng.
- Thêm chặn câu lệnh SQL (theo yêu cầu): file `InputContentRules.cs` (regex HTML + SQL), `RequestInputScanner.cs` (thay HtmlInputDetector:
  duyệt body/query, bỏ qua credential, nhận `Func<string,string>` trả message lỗi), `InvalidInput.cs` (FieldPath + Message).
  Regex SQL bắt cấu trúc câu lệnh, không bắt từ đơn: `SELECT cols FROM x`, `INSERT INTO x`, `UPDATE x SET c =`, `DELETE FROM x`,
  `DROP/TRUNCATE/ALTER TABLE x`, `UNION SELECT`, `EXEC(`/`exec xp_`/`sp_`/`@`, `OR 1=1`/`' or '1'='1` (nháy đóng không bắt buộc),
  `'--`, `'; drop`, `waitfor delay`, `xp_cmdshell`. Cho qua: "please select the leave type from the list", "update address set later",
  "Tom and Jerry", `It's item #5`. Chặn nhầm đã biết: câu tiếng Anh dạng "select one from list".
  `[AllowHtmlInput]` bỏ qua cả kiểm tra SQL cho field/action được gắn. Đây chỉ là lớp phụ; chống SQL injection thật vẫn là parameterized query.
- Kiểm chứng: harness 49/49 pass (thêm 18 case SQL). Trước đó: harness HttpServer in-memory gọi DLL đã build, 33/33 pass (có thêm 4 case `[AllowHtmlInput]` trên field); trước đó 29/29 pass (chặn: JSON, `<`, form `%3C`, XML, list lồng, JObject,
  Dictionary, query value/key; cho qua: `5 < 10` ở body và query, `#`/SELECT trong text, password, `access_token` trong query,
  header, `[AllowHtmlInput]`, full-width, object vòng).
- Không chạy cho `api/commands`/`api/queries` (chỉ `AddEmloyeeCommand` dùng). Chưa test trên IIS và MobileApp.
- Review 2026-10-28: route chung MobileApp (`GeneralApi`, template rỗng) có `CommandDelegatingHandler` tự đọc body và gọi
  `mediator.Execute` ngay trong handler (CommandDelegatingHandler.cs:57-84), không tới controller, nên ActionFilter KHÔNG chạy cho MobileApp.
  Muốn phủ MobileApp: kiểm tra `commandJsonData` (JObject) trong CommandDelegatingHandler bằng cùng `RequestInputScanner`.
