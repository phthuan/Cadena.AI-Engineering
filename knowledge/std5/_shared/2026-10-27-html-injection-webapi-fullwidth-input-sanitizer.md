---
title: HTML Injection in ESS Request Leave Remark - WebAPI bodies bypass ASP.NET request validation; chặn bằng global ActionFilter ValidateRequestBodyFilter duyệt ActionArguments (thay cho full-width sanitizer)
project: std5
branch: all
type: security
keywords: [HTML Injection, Hyperlink Injection, CWE-79, CWE-80, Remark, Request Leave, eleave/leave/submit, validateRequest, ValidateRequestBodyFilter, RequestInputScanner, InputContentRules, AllowHtmlInputAttribute, ErrorResultResponse, ActionArguments, WillReadBody, messageReturnType, HtmlInputSanitizer, HtmlInputSanitizingHandler, full-width, U+FF1C, ReplacePlaceholders, form-urlencoded, XmlMediaTypeFormatter, CommandDelegatingHandler]
files: [Cadena HRM 5.0/Services/Cadena.WebAPI/ActionFilters/ValidateRequestBodyFilter.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/ActionFilters/RequestInputScanner.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/ActionFilters/InputContentRules.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/ActionFilters/AllowHtmlInputAttribute.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/ActionFilters/ErrorResultResponse.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/App_Start/WebApiConfig.cs, Cadena HRM 5.0/Modules/Cadena.Modules.ELeave/Scripts/Model/model.requestleave.js]
commit:
date: 2026-10-27
author: Thuan Pham Ngoc
status: active
confidence: verified
---

## Triệu chứng (Symptom)
Pentest (Medium): nhập `<a href="https://...">Click4Surprise</a>` vào Remark ở ESS > Leave Management > Request Leave, bấm Submit.
Payload được lưu và hiện thành link thật trong email duyệt phép và màn Leave History.

## Nguyên nhân gốc (Root cause)
- WebForms bật `<pages validateRequest="true">`, nhưng màn ESS gửi qua jQuery tới WebAPI (`eleave/leave/submit`); WebAPI tự đọc body nên
  request validation của ASP.NET không áp dụng.
- Hiển thị: email dùng `ASPxHtmlEditor.ReplacePlaceholders` chèn thẳng `Remark`/`Reason` vào template HTML (17 chỗ);
  ESS JS dùng `.html(item.remark)` (ELeave, EOvertime, ETraining).
- Kiểm tra body thô bị bypass bằng JSON escape `<`, form `%3C`, XML `&lt;`, hoặc đổi Content-Type sang text/plain
  (CommandDelegatingHandler/QueryDelegatingHandler/DynamicCommand đọc body như JSON bất kể header).
- WebApiConfig không gỡ XmlMediaTypeFormatter: body `application/xml` được giải mã `&lt;a&gt;` thành `<a>` khi bind.
- ESS chỉ hiển thị lỗi qua `showMeassage` khi HTTP 200; `request.fail` 400 không có listener (`eventSubmitRequestLeaveError`).
- Route chung MobileApp (`GeneralApi`, template rỗng): `CommandDelegatingHandler` tự đọc body và gọi `mediator.Execute`
  (CommandDelegatingHandler.cs:57-84), không tới controller, nên ActionFilter KHÔNG chạy cho MobileApp.

## Cách sửa (Fix)
- `ValidateRequestBodyFilter` (global, `config.Filters.Add` trong WebApiConfig), port từ master và sửa lỗi: duyệt `actionContext.ActionArguments`
  (giá trị đã bind và đã decode) bằng reflection nên chặn được JSON escape, form `%3C`, XML `&lt;` mà không cần đọc lại body.
  Body: chỉ tham số có `ParameterBinding.WillReadBody == true`. Query string: `Request.GetQueryNameValuePairs()` (đã decode), kiểm tra cả key và value.
  Route value và header không bị kiểm tra.
- Bỏ qua field credential theo từ ở đoạn cuối tên field (`ConfirmPassword`, `access_token`, đuôi `newpwd`); `SecretaryRemark` vẫn bị kiểm tra.
- `[AllowHtmlInput]` trên property DTO (chỉ bỏ qua field đó, gồm object con) hoặc trên action/controller (bỏ qua cả request, kể cả query).
  Field được phép HTML phải sanitize theo whitelist ở server trước khi lưu. ASPxHtmlEditor của WebForms lưu bằng postback nên không bị ảnh hưởng.
- Response khi chặn: HTTP 200, `messageReturnType: 2` + `contentResult`, ở top-level và dưới mọi key bao (`submitResult`, `cancelResult`, `result`, `updateResult`...).
- Chặn câu lệnh SQL (theo yêu cầu, chỉ là lớp phụ; chống SQL injection thật vẫn là parameterized query): regex bắt cấu trúc câu lệnh
  (`SELECT cols FROM x`, `INSERT INTO x`, `UPDATE x SET c =`, `DELETE FROM x`, `DROP/TRUNCATE/ALTER TABLE x`, `UNION SELECT`, `EXEC(`,
  `OR 1=1`, `'--`, `'; drop`, `waitfor delay`, `xp_cmdshell`), không bắt từ đơn. Chặn nhầm đã biết: câu tiếng Anh dạng "select one from list".
- `Log` (Cadena.Core) ném exception ở static ctor nếu thiếu section `cadena/logging`: bọc try/catch khi log trong filter.

## Kiểm chứng (Verification)
- MSBuild Cadena.WebAPI.csproj thành công.
- Harness HttpServer in-memory gọi DLL đã build: 49/49 pass — chặn JSON, `<`, form `%3C`, XML, list lồng, JObject, Dictionary,
  query value/key, 18 case SQL; cho qua `5 < 10` ở body và query, `#`/SELECT trong text thường, password, `access_token` trong query,
  header, `[AllowHtmlInput]`, ký tự full-width, object vòng.
- CHƯA test trên IIS và MobileApp; không chạy cho `api/commands`/`api/queries` (chỉ `AddEmloyeeCommand` dùng).

## Hướng đi sai (Dead ends)
- Full-width sanitizer (thay `<` `>` bằng `＜` `＞` trong DelegatingHandler, cho người dùng đi tiếp): đã gỡ, đổi sang chặn.
  Bài học từ bản này: kiểm tra nhanh phải tìm cả `<`; không lọc theo Content-Type khai báo; parse JSON cần
  DateParseHandling.None + FloatParseHandling.Decimal để không đổi format ngày khi ghi lại; `string.Normalize(FormKC/FormKD)` đổi `＜` lại thành `<`.
- Filter gốc của master: kết quả regex HTML không được return (không bao giờ chặn); kiểm tra body thô nên bị bypass;
  regex SQL (`'...#`, `#`) chặn nhầm text thường; trả 400 nên ESS không hiện gì.
- ActionFilter kiểm tra body thô hoặc DelegatingHandler riêng theo route: bỏ sót route động `api/commands/{command}`, `api/queries/{query}`.
- Chỉ xử lý JSON: màn Request Leave gửi `data: item` của jQuery, tức form-urlencoded (`leaveAssignment[remark]=...`).
- Encode toàn bộ input thành `&lt;`/`&amp;` lúc lưu: encode hai lần ở grid, report, export, MobileApp (vốn tự encode) và tràn cột nvarchar.
- Loại trừ field credential theo chuỗi con (`IndexOf("secret")`): bỏ sót field như `SecretaryRemark`.
- `%u003C` trong form không phải bypass: FormUrlEncodedMediaTypeFormatter không giải mã `%uXXXX` (giống WebUtility.UrlDecode);
  đừng dùng HttpUtility.UrlDecode (nó giải mã `%u`) để tránh lệch với Web API.

## Lần sau (Next time)
- Lỗi HTML/XSS từ màn ESS: kiểm tra ValidateRequestBodyFilter trước (WebApiConfig.Register); WebForms: validateRequest trong Cadena.WebApp/Web.config.
- Muốn phủ MobileApp: kiểm tra `commandJsonData` (JObject) trong CommandDelegatingHandler bằng cùng `RequestInputScanner`.
- Chưa được bảo vệ: tham số gọi hub SignalR, import Excel, và dữ liệu đã lưu trước khi sửa
  (tìm bằng SELECT cột Remark/Reason/... LIKE N'%<[a-zA-Z!/?]%'). Phía hiển thị (email template, `.html()`) vẫn cần output encoding.
