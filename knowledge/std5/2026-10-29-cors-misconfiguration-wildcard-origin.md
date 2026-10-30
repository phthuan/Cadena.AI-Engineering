---
title: CORS Misconfiguration - Access-Control-Allow-Origin "*" + Allow-Credentials true; chuyển fix từ MCMC-01 sang TMF-MTL-02
project: std5
type: security
keywords: [CORS, CORS Misconfiguration, CWE-942, Access-Control-Allow-Origin, Access-Control-Allow-Credentials, EnableCors, EnableCorsAttribute, AllowedOrigins, SignalRAllowedOrigins, WebApiConfig, Global.asax, Application_BeginRequest, signalr, Vary Origin, wildcard origin, #89632, PENTest-Fixing2]
files: [Cadena HRM 5.0/Services/Cadena.WebAPI/App_Start/WebApiConfig.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/Global.asax.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/Config/AppSettings.config, Cadena HRM 5.0/Services/Cadena.WebAPI/Controllers/*.cs]
commit: ee5f69cc42 48a4c965c0 (nguồn MCMC-01)
date: 2026-10-29
author: Thuan Pham Ngoc (with Claude)
status: active
---

## Triệu chứng (Symptom)
Pentest báo CORS Misconfiguration ở Cadena.WebAPI (#89632). Response trả `Access-Control-Allow-Origin: *`.
Bản vá đã làm ở branch MCMC-01, cần chuyển sang TMF-MTL-02 (STD5).

## Nguyên nhân gốc (Root cause)
WebAPI cho phép mọi origin. Ở TMF-MTL-02 bề mặt rộng hơn MCMC-01:
- `Global.asax.cs > Application_BeginRequest`: gắn `Access-Control-Allow-Origin: *` **kèm** `Access-Control-Allow-Credentials: true`
  cho **mọi** request (vô điều kiện). Đây là dạng CORS misconfig nặng (ACAO `*` + credentials).
- **9 controller** gắn `[EnableCors(origins: "*", headers: "*", methods: "*")]`: Appraisal, Competency, ELeave,
  EmployeePerformance, EOvertime, ETraining, Localization, PendingAction, User.
- `WebApiConfig.cs`: `config.EnableCors(...)` đang bị comment hết (khác MCMC là bật).

## Cách sửa (Fix) - hướng "gom về 1 chỗ" giống MCMC
1. `AppSettings.config` (WebAPI): thêm `<add key="AllowedOrigins" value="http://localhost:60880" />` (placeholder, PHẢI đổi theo môi trường thật).
2. `WebApiConfig.Register`: đọc `AllowedOrigins` từ config (split `;`, join `,`), throw `ConfigurationErrorsException` nếu rỗng,
   rồi `config.EnableCors(new EnableCorsAttribute(origins: allowedOrigins, headers: "*", methods: "*"))`. Thêm `using System.Configuration;`.
   EnableCorsAttribute áp cho toàn bộ route Web API (kể cả generic Query/Command API).
3. 9 controller: **xóa** dòng `[EnableCors(origins:"*")]` (CLAUDE.md cấm giữ code cũ dạng comment nên xóa hẳn, không comment như MCMC).
4. `Global.asax.cs > Application_BeginRequest`: thay wildcard bằng allowlist **chỉ cho `/signalr/`** (vì EnableCors của Web API
   không áp cho signalr, mà WebAPI có `app.MapSignalR` trong Startup.cs). Chỉ echo `Access-Control-Allow-Origin: <origin>` +
   `Access-Control-Allow-Credentials: true` + `Vary: Origin` khi origin nằm trong AllowedOrigins. Bỏ ACAO `*` và credentials vô điều kiện.
   Thêm `using System.Configuration; System.Linq; System.Collections.Generic;`.

Kiến trúc cuối: WebApiConfig lo CORS cho API; Global.asax lo CORS cho signalr; không nơi nào còn `*`; không trùng header
(API lấy từ EnableCors, signalr lấy từ BeginRequest - không chồng nhau).

## Kiểm chứng (Verification)
- Build Services/Cadena.WebAPI (MSBuild, Debug): 0 lỗi. Chưa test runtime trên IIS, chưa kiểm header thực tế.

## Hướng đi sai (Dead ends)
- Apply máy móc diff của MCMC KHÔNG được: đích khác kiến trúc (MCMC fix ở WebApiConfig + 2 controller Dashboard/Localization;
  đích không có DashboardController, lỗi nằm ở Global.asax BeginRequest + 9 controller).
- **`.ToHashSet()` không dùng được**: WebAPI target .NET 4.5 (ToHashSet có từ 4.7.2). Dùng `new HashSet<string>(..., StringComparer.OrdinalIgnoreCase)`.
- **Line ending/CRLF**: các file controller .cs lưu LF và KHÔNG có newline cuối file. Xóa 1 dòng bằng Edit/sed theo giả định
  CRLF làm dính dòng (`[RoutePrefix]    public class`) hoặc đổi line ending cả file. Cách sạch: `grep -v -F '<dòng>' f > tmp && mv`,
  rồi bỏ newline cuối do grep thêm: `perl -i -0pe 's/\n\z//'`. Kiểm bằng `git diff --stat` phải đúng 1 dòng/ file.
- MCMC còn điểm chỏi: config đổi key thành `AllowedOrigins` nhưng Global.asax vẫn đọc key cũ `SignalRAllowedOrigins`
  (không còn) → nhánh signalr vô hiệu. Ở đích đã dùng thống nhất 1 key `AllowedOrigins`, không copy lỗi này.
- Không chuyển property `AppSetting.AllowedOrigins` + `IAppSetting` từ MCMC: ở đích cả 2 nơi đọc `ConfigurationManager.AppSettings` trực tiếp
  nên property đó là dead code (MCMC cũng không ai dùng). Nếu muốn đồng bộ interface thì thêm sau.

## Lần sau (Next time)
- Trước khi lên môi trường: đổi `AllowedOrigins` thành danh sách origin thật của web/mobile (phân tách bằng `;`), nếu không
  gọi API/signalr cross-origin từ browser sẽ hỏng. `AllowedOrigins` rỗng sẽ làm WebAPI throw lúc khởi động (cố ý fail-fast).
- Endpoint/origin mới cần CORS: chỉ sửa config `AllowedOrigins`, không sửa code.
- Thêm controller mới: KHÔNG gắn lại `[EnableCors(origins:"*")]`; CORS đã global ở WebApiConfig.
