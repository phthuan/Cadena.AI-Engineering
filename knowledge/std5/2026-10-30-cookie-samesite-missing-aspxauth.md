---
title: Cookie .ASPXAUTH / ckLanguage thiếu thuộc tính SameSite dù project target .NET 4.5
project: std5
type: security
keywords: [SameSite attribute is missing from the cookie configuration, SameSite, .ASPXAUTH, ckLanguage, xcn, CWE-1275, httpCookies sameSite, cookieSameSite, new HttpCookie, FormsAuthentication.FormsCookieName, TargetFrameworkVersion v4.5]
files: [Cadena HRM 5.0/Cadena.WebApp/Config/Cookie.config, Cadena HRM 5.0/Cadena.WebApp/Web.config, Cadena HRM 5.0/Cadena.JobPortal/Web.config, Cadena HRM 5.0/Services/Cadena.WebAPI/Web.config, Cadena HRM 5.0/Cadena.WebApp/Login.aspx.cs, Cadena HRM 5.0/Cadena.WebApp/Controls/Login/Login.ascx.cs]
commit:
date: 2026-10-30
author: Thuan Pham Ngoc
status: active
---

## Triệu chứng (Symptom)
Pentest: "the SameSite attribute is missing from the cookie configuration". Trên /ESS/Main.aspx,
`.ASPXAUTH` và `ckLanguage` có cột SameSite trống; `xcn` (session) và cookie tạo bằng JS thì có Lax.

## Nguyên nhân gốc (Root cause)
- `.ASPXAUTH` được tạo thủ công bằng `new HttpCookie(FormsAuthentication.FormsCookieName, ...)` (Login.aspx.cs, Login.ascx.cs),
  nên không dùng cấu hình của `<forms>`. Một cookie tạo bằng `new HttpCookie` lấy giá trị mặc định từ `<httpCookies>`.
- Config/Cookie.config `<httpCookies>` chỉ có httpOnlyCookies/requireSSL, thiếu `sameSite`.
- `xcn` có Lax nhờ mặc định của sessionState (runtime 4.7.2+); cookie tạo bằng JS có Lax nhờ jquery_cookie.js tự thêm `;SameSite=Lax`.

## Cách sửa (Fix)
Sửa bằng cấu hình (project target 4.5 nên trong code không dùng được `HttpCookie.SameSite`):
- Cookie.config: `sameSite="Lax"`.
- WebApp Web.config: `<forms cookieSameSite="Lax">`, `<sessionState cookieSameSite="Lax">`.
- JobPortal: `<httpCookies sameSite="Lax" />`, `<forms cookieSameSite="Lax">`. WebAPI: `<sessionState cookieSameSite="Lax">`.
Chọn Lax, không chọn Strict: với Strict, người dùng mở link duyệt từ email sẽ bị coi như chưa đăng nhập ở lần mở đầu tiên.
Không thêm `requireSSL` cho `<forms>`: nếu SSL được terminate ở load balancer thì IIS thấy request là http và sẽ bỏ qua cookie đăng nhập.

## Kiểm chứng (Verification)
curl tới IIS Express local Login.aspx: `Set-Cookie: ckLanguage=...; secure; HttpOnly; SameSite=Lax`, `xcn=...; SameSite=Lax`.
.ASPXAUTH tạo theo cùng cách (new HttpCookie) nhưng chưa test trực tiếp bằng đăng nhập thật; cần retest trên server.

## Hướng đi sai (Dead ends)
- Tưởng "target framework 4.5" nghĩa là server không hỗ trợ sameSite. Thực tế thuộc tính trong config do runtime cài trên server
  quyết định; bằng chứng là `xcn` đã có Lax (mặc định chỉ có từ 4.7.2+).

## Lần sau (Next time)
Kiểm tra runtime: HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\Release >= 461808 là 4.7.2+.
Nếu có, sửa bằng `<httpCookies sameSite>`. Nếu runtime thật sự < 4.7.2, phải nối "; SameSite=Lax" vào cookie.Path trong EndRequest.
