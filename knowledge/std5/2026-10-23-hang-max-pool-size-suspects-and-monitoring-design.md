---
title: Production bị treo / CPU 100% / "max pool size was reached" — những nơi HRM giữ connection, và chỗ gắn hook cho in-app performance monitor
project: std5
type: performance
keywords: [Timeout expired, The timeout period elapsed prior to obtaining a connection from the pool, max pool size was reached, SessionPerRequestModule, SingletonSingleThreadSemaphore, SingletonSemaphore, ProcessAnalysisTimeSheetCommandHandler, ProcessCalculateSalaryCommandHandler, BaseScheduleJob, new Thread, DisallowConcurrentExecution, GetSessionAudit, GetAuditTrailDetailQueryHandler, ConnStringDBAudit, SaveDocumentToMemoryStream, CacheReportDocument, InternalApiClient, BaseApiClient, CommandTimeout 300, EnableService, ConfigurationFileCache, adonet.factory_class, SiteMap_SiteMaps, SiteMap_SQLAssistant, Performance Monitoring]
files: [Cadena HRM 5.0/Cadena.NHibernateProvider/Web/SessionPerRequestModule.cs, Cadena HRM 5.0/Cadena.Infrastructure.NHibernate/ModuleRegister.cs, Cadena HRM 5.0/Services/Cadena.BackgroundJobs/Jobs/ScheduleJobs/AnalyzeDailyTimeSheetJob.cs, Cadena HRM 5.0/Cadena.BusinessLayer/AnalyzeTimeSheetData/Handlers/ProcessAnalysisTimeSheetCommandHandler.cs, Cadena HRM 5.0/Cadena.BusinessLayer/Payroll/Handlers/SalaryCalculation/ProcessCalculateSalaryCommandHandler.cs, Cadena HRM 5.0/Cadena.BusinessLayer/ConfigManager/ConnectionStringHelper.cs, Cadena HRM 5.0/Modules/Cadena.Modules.Setting/Handlers/GetAuditTrailDetailQueryHandler.cs, Cadena HRM 5.0/Cadena.Web/API/Consumer/BaseApiClient.cs, Cadena HRM 5.0/Cadena.WebApp/Login.aspx.cs, Cadena HRM 5.0/Cadena.WebApp/Config/ConnectionStrings.config, Cadena HRM 5.0/Cadena.SQLScripts/5.SiteMaps/SiteMap_SQLAssistant.sql]
commit: (chưa commit — hai bản sửa leak nằm trong working tree; các script HangDiagnostics đã được chuyển sang D:/Source Project/HRM-Tools/HangDiagnostics của MAI-02_5.3.136.0)
date: 2026-10-23
author: Claude Code (session of phthuan136)
status: active
---

## Triệu chứng (Symptom)
Production (dữ liệu lớn, nhiều người dùng) bị treo hoặc sập với CPU/RAM lên tới 100%, lỗi "max pool size", người dùng không đăng nhập được.
Chạy local thì bình thường. Hai session review ngày 2026-10-23: một bản thiết kế monitoring, sau đó là review kiến trúc về các nguyên nhân pool / blocking / RAM.

## Nguyên nhân gốc (Root cause)
Chưa được chứng minh với một sự cố thật của khách hàng (không có dump, không có DMV capture). Các sự thật đọc được từ code:

Connection pool
- Web app tự chạy Quartz (EnableService=true trong Cadena.WebApp/Config/AppSettings.config) trên cùng connection string,
  nên job và người dùng dùng chung một pool (không có Max Pool Size → mặc định 100 cho mỗi w3wp).
- 21 job theo lịch/thủ công khởi động `new Thread(...)` bên trong Execute và trả về ngay (ví dụ AnalyzeDailyTimeSheetJob.cs:36,77).
  Thread pool của Quartz không còn giới hạn chúng, và [DisallowConcurrentExecution] bị comment out trên gần như mọi job.
  Mức đồng thời ≈ số company × số job chạy cùng một thời điểm cron.
- Mỗi job giữ một session + transaction trong suốt lần chạy (AnalyzeDailyTimeSheetJob.cs:96-98). Sau đó handler timesheet
  chờ một semaphore toàn cục trong khi transaction bên ngoài vẫn mở (ProcessAnalysisTimeSheetCommandHandler.cs ~693-712).
  Các lần chạy của service dùng SingletonSingleThreadSemaphore (capacity 1), nên N company = N connection idle-in-transaction đang chờ.
- Leak permit của semaphore: Wait() xảy ra trước đoạn code có thể ném exception bên ngoài try/finally giải phóng nó:
  `throw new Exception("Employee is null...")` sau Wait (~dòng 727), và OpenSession / session.Connection / BeginTransaction
  bên trong Task.Run trước try (~742-753). Một pool timeout ở đó làm mất một permit vĩnh viễn; với capacity 1, mọi lần
  phân tích timesheet của service sau đó đều treo, mỗi lần giữ connection bên ngoài của nó. Cùng dạng lỗi trong ProcessCalculateSalaryCommandHandler
  (Wait ~408, OpenStatelessSession/BeginTransaction ~459-461 trước try ở ~462).
- GetAuditTrailDetailQueryHandler.LoadSession → ConnectionStringHelper.GetSessionAudit(_sessionFactory, true): mở một
  transaction, không bao giờ commit/close → leak một connection mỗi lần gọi.
- Nếu ConnStringDBAudit được đặt, ConnectionStringHelper.GetConnectionAudit mở một SqlConnection được truyền vào
  OpenSession/OpenStatelessSession(conn). NHibernate không đóng connection do người dùng cung cấp, cũng không ai khác đóng →
  leak ở mỗi lần ghi audit (AuditTrailManager.LoadSession) và mỗi query audit. Khi pool đó đầy, Open() chờ hết
  connect timeout (15 s) rồi mới fallback: mọi thao tác lưu đều bị chặn.
- NHibernate CommandTimeout = 300 s (ModuleRegister.cs:87), một số query SetTimeout(900): một query bị block giữ
  connection trong 5-15 phút. executionTimeout của web (110 s) không hủy SQL.

Thread / blocking
- Login.aspx.cs thực hiện ~19 lời gọi InternalApiClient với `.Result`; BaseApiClient.GetApiResponseMessageAsync cũng dùng
  `client.SendAsync(...).Result` và await mà không có ConfigureAwait(false). Mỗi lần login chặn một request thread qua nhiều
  bước HTTP tới Cadena.WebAPI → cạn thread pool (thread-pool starvation) khi có đợt login dồn dập; nguy cơ deadlock với AspNetSynchronizationContext.
- Login cập nhật dòng user (LoginAuthorization.cs:107-114). ReadUncommitted không ngăn được writer bị block
  bởi các transaction job dài giữ lock / lock escalation trên cùng bảng.

RAM
- ~153 view báo cáo DevExpress thực hiện `Page.Session[Guid.NewGuid()] = e.SaveDocumentToMemoryStream()` trong CacheReportDocument
  và không bao giờ xóa; sessionState là InProc (20 phút). Báo cáo lớn → LOH tăng, GC tốn CPU.
- AnalyzeDailyTimeSheetJob / AnalyzeFinalTimeSheetJob tạo một System.Runtime.Caching.MemoryCache cho mỗi instance, không bao giờ dispose.
- NhRepository.Session mở session mới ở mỗi lần truy cập khi không có current session (background thread), không bao giờ dispose.
- NotificationHub.RefreshServiceAlert tải toàn bộ bảng BasicFormSiteMap mỗi lần gọi; LoginAuthorization tải toàn bộ SiteMapPayTime mỗi lần login.

Transaction theo request scope và hai leak nhỏ (kiểm chứng lại ngày 2026-10-23 trên branch MAI-02_5.3.136.0, D:\Source Project\MAI-02\STD5):
- SessionPerRequestModule.BeginSession CÓ mở transaction: dòng 71 `session.BeginTransaction(ReadUncommitted)` là code đang chạy,
  không bị comment out; EndSession commit nó ở EndRequest. Một ghi chú trước đây trong bài học này nói ngược lại là sai với
  branch này — hãy kiểm tra branch/checkout trước khi dựa vào bất kỳ khẳng định nào (các branch khách hàng khác có thể khác).
- JobScheduler.CorrectJobStatus và AuditTrailManager.GetLocalTextFromReferenceTable bị leak trong code đã commit
  (CorrectJobStatus: session + transaction không bao giờ đóng; GetLocalText...: session không bao giờ dispose, leak khi query ném exception).
  Chúng "dùng `using`" chỉ là nhờ bản sửa chưa commit thực hiện trong session này (xem mục Cách sửa).

## Cách sửa (Fix)
Đã làm (chưa commit, branch MAI-02_5.3.136.0): `using` bao quanh session trong JobScheduler.CorrectJobStatus (kết quả query
được materialize bên trong, vòng lặp ở sau) và trong AuditTrailManager.GetLocalTextFromReferenceTable. Đã thêm các script chẩn đoán treo read-only trong
`D:/Source Project/HRM-Tools/HangDiagnostics` (nằm ngoài source repo, không commit cùng HRM) (01 blocking, 02 connection pool, 03 top store/function/query, 04 deadlock từ
system_health, 05 waits/CPU/IO/memory + README kèm các bước ProcDump).
Vẫn khuyến nghị, theo thứ tự: (1) sửa leak permit của semaphore và leak session/connection của audit;
(2) không giữ transaction bên ngoài của job trong khi chờ semaphore; (3) chuyển Quartz ra khỏi web process
(web EnableService=false, host riêng với connection string + Application Name + pool size riêng), bỏ `new Thread`
trong job và dùng [DisallowConcurrentExecution] + threadCount nhỏ cho Quartz; (4) bỏ report stream khỏi Session
(xóa sau khi restore hoặc dùng file/cache có thời hạn); (5) chuyển các lời gọi khi login sang async hoặc gọi mediator trực tiếp;
(6) giảm CommandTimeout cho web; thêm `Application Name=` vào connection string để DMV phân biệt web với job.
Các điểm gắn hook của thiết kế monitoring (tài liệu "HRM Performance Monitoring – Kiến trúc tổng thể"):
- Đo thời gian SQL: một batcher factory (`adonet.factory_class`). ModuleRegister cache NH Configuration ra file
  (ConfigurationFileCache); áp dụng property SAU KHI đã có Configuration, cả trên nhánh cache-hit.
- Bên giữ connection: bọc NHibernate IConnectionProvider; ghi SPID (SqlConnection.ServerProcessId) để join với DMV.
- Menu: SiteMap_*.sql mới trong Cadena.SQLScripts/5.SiteMaps (ParentID 4D754FBF-00E0-4191-A0EF-A40D009D409B = System Setup),
  được liệt kê trong _5.SiteMapIndexing.txt và dưới dạng EmbeddedResource; view kế thừa BaseUserControl với [FormInfo(FormID=...)].
- Dữ liệu UI qua một IHttpHandler không có IRequiresSessionState. Lưu trữ: JSON Lines dưới App_Data/Diagnostics.

## Kiểm chứng (Verification)
- Cadena.BusinessLayer build kèm project reference (MSBuild, Debug): thành công với hai bản sửa leak.
  Build với /p:BuildProjectReferences=false thất bại ở các file không liên quan (DLL được tham chiếu đã cũ) — không phải do bản sửa.
- 5 SQL script chạy không lỗi trên SQL Server 2025 local (tempdb). Một deadlock local được tạo có chủ đích đã được 04 parse đúng
  (victim, cả hai statement, key lock, table/index); một chuỗi blocking được tạo có chủ đích đã được 01 tìm ra (head blocker, waiter LCK_M_S,
  tuổi của transaction). sqlcmd mặc định QUOTED_IDENTIFIER OFF → các XML method lỗi (Msg 1934); script giờ SET nó ON.
  XML method không được phép trong GROUP BY (Msg 4148) → dùng derived table.
- Không có load test, không có dữ liệu khách hàng. Các phát hiện khác ở trên chỉ là đọc code.

## Hướng đi sai (Dead ends)
- Một IIS app pool thứ hai trỏ vào cùng thư mục với cùng cấu hình để monitor vẫn truy cập được: bị loại — nó chạy lại
  Global.asax và khởi động Quartz lần thứ hai. (Tách job ra chỉ hoạt động khi phía web đặt EnableService=false.)
- "Menu System Setup là dữ liệu trong SiteMap_SiteMaps" (grep .ascx/.cs không tìm thấy gì): SAI, đã đính chính ngày 2026-10-24.
  Sidebar System Setup được HARD-CODE trong Cadena.WebApp/Main.aspx (mỗi mục một <p onclick="openTab(...)">, bên trong
  `if RoleAdmin == SupperAdmin`). Dòng SiteMap vẫn cần thiết (BasicForm.aspx?fid= tải UserControlUrl từ đó), nhưng
  một trang System Setup mới cũng cần thẻ <p> của nó trong Main.aspx. Hãy grep cả .aspx.
- "Transaction theo request scope trong SessionPerRequestModule đã bị comment out": không đúng trên MAI-02_5.3.136.0 (dòng 71 đang chạy).
  Kiểm chứng trên đúng branch trước khi dùng nó để kết luận hoặc loại trừ nguyên nhân.
- Grep / ripgrep toàn bộ cây "Cadena HRM 5.0" bị timeout (packages, bin, obj). Dựng danh sách file .cs một lần, loại trừ
  packages/Dlls/Libraries/bin/obj, rồi grep qua xargs.

## Lần sau (Next time)
Với lỗi "max pool size" hoặc treo: chạy `D:/Source Project/HRM-Tools/HangDiagnostics` (nằm ngoài source repo, không commit cùng HRM) 01, 02, 05 trong lúc sự cố đang xảy ra (README có
thứ tự và cách đọc kết quả), hoặc tự capture `sys.dm_exec_sessions` nhóm theo program_name/status với
open_transaction_count > 0 (idle-in-transaction = session bên ngoài của job hoặc leak), chuỗi blocking từ
sys.dm_exec_requests.blocking_session_id, và perf counter (SqlClient NumberOfActiveConnections, ASP.NET Requests Queued).
Sau đó kiểm tra: leak permit của semaphore trong handler timesheet/salary, leak session của audit, các job chạy cùng một thời điểm cron.
