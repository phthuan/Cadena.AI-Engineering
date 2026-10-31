---
title: Chrome 156 báo hàng trăm lỗi CSP "Executing inline event handler violates..." ngay khi load trang, Chrome 155 không báo
project: std5
type: bug
keywords: [Executing inline event handler violates the following Content Security Policy directive, unsafe-inline, unsafe-hashes, nonce, Chrome 156, 156.0.8078.73, 155.0.8059.85, csp-inline-fix.js, migrateInlineEventsToListeners, onclick, onmouseover]
files: [Cadena HRM 5.0/Cadena.WebApp/Scripts/csp-inline-fix.js, Cadena HRM 5.0/Cadena.WebApp/Global.asax.cs, Cadena HRM 5.0/Cadena.Web/Framework/HtmlResponseRewriter.cs]
commit:
date: 2026-10-30
author: Thuan Pham Ngoc
status: active
---

## Triệu chứng (Symptom)
Sau khi update Chrome lên 156.0.8078.73, console có hàng trăm lỗi
"Executing inline event handler violates the following Content Security Policy directive 'script-src 'self' 'nonce-...' 'unsafe-eval''".
Chrome 155.0.8059.85 không báo. Code và CSP không đổi.

## Nguyên nhân gốc (Root cause)
Chrome 156 báo vi phạm CSP ngay khi một attribute on* được gắn vào DOM (lúc parse HTML, khi chèn bằng innerHTML, khi gọi setAttribute),
không còn đợi tới lúc event thực sự xảy ra. Chrome 155 chỉ báo khi handler bị gọi. CSP không có 'unsafe-inline'
(xem [[2026-10-26-csp-remove-unsafe-inline-render-review]]), và csp-inline-fix.js chỉ chuyển on* sang addEventListener ở window.load.
Vì vậy mọi attribute on* đều bị báo lỗi trước khi script kịp chuyển.
Chức năng không đổi: handler inline vốn đã bị chặn ở cả hai phiên bản, và listener tạo bằng new Function vẫn chạy.

## Cách sửa (Fix)
Không dùng `script-src-attr 'unsafe-inline'` (đã test là hết lỗi, nhưng pentest sẽ báo lại unsafe-inline). Đã sửa (2026-10-31):
- Cadena.Web/Framework/InlineEventHandlerRewriter.cs: regex `(\s)(on[a-z]+)(?<=<[a-z][^<>]*)(?=\s*=\s*["'])`
  đổi on* thành data-cdn-on* trong HTML. Được gọi trong Render của 10 trang khung (BasicForm, ESSBasicForm, ESS/Main, Main, Login,
  Admin/Login, RBasicForm, MasterDataForm, Authenticate, ForgotPassword), ngay sau bước gắn nonce.
- Scripts/csp-inline-fix.js: shim override Element.prototype get/set/removeAttribute cho tên on*, để chúng làm việc với data-cdn-on*
  (DevExpress 16.2 ASPx.Attr dùng đúng 3 hàm này để lưu/khôi phục onclick khi disable/enable; giá trị lưu vào attribute savedonclick).
  Các selector của phần chuyển handler tìm cả [on*] và [data-cdn-on*].
- Shim phải chạy trước script DevExpress: csp-inline-fix.js phải nằm trong <head> (RBasicForm trước đây nạp sau </form>).
Còn sót: Render bỏ qua postback/callback, nên HTML trả về từ UpdatePanel / DevExpress callback có on* thật vẫn báo lỗi khi chèn.

## Kiểm chứng (Verification)
Chạy headless Chrome 156 (--enable-logging=stderr) trên các trang test tối giản với CSP qua thẻ meta:
- div onmouseover, không có event nào xảy ra: vẫn báo vi phạm (tức là báo lúc parse).
- button onclick được chuyển sang addEventListener(new Function) ở load: click vẫn chạy.
- innerHTML có onclick và setAttribute('onclick'): mỗi trường hợp đều báo 1 vi phạm.
- data-cdn-onmouseover: không báo.

## Hướng đi sai (Dead ends)
- Nghi bản deploy mới đổi CSP: không có thay đổi nào; chỉ khác phiên bản Chrome.

## Lần sau (Next time)
Khi lỗi CSP chỉ xuất hiện sau khi update trình duyệt, tạo trang test tối giản rồi chạy bằng headless Chrome
với --enable-logging=stderr --virtual-time-budget để xem vi phạm được báo ở thời điểm nào, trước khi sửa code.
