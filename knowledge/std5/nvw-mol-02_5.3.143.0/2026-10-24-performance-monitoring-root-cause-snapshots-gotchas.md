---
title: "Performance Monitoring (incident mode, SQL delta, plan, deadlock, To fix, Slow moments) — bẫy DMV toàn server, DMV của chính monitor bị tính là tải HRM, đọc system_health chậm, lấy mẫu 1/N bị aliasing, tracker giữ connection leak sống, baseline sau restart"
project: std5
branch: NVW-MOL-02_5.3.143.0
type: feature
keywords: [Performance Monitoring, DiagnosticsRuntime, SqlServerProbe, SqlIncidentReport, SqlServerTop, TopSlow, SlowMomentTop, BlockingTop, PlanAnalyzer, IndexDraftBuilder, DeadlockCollector, Analyzer, ConnectionTracker, WindowStats, JobListener, dm_exec_query_stats, dm_exec_plan_attributes, dbid, dm_exec_text_query_plan, dm_db_missing_index_group_stats, fn_xe_file_target_read_file, system_health, xml_deadlock_report, RING_BUFFER_SCHEDULER_MONITOR, GlobalMemoryStatusEx, CallContext.LogicalSetData, max pool size, NumberOfReclaimedConnections, Total_Cost_Impact, Process is terminated due to StackOverflowException, Operand type clash]
files: [Cadena HRM 5.0/Cadena.NHibernateProvider/Diagnostics/*.cs, Cadena HRM 5.0/Cadena.NHibernateProvider/Cadena.NHibernateProvider.csproj, Cadena HRM 5.0/Cadena.BusinessLayer/Scheduler/JobListener.cs, Cadena HRM 5.0/Cadena.WebApp/Views/PerformanceMonitoringView.ascx]
commit: (chưa commit — working tree của MAI-02_5.3.136.0)
date: 2026-10-24
author: Thuan Pham Ngoc
status: active
confidence: verified
---

## Triệu chứng (Symptom)
Mục tiêu: khi khách hàng báo CPU / RAM cao / treo / max pool size, dev mở System Setup > Performance Monitoring và đọc được
store / function / statement / missing index / blocking / deadlock / bên giữ connection / job nào gây ra.
Vòng 1 xem 2026-10-23-in-app-performance-monitoring-implementation-gotchas.md.

## Nguyên nhân gốc (Root cause)
Các bẫy phát hiện khi xây dựng và kiểm chứng trên SQL Server 2022 dev dùng chung nhiều database.

SQL Server DMV:
- `sys.dm_exec_query_stats` là TOÀN SERVER: lần test đầu "tìm thấy" 69 phút CPU của một database khác trên cùng server.
  Lọc bằng `CROSS APPLY sys.dm_exec_plan_attributes(plan_handle) WHERE attribute = 'dbid'` (≈7 µs/plan, 42 ms cho 6 112 plan).
  `dm_exec_sql_text.dbid` chậm hơn và NULL ở 75 % dòng.
- DMV query của chính monitor, của SSMS object explorer và script DBA chạy trong ngữ cảnh DB HRM nên đứng đầu bảng "HRM"
  và sinh finding sai "implicit conversion". Loại các statement khớp `\bsys\.(dm_|fn_xe_|database_query_store)` và `(sys|INFORMATION_SCHEMA)\.`.
- Đọc mọi file `system_health*.xel` mất 22-60 s. Đọc tăng dần bằng `fn_xe_file_target_read_file(pattern, NULL, @file, @offset)`
  và lưu vị trí; lần đầu chỉ đọc file hiện tại (~5 s), các lần sau ~1.5 s. Frame ad-hoc có text "unknown": dùng inputbuf.
  system_health ghi deadlock trễ ~30 s, nên snapshot ngay sau lỗi 1205 chưa có deadlock graph.
- Chỉ đọc deadlock sau khi HRM nhận lỗi 1205 sẽ bỏ sót deadlock mà victim là ứng dụng khác: cần đọc định kỳ.
- `open_transaction_count` / `database_id` của `dm_exec_sessions` và file target system_health chỉ có từ SQL 2012.
  Với 2008 R2 dùng `sys.sysprocesses` (open_tran, dbid) qua OUTER APPLY.
- Mẫu CPU của ring buffer là theo phút: đợt tăng vọt ngắn hơn một phút có thể hiện 0 %.
- `WHERE 1 = 1` và `WHERE 2 = 2` có cùng query_hash: query test phải khác nhau về cấu trúc.

Đo delta (statistics hiện tại − baseline):
- Không có baseline thì số liệu là cộng dồn từ khi SQL start (nhiều ngày); hai lần phân tích sát nhau đo được 0.
  Baseline phải được đọc định kỳ (15 phút) và giữ một baseline cũ hơn ≥ 2 phút.
- Sau khi ứng dụng restart, lần đọc đầu tiên chỉ được làm mốc nếu đã có danh sách lưu; nếu import tổng cộng dồn thì
  lịch sử cũ quay lại danh sách. Mọi xử lý phụ (ví dụ cập nhật cost của missing index) cũng phải chạy trong nhánh "chỉ làm mốc",
  nếu không giá trị đã lưu đứng yên tới lần đọc thứ hai (~17 phút).
- "Start a new list" phải bỏ cả lần đọc trước (`_previous`), nếu không lần refresh kế tiếp cộng thêm cả giờ hoạt động cũ.

Lấy mẫu, thread, chi phí:
- Lấy mẫu 1/N bằng bộ đếm round-robin bị aliasing với vòng lặp N+1 lặp statement theo thứ tự cố định (5/50 statement được lấy,
  mỗi cái đếm 10 lần). Dùng random xorshift theo thread → sai số ±5 %.
- Quartz job tạo `new Thread`: owner `[ThreadStatic]` không đi theo. Dùng `CallContext.LogicalSetData` trong `JobListener.JobToBeExecuted`
  và `FreeNamedDataSlot` trong `JobWasExecuted`.
- Watchdog trên `System.Threading.Timer` (thread pool) không chạy khi HRM treo do thread-pool starvation: cần thread riêng.
- `StackTrace(false)` 20-67 µs nhưng ~190 µs khi 8 thread cùng capture (contention CLR): chỉ lấy stack khi statement đã chậm/lặp.
- Normalizer 6 lượt regex 178 µs/statement và cache SQL text thô tới 100 MB với SQL nối chuỗi; format timestamp cho mỗi statement
  làm chi phí nền tăng gấp ba. Giữ hot path ở mức < 0.5 µs/SQL: không regex, không format chuỗi, cache có giới hạn theo ký tự.
- `ConcurrentDictionary.Count` lấy mọi lock: không gọi ở mỗi lần mở connection.
- Lấy mẫu blocking 15 s trên tick 10 s thực tế là 20 s, nên lần chờ lock 45 s không bao giờ thấy ở mức ≥ 30 s.

Connection và max pool size:
- Tracker giữ `IDbConnection` làm strong key khiến session không dispose không bao giờ bị GC thu gom → chính monitor biến leak
  thành vĩnh viễn và `NumberOfReclaimedConnections` luôn 0. Dùng weak key (WeakReference + RuntimeHelpers hash), lock-free;
  `ConditionalWeakTable.TryGetValue` lấy lock trên .NET Framework.
- Connection mở trực tiếp bằng `SqlConnection` (DbBase không đóng connection — Cadena.Core/DbConnection/IDb.cs; ADONet; BulkCopyHelper)
  dùng chung pool nhưng tracker không thấy: báo "10 of 100" khi pool đã đầy. Liệt kê session của w3wp qua `host_process_id` = PID
  và `host_name`, kể cả session đang sleeping. Session còn gồm pooled connection idle (giữ 4-8 phút sau đợt tăng vọt):
  chỉ coi là "held" khi reason = max-pool-size, hoặc khi có transaction mở / idle ≥ LeakSuspectMinutes.
- Mọi snapshot dùng chung cooldown thì snapshot max-pool-size bị nuốt bởi snapshot blocking/CPU vài phút trước: cần cooldown riêng.

Vận hành:
- Settings kẹp `IncidentSlowSqlMs ≤ SlowSqlMs` khi Normalize đã ghi đè vĩnh viễn giá trị khi hạ SlowSqlMs để test: kẹp lúc runtime bằng Math.Min.
- "Refresh làm tôi bị đăng xuất": HRM dùng `sessionState mode="InProc"`, mỗi lần app restart (copy DLL vào bin khi build dev,
  restart IIS Express) đều đăng xuất mọi người. Monitor chỉ ghi vào App_Data (bị file-change notification bỏ qua) nên không gây restart.
  Lý do shutdown xem ở dòng Application_End / Application_Start trong Logs/<date>.log, không có trong Event Log máy dev.
- JavaScriptSerializer không đọc được thời gian dạng chuỗi ISO cũ (ra 0001-01-01), lần lưu sau bỏ mọi entry vì "cũ hơn retention".
- Off phải dừng thật các thread worker/watchdog, nếu không một sự kiện lúc đang off để lại snapshot chờ, kích hoạt sai thời điểm khi bật lại.

## Cách sửa (Fix)
- Công tắc on/off (mặc định OFF trên deployment mới; trạng thái nằm trong App_Data/Diagnostics/settings.json, bị git-ignore)
  và incident mode tự động (pool ≥ 50 %, connection bị giữ lâu, SQL timeout, deadlock, chờ lock ≥ 5 s, CPU/memory cao).
- Snapshot = delta theo database, statement (query_hash), procedure, function, missing-index group; plan mức statement cho top 5,
  parse tìm MissingIndex, PlanAffectingConvert, Key/RID Lookup, scan lớn, spill. Bản nháp index không bao giờ được thực thi.
- Danh sách lưu bền qua restart: To fix (procedure/function/query/missing index/trang chậm), Slow moments (cái gì bận vào lúc chậm),
  BlockingTop, kèm retention và "Start a new list".
- Phân tích tự động khi SQL timeout (-2), deadlock (1205, chờ DeadlockCollector, fallback 180 s), hang (≥ 10 request chạy ≥ 30 s),
  max pool size (cooldown riêng, xử lý đầu tiên trong tick).
- Đọc DMV định kỳ bị hoãn khi SQL CPU cao; lần đọc > 5 s dời lần sau sang 60 phút.

## Kiểm chứng (Verification)
- Build MSBuild Debug OK. IIS Express + DB dev: blocking thật bằng bảng ##temp → incident mode và finding đúng; deadlock thật được
  capture kèm victim, hai statement và key lock; SQL timeout thật (WAITFOR) → phân tích sau 10 s; deadlock → phân tích sau 64 s kèm graph.
- Microbenchmark hot path 0.16-0.5 µs/SQL; A/B load test 50/100/200 user On/Off trong mức nhiễu (≈3 200-3 480 req/s, 0 lỗi).
- Harness reflection: connection leak giả bị thu gom và sweep; 2 000 open/close song song kết thúc ở 0; Analyzer "100 of 100 … 90 not tracked";
  hang 9 → không, 12 → có; Off: thread dừng trong 23 ms; Missing index cost: 116/152 có cost sau lần đọc đầu, top khớp query DBA.
- CHƯA làm: session HRM thật trên trình duyệt, load test với user đã xác thực, cạn pool thật, SQL 2005/2008R2/2016/2017 (chỉ review tĩnh).

## Hướng đi sai (Dead ends)
- Test job-context trong PowerShell (Add-Type + AssemblyResolve) crash "Process is terminated due to StackOverflowException":
  lỗi của PowerShell, không phải module. Dùng console app csc.
- Test harness gọi thẳng AddIndexes không bắt được lỗi cost = 0; phải test qua Feed + Load (file thật) + Statistics() thật.
- Query test 1 ms bị cắt khỏi danh sách 300 query nặng nhất và trông như "không được ghi lại": dùng query đủ nặng.
- Scan `CONVERT(nvarchar, ID) LIKE` trên bảng 2.2 M dòng tốn ~111 s CPU trên dev server dùng chung: dùng query nhẹ hơn để test delta.
- Load test qua Login.aspx mất ~32 s (gọi WebAPI không chạy) và ghi audit vào DB dùng chung: dùng redirect ẩn danh của BasicForm.aspx.
- SELECT test với kiểu parameter sai ("Operand type clash: uniqueidentifier is incompatible with int").

## Lần sau (Next time)
Đọc phần "Findings" của snapshot trước; dữ liệu đằng sau mỗi finding đều có liên kết. Với công việc DMV, luôn lọc theo database
(plan_attributes dbid / database_id), loại statement sys.dm_, và luôn có baseline trước khi tính delta.
Test blocking/deadlock bằng bảng ##global temp trong ngữ cảnh DB HRM (không ghi vào bảng HRM).
Test harness khởi động runtime phải ghi `{"Enabled":true}` vào settings.json trước.
IIS Express bị VS dừng: chạy `iisexpress.exe /config:".vs\Cadena HRM 5.0\config\applicationhost.config" /site:"Cadena.WebApp"`.
