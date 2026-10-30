---
title: Response vẫn lộ header "Server: Microsoft-IIS/10.0" dù đã Remove("Server") trong Application_BeginRequest
project: std5
type: security
keywords: [Server: Microsoft-IIS/10.0, server name and version disclosure, Server header, X-AspNet-Version, X-Powered-By, CWE-200, CWE-497, WebResource.axd, Application_BeginRequest, Application_PreSendRequestHeaders, removeServerHeader, OnSendingHeaders]
files: [Cadena HRM 5.0/Cadena.WebApp/Global.asax.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/Global.asax.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/Startup.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/Web.config, Cadena HRM 5.0/Cadena.JobPortal/Global.asax.cs, Cadena HRM 5.0/Cadena.JobPortal/Web.config]
commit:
date: 2026-10-30
author: Thuan Pham Ngoc
status: active
---

## Triệu chứng (Symptom)
Pentest (Burp) báo: "the application discloses its server name and version information in the HTTP response".
GET /WebResource.axd?d=... trả `Server: Microsoft-IIS/10.0`.

## Nguyên nhân gốc (Root cause)
- Global.asax (WebApp, WebAPI) gọi `Response.Headers.Remove("Server")` trong `Application_BeginRequest`.
  Lúc đó IIS chưa thêm header Server nên lệnh xóa không có tác dụng.
- WebAPI Startup.cs (OWIN) xóa header trước `next()`, cũng quá sớm.
- WebApp Web.config có outbound rule URL Rewrite đổi Server thành "Cadena HRM Series", nhưng không áp dụng
  cho response không đi qua rewrite module (module chưa cài, hoặc response cache `Cache-Control: public` như WebResource.axd).
- JobPortal không có cơ chế nào.

## Cách sửa (Fix)
- Thêm `Application_PreSendRequestHeaders` vào Global.asax của WebApp, WebAPI, JobPortal để xóa
  `Server`, `X-AspNet-Version`, `X-AspNetMvc-Version`, `X-Powered-By`; bỏ Remove("Server") ở BeginRequest.
  `runAllManagedModulesForAllRequests="true"` nên request tĩnh/.axd cũng đi qua handler này.
- WebAPI Startup.cs: dùng `context.Response.OnSendingHeaders(...)` và đăng ký middleware trước `MapSignalR`.
- `enableVersionHeader="false"` cho httpRuntime của WebAPI và JobPortal (WebApp đã có).
- Chưa thêm `<requestFiltering removeServerHeader="true" />`: chỉ hỗ trợ từ IIS 10 bản 1709 (Windows Server 2019+);
  trên Windows Server 2016 sẽ gây lỗi 500.19. Chỉ thêm khi đã xác nhận OS của server.

## Kiểm chứng (Verification)
- MSBuild Cadena.WebApp, Cadena.WebAPI, Cadena.JobPortal: build thành công.
- Gọi curl tới IIS Express local (Login.aspx, WebResource.axd, file tĩnh): không còn thấy Server / X-AspNet-Version / X-Powered-By.
- Retest trên server: `curl -sI https://<host>/WebResource.axd?d=...` và một URL 404, kiểm tra không có header Server.

## Hướng đi sai (Dead ends)
- Remove("Server") trong Application_BeginRequest / trước next() của OWIN: quá sớm, không có tác dụng.
- Chỉ dựa vào outbound rule của URL Rewrite: phụ thuộc vào việc server cài module, và response lấy từ cache không đi qua rule.

## Lần sau (Next time)
Xóa header ở PreSendRequestHeaders (Global.asax) hoặc OnSendingHeaders (OWIN). Với response HTTP.sys tự sinh
(400/503 trước khi request vào IIS), cần thêm `removeServerHeader` (IIS 10 1709+) hoặc registry
HKLM\SYSTEM\CurrentControlSet\Services\HTTP\Parameters\DisableServerHeader=2 trên server.
