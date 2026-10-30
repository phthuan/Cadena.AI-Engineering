---
title: WAF chặn IP vì request *.js.map (bootstrap.min.js.map, toastr.js.map, autonumeric.min.js.map) - do comment sourceMappingURL, không phải do file .map
project: std5
type: security
keywords: [js.map, css.map, sourceMappingURL, WAF, web application firewall, poor reputation, bootstrap.min.js.map, toastr.js.map, autonumeric.min.js.map, source map, requestFiltering, fileExtensions]
files: [Cadena.WebApp/Content/Bootstrap5.3/js/bootstrap.min.js, Cadena.WebApp/Content/toastr/toastr.min.js, Cadena.WebApp/Scripts/libs/autoNumeric.min.js, Cadena.WebApp/Web.config, Cadena.JobPortal/Web.config, Cadena.WebApp/Cadena.WebApp.csproj]
commit:
date: 2026-10-27
author: Thuan Pham Ngoc
status: active
---

## Triệu chứng (Symptom)
Security team khách hàng (OOCL) báo IP công ty bị WAF chặn nhiều lần, yêu cầu "remove all *.js.map files". Các URL ví dụ:
`/content/bootstrap5.3/js/bootstrap.min.js.map`, `/content/toastr/toastr.js.map`, `/scripts/libs/autonumeric.min.js.map`.

## Nguyên nhân gốc (Root cause)
Ba file .map đó KHÔNG tồn tại trong source/deploy. Request phát sinh vì các file vendor `.min.js`/`.css` có dòng cuối
`//# sourceMappingURL=xxx.map` (CSS: `/*# sourceMappingURL=... */`, jQuery cũ: `//@ sourceMappingURL=`).
Trình duyệt chỉ đi lấy file .map khi DevTools (F12) đang mở -> 404 -> WAF đếm vi phạm.
Web.config đặt clientCache max-age 365 ngày nên trình duyệt giữ bản JS cũ (còn comment) rất lâu.

## Cách sửa (Fix)
1. Xóa dòng comment sourceMappingURL (chỉ dòng bắt đầu bằng `//# `, `//@ `, `/*# sourceMappingURL=`) trong 64 file JS/CSS. Giữ nguyên encoding/BOM/CRLF (dùng `sed -b`, kiểm `git diff --numstat` = 0 thêm / 1 xóa mỗi file).
2. `git rm` 40 file source map + xóa `<Content Include="...map">` trong 4 csproj (WebApp, JobPortal, ECompetency, WebApplication1). Thiếu bước csproj thì publish lỗi.
3. Web.config (WebApp, JobPortal): `requestFiltering/fileExtensions` `<remove fileExtension=".map"/><add fileExtension=".map" allowed="false"/>` (remove trước để tránh 500.19 duplicate).
4. Cache-busting: thêm `?v=<version>` vào thẻ script/link của các file đã sửa trong WebApp (.aspx/.ascx/.html). JobPortal dùng BundleConfig nên bundle tự đổi hash.

## Kiểm chứng (Verification)
- `git grep` không còn dòng sourceMappingURL comment; XML Web.config + csproj parse OK.
- Chưa build/chạy app trong tác vụ này: cần test thủ công tab Network (không còn request .map, không 404 file js/css) trên Login, Main, BasicForm, ESSBasicForm, ESS Main, PendingAction mobile, MFA.

## Hướng đi sai (Dead ends)
- Chỉ xóa file .map như khách yêu cầu: không có tác dụng vì các file .map bị request vốn không tồn tại.
- Chặn .map ở IIS: chỉ ngăn server trả file, request vẫn đi qua WAF.
- KHÔNG xóa `Web References/AcumaticaAPI/Reference.map`: đó là file Web Reference (MSDiscoCodeGenerator), không phải source map.

## Lần sau (Next time)
Khi WAF/scan báo *.map: `git grep -n "sourceMappingURL" -- '*.js' '*.css'`, gỡ comment, thêm cache-busting.
Khi nâng cấp thư viện vendor (bootstrap, toastr, autoNumeric, popper...), gỡ comment sourceMappingURL trước khi commit.
Cache-busting phải quét cả `Modules/**/Views/*.ascx` (khoảng 300 include, render dưới URL gốc của WebApp, có dạng `<%= ResolveUrl("~/...") %>`), không chỉ Cadena.WebApp - lần đầu bị bỏ sót.
Uy tín IP xấu không tự hết, phải nhờ security khách hàng reset/whitelist.
