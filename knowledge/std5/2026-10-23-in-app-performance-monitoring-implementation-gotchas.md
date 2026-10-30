---
title: In-app Performance Monitoring cho HRM WebApp — hook batcher của NHibernate 4.0.4, httpErrors nuốt lỗi API, map SPID khi không có ServerProcessId
project: std5
type: feature
keywords: [Performance Monitoring, PerformanceMonitoring.axd, DiagnosticsRuntime, MonitoringBatcher, TrackingConnectionProvider, SqlClientBatchingBatcher, IBatcher, adonet.factory_class, connection.provider, CS0506 cannot override inherited member because it is not marked virtual, ServerProcessId, ClientConnectionId, httpErrors existingResponse Replace, TrySkipIisCustomErrors, Error.html, SiteMap_PerformanceMonitoring, 1D16E437-2715-48B1-8D45-B5F5ECCE31B0]
files: [Cadena HRM 5.0/Cadena.NHibernateProvider/Diagnostics/*.cs, Cadena HRM 5.0/Cadena.Infrastructure.NHibernate/ModuleRegister.cs, Cadena HRM 5.0/Cadena.WebApp/Global.asax.cs, Cadena HRM 5.0/Cadena.WebApp/Web.config, Cadena HRM 5.0/Cadena.WebApp/Views/PerformanceMonitoringView.ascx, Cadena HRM 5.0/Cadena.SQLScripts/5.SiteMaps/SiteMap_PerformanceMonitoring.sql]
commit: (chưa commit — working tree của MAI-02_5.3.136.0)
date: 2026-10-23
author: Claude Code (session of phthuan136)
status: active
---

## Triệu chứng (Symptom)
Xây dựng System Setup > Performance Monitoring bên trong web process của HRM (tài liệu thiết kế "HRM Performance Monitoring – Kiến trúc tổng thể").

## Nguyên nhân gốc (Root cause)
(Tính năng.) Các bẫy gặp phải khi xây dựng:
- NHibernate 4.0.4: trong AbstractBatcher chỉ ExecuteReader, DoExecuteBatch và Dispose(bool) là override được.
  ExecuteNonQuery, CloseReader, CloseCommands là các interface implementation bị sealed → CS0506. Reflection hiển thị chúng là
  IsVirtual (do là interface method), điều này gây hiểu lầm.
- IBatcher nằm trong NHibernate.Engine, không phải NHibernate.AdoNet.
- System.Data.SqlClient trên .NET Framework không có SqlConnection.ServerProcessId. ClientConnectionId (Guid) có tồn tại và bằng
  sys.dm_exec_connections.connection_id → map SPID tới trang/người dùng HRM mà không cần thêm một round trip.
- Web.config của HRM `<httpErrors errorMode="Custom" existingResponse="Replace">` viết lại mọi 4xx/5xx (và 404 cho App_Data)
  thành Error.html với HTTP 200. Response.TrySkipIisCustomErrors KHÔNG giúp được khi existingResponse="Replace".
- AuthenticateUser trong Global.asax chỉ chạy khi request có Session; một IHttpHandler không có session hoàn toàn không được
  HRM xác thực → nó cần cơ chế kiểm tra riêng (token HMAC có ký do view cấp).
- Cadena.WebApp/Config/ConnectionStrings.config là untracked/local; ngày 2026-10-23 nó trỏ tới MAI-02_HRM_CUS_20260624, database
  không còn tồn tại trên HRS05\SQL2022 (chỉ còn MAI-02_HRM_CUS_07092026).

## Cách sửa (Fix)
- Code trong Cadena.NHibernateProvider/Diagnostics (namespace Cadena.Diagnostics; không thay đổi .sln). MonitoringBatcher kế thừa
  từ SqlClientBatchingBatcher VÀ khai báo lại IBatcher, implement ExecuteNonQuery/CloseReader/CloseCommands một cách tường minh
  (NHibernate luôn gọi qua IBatcher).
- DiagnosticsNHibernate.Apply(config) được gọi trong ModuleRegister SAU khối if/else của ConfigurationFileCache, để cache hit cũng có
  nó và nó không bị lưu vào file cache.
- Handler luôn trả về HTTP 200 với {"failed":true,"unauthorized"?,"error"} khi thất bại; trang đọc cờ này.
- Sitemap: SiteMap_PerformanceMonitoring.sql được clone từ SiteMap_SQLAssistant.sql (cũng thêm dòng Localization_LocalTexts),
  được liệt kê trong _5.SiteMapIndexing.txt + EmbeddedResource.
- Menu (đã sửa 2026-10-24): chỉ riêng dòng dữ liệu KHÔNG làm hiện mục menu. Các mục System Setup được hard-code trong Main.aspx
  (khối SupperAdmin); đã thêm một <p id="1D16E437-..." onclick="openTab(...BasicForm.aspx?fid=...)"> sau SQL Assistant.
- Dữ liệu runtime App_Data/Diagnostics được thêm vào .gitignore (chứa .secret).

## Kiểm chứng (Verification)
- MSBuild Debug: Cadena.NHibernateProvider và Cadena.WebApp (kèm reference) thành công.
- IIS Express (.vs/Cadena HRM 5.0/config/applicationhost.config, site Cadena.WebApp, port 17228) với
  MAI-02_HRM_CUS_07092026: monitor khởi động, metric mỗi 10 s, SQL lúc khởi động được ghi lại (owner "(background) thread 1"),
  mọi API action đều phản hồi; các DMV action trên SQL 2022: topsql 0.5–2 s, waits 0.6 s, sessions 0.05 s, deadlocks ~26 s.
  Token bị sửa/thiếu, action không xác định và path traversal (tên snapshot, file hourstats) đều bị từ chối.
- A/B sơ bộ: 300 GET Login.aspx với concurrency 10, Off so với Basic p50 4.19 s so với 4.19 s; queue ≤ 7, dropped 0. GET đó không chạy
  SQL nào sau warm-up, nên hot path SQL dưới tải CHƯA được đo.
- Bản thân trang UI chưa được mở trên trình duyệt (session không có tài khoản đăng nhập HRM); JS đã qua `node --check`.

## Hướng đi sai (Dead ends)
- Override ExecuteNonQuery/CloseReader/CloseCommands (CS0506).
- Response.TrySkipIisCustomErrors để cho JSON 401 đi qua httpErrors Replace.
- curl hiển thị HTTP 200 cho App_Data/.secret trông như bị lộ; thực ra body là Error.html (kiểm tra header X-SourceFiles).

## Lần sau (Next time)
Mở http://localhost:17228 → đăng nhập → System Setup → Performance Monitoring. Test hot path SQL với một scenario thật
(phân tích timesheet / payroll) dưới nhiều người dùng đồng thời trước khi lên production; một Quartz IJobListener và caption tiếng Việt
vẫn chưa làm.
