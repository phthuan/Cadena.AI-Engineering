---
title: "Performance Monitoring vòng 2 (incident mode, SQL delta, plan, bản nháp index, deadlock, finding) — các bẫy DMV: query_stats toàn server, DMV query của chính monitor bị tính là tải HRM, lần đọc system_health đầu tiên chậm, lấy mẫu 1/N bị aliasing"
project: std5
type: feature
keywords: [Performance Monitoring, DiagnosticsRuntime, SqlServerProbe, SqlIncidentReport, PlanAnalyzer, IndexDraftBuilder, DeadlockCollector, Analyzer, WindowStats, DiagnosticsJobContext, JobListener, dm_exec_query_stats, dm_exec_plan_attributes, dbid, dm_exec_text_query_plan, MissingIndexGroup, PlanAffectingConvert, dm_db_missing_index_group_stats_query, fn_xe_file_target_read_file, system_health, xml_deadlock_report, currentdb, RING_BUFFER_SCHEDULER_MONITOR, GlobalMemoryStatusEx, CallContext.LogicalSetData, Process is terminated due to StackOverflowException, Operand type clash]
files: [Cadena HRM 5.0/Cadena.NHibernateProvider/Diagnostics/*.cs, Cadena HRM 5.0/Cadena.NHibernateProvider/Cadena.NHibernateProvider.csproj, Cadena HRM 5.0/Cadena.BusinessLayer/Scheduler/JobListener.cs, Cadena HRM 5.0/Cadena.WebApp/Views/PerformanceMonitoringView.ascx]
commit: (chưa commit — working tree của MAI-02_5.3.136.0)
date: 2026-10-24
author: Claude Code (session of phthuan136)
status: active
---

## Triệu chứng (Symptom)
Mục tiêu: khi khách hàng báo CPU / RAM cao / bị treo, dev mở System Setup > Performance Monitoring và đọc được
store / function / statement / missing index / blocking / bên giữ pool / job nào đã gây ra. Vòng 1 (xem
2026-10-23-in-app-performance-monitoring-implementation-gotchas.md) chỉ có các bảng dữ liệu thô và số liệu DMV cộng dồn.

## Nguyên nhân gốc (Root cause)
(Tính năng.) Các bẫy phát hiện khi xây dựng và test vòng 2 trên HRS05\SQL2022 (dev server dùng chung, nhiều database):
- sys.dm_exec_query_stats là TOÀN SERVER. Lần test đầu tiên "tìm thấy" 69 phút CPU trên TIM_EmployeeTIMShiftOTSummarizes và
  đổ lỗi cho MAI-02 — thực ra nó thuộc về HNA_PRO_260925 trên cùng server. Lọc bằng
  CROSS APPLY sys.dm_exec_plan_attributes(plan_handle) WHERE attribute = 'dbid' (tốn ~0.3-1 s với ~6000 plan).
- Các DMV query của chính monitor (và SSMS / script của DBA) chạy trong ngữ cảnh database HRM, nên chúng xuất hiện như các statement
  "HRM" đứng đầu. Loại bỏ các statement có text khớp \bsys\.(dm_|fn_xe_|database_query_store) trước khi xếp hạng.
- Deadlock: đọc mọi file system_health*.xel mất 22-60 s (gần chạm timeout 60 s). Đọc tăng dần (incremental) với
  fn_xe_file_target_read_file(pattern, NULL, @file, @offset) và lưu vị trí trong App_Data/Diagnostics/deadlock-position.json;
  lần đọc đầu tiên (chưa có vị trí) chỉ đọc file HIỆN TẠI (EventFileTarget/File/@name) → 4.9 s, các lần sau ~1.5 s.
  Frame ad-hoc chứa text "unknown": dùng inputbuf thay thế.
- Lấy mẫu 1-trên-N bằng một bộ đếm Interlocked round-robin bị aliasing với các vòng lặp lặp lại statement theo thứ tự cố định
  (N+1): chỉ 5 trên 50 statement từng được lấy mẫu, mỗi cái bị đếm 10 lần. Dùng random xorshift theo từng thread → số đếm theo từng
  statement nằm trong khoảng ±5 %.
- Quartz job khởi động `new Thread` bên trong Execute: một owner [ThreadStatic] không đi theo. CallContext.LogicalSetData trong
  JobListener.JobToBeExecuted được truyền sang các thread do job khởi động; FreeNamedDataSlot trong JobWasExecuted.
- Các job chạy lâu thường xuyên giữ một connection trong nhiều phút: điều kiện kích hoạt incident "connection held > 2 min" chỉ được
  tính cho HTTP lease (job dùng ngưỡng leak 10 phút).
- Mẫu CPU SQL của ring buffer là theo phút: một đợt tăng vọt ngắn hơn một phút có thể hiển thị 0 %.
- Review kiến trúc (cùng ngày): SqlNormalizer dùng 6 lượt regex (178 µs cho mỗi statement 1.2 KB) và cache tới
  20 000 SQL text thô (đo được 100 MB với SQL nối chuỗi: mỗi literal mới là một cache miss). Watchdog chạy trên một
  System.Threading.Timer = thread pool: khi HRM treo do thread-pool starvation thì nó sẽ không chạy. ConnectionTracker
  dùng ConcurrentDictionary.Count (lấy mọi lock) ở mỗi lần mở connection. Blocking được lấy mẫu mỗi 15 s nhưng
  watchdog tick mỗi 10 s → thực tế là mỗi 20 s, nên một lần chờ lock 45 s không bao giờ được thấy ở mức ≥ 30 s.

## Cách sửa (Fix)
- Một công tắc on/off duy nhất (Off tự quay lại sau 24 h) + incident mode tự động (pool ≥ 50 %, HTTP connection bị giữ
  > 2 phút, bất kỳ connection nào > 10 phút, pool/SQL timeout, deadlock, chờ lock ≥ 5 s, CPU / SQL CPU / memory cao) trong 10 phút:
  stack cho mỗi connection được mượn, ngưỡng slow-SQL 200 ms.
- Quá tải (CPU ≥ 95 % trong 1 phút hoặc memory guard): lấy mẫu random 1/N với trọng số N thay vì bỏ các SQL nhanh.
- 15 bucket một phút (WindowStats) → các trang "5 phút gần nhất" / SQL theo thời gian, số lần, fetch (số dòng đọc).
- Baseline của các counter SQL Server được lấy khi có cảnh báo sớm (CPU ≥ 70 %, incident mode) và được thay bởi mỗi snapshot;
  snapshot = delta theo database, statement (query_hash), procedure, function, missing-index group.
- Plan ở mức statement (dm_exec_text_query_plan) cho top 5 → lưu dưới dạng .sqlplan, parse để tìm MissingIndex,
  PlanAffectingConvert (Seek Plan), Key/RID Lookup, scan lớn, spill. Các bản nháp index được gộp theo key prefix, không bao giờ được thực thi.
- Analyzer: các finding dựa trên rule ở đầu mỗi snapshot và trên trang overview (không thêm SQL).
- Giá trị parameter của các SELECT chậm (không bao giờ với thao tác ghi, được che khi SQL chứa từ nhạy cảm).
- Các bản sửa từ review: normalizer một lượt không dùng regex (47 µs, nhanh hơn 3.8 lần; cùng key trên 9 edge case) và cache giới hạn
  ở ~2 M ký tự; watchdog chạy trên background thread riêng; bộ đếm lease Interlocked; blocking được lấy mẫu ở mọi tick khi
  có request bị block (dung sai 2 s trong trường hợp khác). dm_exec_plan_attributes được đo là rẻ (≈7 µs mỗi plan, 42 ms cho
  6 112 plan; toàn bộ query statistics 240 ms) → không cần thay đổi ở đó; dm_exec_sql_text.dbid chậm hơn và NULL ở 75 %.
- Review lần hai: RequestScope.CountSql (bộ đếm N+1, trên request thread) hash toàn bộ statement: 0.7 / 3.6 / 9.3 µs cho
  SQL 0.5 / 3 / 8 KB (không được benchmark RecordSql bao phủ). Giờ dùng một prefix comparer (độ dài + 256 ký tự, hash của 64 ký tự đầu
  + 32 ký tự cuối) và một lần lookup duy nhất: ~0.5 µs với mọi độ dài, số đếm không đổi. Overview gửi toàn bộ 360 điểm metric mỗi
  10 s (~157 KB, ~90 ms): giờ chỉ gửi các điểm mới (~1 KB). Plan bị giới hạn ở 1 MB và bỏ qua khi memory cao; thống kê theo giờ /
  window dùng chung key và chuỗi mẫu của "since start"; form chỉ được parse với các post form-urlencoded. Các query của SSMS
  object-explorer (catalog sys.*) bị báo cáo là statement HRM với finding sai "implicit conversion":
  các statement khớp (sys|INFORMATION_SCHEMA).w bị loại trừ.
- Danh sách statement theo request: mỗi bản ghi request chậm liệt kê 5 statement tốn kém nhất (+ statement lặp nhiều nhất) cùng các
  frame Cadena.* đã chạy chúng. StackTrace(false) đo được 20 / 43 / 67 µs ở độ sâu 30 / 80 / 150, nhưng ~190 µs mỗi lần khi có
  8 thread cùng capture (contention của CLR). Vì vậy stack chỉ được lấy khi một statement đạt 200 ms trong request,
  hoặc lặp ≥ 10 lần trong một request đã chạy ≥ 1 s; một lần cho mỗi statement, tối đa 5 mỗi request, không bao giờ khi
  quá tải. Chi phí mỗi SQL vẫn ~0.5 µs; request nhanh không lấy stack (benchmark: 0 stack dưới 1 s, 5 khi dài hơn).
  Stack connection ở incident mode giờ được lấy cho 1 trên 10 lần mượn.
- Bẫy về settings: Normalize() kẹp IncidentSlowSqlMs ở mức ≤ SlowSqlMs, nên việc hạ SlowSqlMs xuống 10 ms để test đã
  ghi đè vĩnh viễn IncidentSlowSqlMs thành 10 (thấy trên trang Settings). Chỉ kẹp trong một khoảng; dùng Math.Min lúc runtime.
  Max Pool Size giờ được đọc từ connection string của HRM (SqlConnectionStringBuilder.MaxPoolSize) thay vì gõ tay.
  Trang Settings: 10 setting chính + một phần "Advanced" đóng sẵn.
- Overview (2026-10-25, phản hồi của người dùng): không có chart; finding + "Analyze now" lên đầu; CPU / RAM chia theo máy và theo owner:
  CPU máy web qua GetSystemTimes so với w3wp, máy SQL qua ring buffer (SQL so với phần còn lại), RAM qua GlobalMemoryStatusEx và
  sys.dm_os_sys_memory + sys.dm_os_process_memory + sys.configurations max server memory. Rule OtherProcesses của Analyzer
  báo cáo CPU / RAM bị các process không phải HRM chiếm. Trên HRS05 nó thấy còn trống 2.7 GB trên 48 GB trong khi SQL2022 giữ 8.2 GB (max 9.8 GB):
  phần còn lại là các process khác (nhiều khả năng là các SQL instance khác trên host).
- Thu gọn phạm vi (2026-10-25, người dùng: "chỉ những gì cho biết request / store / function / query nào chậm, hoặc block /
  deadlock nào gây ra"): bỏ thống kê since-start và theo giờ (StatsPeriod, stats-*.json), file lịch sử metric,
  Waits/IO, Sessions, CPU-by-database, connections-by-owner, các bảng "SQL by executions / reading rows" và các counter không dùng.
  Chi phí nền mỗi SQL 0.67 → 0.28 µs. Trang: 8 tab, mọi cột có tooltip (title trên th) + một dòng chú giải dưới các
  bảng chính. File theo ngày chỉ được đọc khi danh sách trong memory rỗng (action sql trước đây là 1.5 MB ở mỗi lần mở).
- "Refresh làm tôi bị đăng xuất" (2026-10-25): HRM dùng <sessionState mode="InProc" timeout="20">, nên mỗi lần ứng dụng restart
  là mọi người bị đăng xuất. 9 lần restart trong ngày hôm đó khớp với các lần build dev (copy DLL vào bin → Application_End; lần cuối khớp tới
  từng giây) và các lần restart IIS Express. Đã kiểm chứng monitor không làm restart ứng dụng: mọi thao tác ghi của nó đều vào
  App_Data/Diagnostics (bị ASP.NET file-change notification bỏ qua), nó chỉ xóa file (không bao giờ xóa thư mục) và không bao giờ
  đụng tới session; ghi 11 file (settings, snapshots, plans, deadlock position) → cùng startedUtc, không có Application_End mới
  trong Logs/<date>.log. Lưu ý: PerformanceMonitoring.axd không có session, nên một trang để mở không gia hạn được
  session HRM 20 phút (giống mọi trang HRM đang idle). Lý do shutdown không có trong Event Log trên máy dev
  (HRM không tạo được source ".NET Runtime"); hãy dùng các dòng Application_End / Application_Start trong Logs/<date>.log.
- Tab "Top slow (to fix)" (2026-10-25): cửa sổ 5 phút dịch chuyển mỗi 10 s và plan cache của SQL Server quên plan
  (restart, memory pressure, recompile), nên một statement chậm có thể biến mất trước khi có ai sửa. TopSlow.cs giữ
  500 statement / 300 trang tệ nhất theo tổng thời gian cùng lần chạy tệ nhất của chúng (thời gian, user, parameter, code), lần đầu / lần cuối thấy;
  lưu vào App_Data/Diagnostics/top-slow.json mỗi 5 phút và ở Application_End, tải lại khi start, bỏ đi sau
  RetentionDays mà không có lần chạy nào; "Start a new list" sau một bản release. Bẫy: format chuỗi timestamp cho mỗi statement
  (Json.Iso) làm chi phí nền tăng gấp ba (0.28 → 1.09 µs); giữ DateTime và chỉ format khi trang đọc (0.46 µs).
- Tab "To fix" (2026-10-25) thay thế Top slow / Slow requests / Slow SQL / Store-function-query: procedure, function,
  query, missing index (SqlServerTop.cs: đọc các DMV counter theo giờ + theo mỗi lần phân tích + theo yêu cầu, phần tăng so với
  lần đọc trước được cộng vào top-sql-server.json; lần đọc đầu tiên sau khi start import các entry chưa biết và chỉ
  đặt lại baseline cho các entry đã biết = không tính trùng, đã kiểm chứng) và các trang chậm trong code C# (TopSlow requests: % thời gian ngoài
  SQL; bỏ qua request trong 2 phút đầu sau khi start = thời gian biên dịch). Trang / parameter / code phía web được gắn theo
  tên procedure và Analyzer.MatchKey. Kết luận (verdict) theo các rule cố định (Slow ≥ 1 s, Heavy IO ≥ 100k page/lần chạy, Missing index?
  ≥ 1,000 page/dòng, Loop ≥ 20 lần chạy trong một request, Time in C# code ≥ 50 % của một trang ≥ 1 s) + "Only problems".
  Bẫy: StatementDetails nhận 30 hash mỗi lần gọi → đọc text theo lô; JavaScriptSerializer không đọc được thời gian dạng
  chuỗi ISO cũ thành DateTime (ra 0001-01-01) và lần lưu tiếp theo bỏ mọi entry vì "cũ hơn retention" →
  coi thời gian mặc định là "vừa thấy" khi tải. Method bên trong đoạn code C# chậm vẫn cần một profiler.

## Kiểm chứng (Verification)
- MSBuild Debug Cadena.WebApp kèm reference: thành công (chỉ có các warning cũ).
- IIS Express (port 17228) với MAI-02_HRM_CUS_07092026, API được gọi bằng token ký bằng secret App_Data local:
  snapshot thủ công 0.8-1.3 s (phần SQL 0.77-1.0 s); blocking thật qua bảng ##temp trong ngữ cảnh DB HRM → incident mode ở
  thời điểm chờ 21.8 s, snapshot "blocking" tự động ở 41.9 s, finding "session keeps a transaction open while idle and blocks 1
  request"; deadlock thật (##pm_d1/##pm_d2) được capture kèm victim, cả hai statement và key lock; snapshot delta cho thấy
  query test chiếm 100 % CPU của HRM với "scan of a large table"; tải .sqlplan OK; công tắc off/on OK.
- Microbenchmark hot path (console harness trên DLL đã build): 0.16 µs mỗi SQL trên request thread, 0.62 µs trên
  worker; khi quá tải 0.07 µs. Việc truyền tên job đã được kiểm tra bằng một console app csc.
- Script của trang: node --check + chạy trong Node với DOM stub và các API response đã ghi lại: không có lỗi runtime ở tab nào.
- CHƯA làm: một session đăng nhập HRM thật trên trình duyệt, load test với nhiều người dùng, SQL CPU ≥ 85 % (server dùng chung).

## Hướng đi sai (Dead ends)
- Chạy test job-context trong PowerShell (Add-Type + scriptblock AssemblyResolve) bị crash với "Process is terminated
  due to StackOverflowException" khi một thread khác resolve assembly: lỗi do PowerShell, không phải module. Hãy dùng console app csc.
- SELECT test với kiểu parameter không khớp ("Operand type clash: uniqueidentifier is incompatible with int").
- Một scan CONVERT(nvarchar, ID) LIKE trên TIM_EmployeeTIMShiftDetails (2.2 M dòng) tốn ~111 s CPU cho 10 lần chạy (parallel) trên
  dev server dùng chung: hãy dùng thứ gì nhẹ hơn cho test delta.

## Lần sau (Next time)
Đọc phần "Findings" của snapshot trước; dữ liệu đằng sau mỗi finding đều có liên kết. Với công việc DMV, luôn lọc theo database
(plan_attributes dbid / database_id) và loại trừ các statement sys.dm_. Test blocking/deadlock bằng bảng ##global temp trong
ngữ cảnh database HRM (không ghi vào bảng HRM): theo pattern của các scratch script make-lock.ps1 / pm-api.ps1.

## Cập nhật 2026-10-25: phiên bản SQL, load test, danh sách blocking được lưu giữ
- Tương thích SQL Server: dm_exec_sessions.open_transaction_count / database_id chỉ có từ 2012; file target của system_health
  cũng chỉ có từ 2012. Với 2008 R2 dùng sys.sysprocesses (open_tran, dbid) qua OUTER APPLY, và trả về tập rỗng khi
  không tìm thấy XE file pattern. Chỉ SQL 2022 (HRS05\SQL2022, CDV198) là truy cập được để thực thi; HRS03 2005/2008R2/2016/2017
  từ chối login: các phiên bản cũ hơn chỉ được review tĩnh.
- Load test local: Login.aspx mất ~32 s (gọi Cadena.WebAPI, vốn không chạy) và các lần login thất bại ghi dòng audit vào DB
  dùng chung. Hãy dùng redirect ẩn danh của BasicForm.aspx (~14 ms, không ghi DB) với một closed-loop csc LoadTest (scratch load-ab.ps1,
  ABA On/Off/On). Cách này đo overhead mỗi request của module, không phải 1–2k người dùng thật đã xác thực.
- Phát hiện bug worker: sleep cố định 1 s mỗi batch giới hạn worker ở 50,000 event/s. Xả liên tục (thức dậy sau mỗi
  vài event) thì lại tốn ~8 % throughput ở 100 người dùng. Cuối cùng: sleep cho tới khi queue đạt 1,024 (Enqueue set event)
  hoặc 1 s, chỉ tiếp tục xả không nghỉ khi còn backlog ≥ 1,024. Năng lực 397k (SQL 3 KB) – 1.1M (400 ký tự)
  statement/s; A/B 50/100/200 người dùng On so với Off nằm trong mức nhiễu (≈3,200–3,480 req/s, 0 lỗi, 0 dropped).
- BlockingTop (top-blocking.json): blocker có key là trang/job owner + SQL đã normalize, episode mới sau 60 s không thấy; deadlock
  có key là các phía đã sắp xếp × object, được nạp từ DeadlockCollector.Found. Tên helper `Text` xung đột với class Text → đã đổi tên.

## Cập nhật 2026-10-25 (tối): đọc định kỳ, baseline, treo
- Một lần phân tích đo "SQL Server đã làm gì" bằng statistics hiện tại trừ đi baseline. Khi chỉ có lần đọc To-fix theo giờ và
  baseline lấy khi CPU vượt 70 %, một đợt tăng vọt đột ngột không có baseline (số cộng dồn kể từ khi SQL start) và hai lần
  phân tích sát nhau đo được 0 phút. Cách sửa: lần đọc statistics mỗi 15 phút kiêm luôn baseline; giữ một baseline cũ hơn
  (cũ hơn >= 2 phút) và dùng nó khi baseline mới nhất chưa tới 2 phút. Đã kiểm chứng: hai snapshot thủ công cách nhau 1 s đều
  đo được 2.3 phút.
- "Start a new list" giữ lại SqlServerTop._previous, nên lần refresh ngay sau khi click cộng thêm tới một giờ hoạt động trước
  khi click. Cách sửa: Clear() đặt một cờ; lần Feed tiếp theo chỉ trở thành điểm bắt đầu. Hãy dùng các query test khác nhau về cấu trúc:
  `WHERE 1 = 1` và `WHERE 2 = 2` có cùng query_hash và trông giống như bug.
- Deadlock chỉ được đọc sau khi HRM nhận lỗi 1205: một deadlock mà victim là ứng dụng khác sẽ bị bỏ sót. Đọc định kỳ
  mỗi 15 phút (tăng dần từ vị trí đã lưu; lần đọc đầy đủ đầu tiên của file hiện tại mất 1.7 s trên dev).
- Cơ chế bảo vệ: các lần đọc định kỳ bị hoãn 5 phút khi SQL CPU >= SqlCpuSnapshotPercent (lần phân tích vẫn đọc); một lần đọc
  mất > 5 s sẽ dời lần tiếp theo sang 60 phút (có audit).
- Phân tích "hang": >= 10 request đang chạy trong >= 30 s (watchdog, đếm InFlight tốn cỡ µs). Đã test bằng một csc harness
  đặt các object RequestScope với StartTicks cũ (field readonly được đặt bằng reflection) vào InFlight: 9 → không có, 12 → hang.
- IIS Express local có thể bị VS dừng: khởi động bằng iisexpress.exe /config:".vs\Cadena HRM 5.0\config\applicationhost.config"
  /site:"Cadena.WebApp".
- Dữ liệu cũ quay lại trong To fix sau khi ứng dụng restart: lần đọc đầu tiên sau khi start đã import tổng cộng dồn
  (kể từ khi plan được cache, thường là nhiều ngày) của mọi key không có trong danh sách, nên "Start a new list" + restart lại import
  lịch sử. Cách sửa: khi đã tải được danh sách đã lưu, lần đọc đầu tiên chỉ là điểm bắt đầu; chỉ lần start đầu tiên thực sự
  (chưa có file) mới import tổng. Test bằng một query đủ nặng: danh sách query giữ 300 query nặng nhất, một query test 1 ms
  bị cắt bỏ khi danh sách đầy và trông như "không được ghi lại".
- Monitoring khi đã tắt giờ sẽ giữ trạng thái tắt (không tự quay lại sau 24 h), theo yêu cầu của người dùng.

## Cập nhật 2026-10-26: review "max pool size" — tracker giữ cho leak sống, mất snapshot, không thấy SqlConnection
Review kiến trúc với câu hỏi "nếu xảy ra max pool size, ta có biết được nguyên nhân không?" đã tìm ra ba lỗi (đã sửa, chưa commit):
- ConnectionTracker giữ mỗi connection NHibernate trong ConcurrentDictionary<IDbConnection, ...> (strong key). Một session
  không bao giờ được dispose thì bình thường sẽ bị thu gom và ADO.NET lấy lại pooled connection của nó; strong key khiến leak đó
  trở thành vĩnh viễn → chính monitor có thể làm đầy pool, và SqlClient NumberOfReclaimedConnections luôn là 0. Cách sửa: key =
  WeakKey (WeakReference + identity hash của RuntimeHelpers) với một comparer cũng chấp nhận connection đang sống khi lookup
  (lock-free, khác với ConditionalWeakTable có TryGetValue lấy lock trên .NET Framework — SetLastSql chạy cho mỗi statement).
  Watchdog Sweep() ở mỗi tick xóa các lease đã bị thu gom, audit "connection not closed", giữ 50 cái gần nhất cho snapshot
  (reclaimedConnections) và một finding "Connection leak" của Analyzer.
- Mọi snapshot tự động dùng chung một cooldown 5 phút và request "max-pool-size" đang chờ bị tiêu thụ trước khi kiểm tra:
  một snapshot blocking/CPU vài phút trước đó âm thầm làm rơi snapshot của sự cố. Cách sửa: max-pool-size có cooldown
  2 phút riêng và được xử lý đầu tiên trong tick. pool-high / hang giữ cooldown thông thường (chúng có thể kéo dài hàng giờ).
- Các connection mở trực tiếp bằng SqlConnection (DbBase không bao giờ đóng connection của nó — Cadena.Core/DbConnection/IDb.cs;
  ADONet; BulkCopyHelper) dùng chung pool CadenaDb nhưng không được nhìn thấy; finding báo "10 of 100 in use" trong khi pool đã
  đầy. Cách sửa không cần đụng vào code HRM: SqlServerProbe.Sessions() liệt kê mọi session của w3wp này (host_name = Workstation
  ID hoặc tên máy, host_process_id = PID, cả session đang sleeping, SQL gần nhất qua most_recent_sql_handle, open_tran qua sysprocesses),
  được chú thích bằng connection_id → owner NHibernate. Analyzer đếm các session SQL Server trên db HRM; các session không được track
  đều bị coi là "held by code" khi reason = max-pool-size, nếu không thì chỉ những session idle ≥ LeakSuspectMinutes hoặc có transaction đang mở
  (pooled connection đang idle cũng không được track).
Kiểm chứng: Cadena.NHibernateProvider MSBuild Debug OK. csc harness (scratch pooltest/PoolTest.cs) trên DLL đã build qua
reflection: connection giả bị leak được thu gom và sweep, connection đang sống được giữ, 2000 lần open/close song song kết thúc ở 0; Sessions() thấy 3
SqlConnection đang bị giữ bao gồm cả transaction đang mở (30 ms); Analyzer: 10 NH + 90 raw + 5 audit-db session → "100 of 100 ...
10 borrowed through NHibernate, 90 not tracked" + finding critical kèm SQL. CHƯA làm: chạy HRM thật / cạn pool thật.
Review tiếp theo (cùng ngày): (M1) finding về pool dùng max(inUse, SQL Server sessions); session bao gồm cả pooled connection đang idle
(được giữ 4-8 phút sau một đợt tăng vọt) → finding sai "critical 90 of 100" trên các snapshot thủ công / CPU. Giờ "held" = NHibernate
lease + các nghi vấn không được track (tất cả khi reason = max-pool-size, nếu không thì chỉ những cái có transaction đang mở hoặc idle ≥
LeakSuspectMinutes). (M2) Tab History không hiển thị sqlSessions / reclaimedConnections (link "Details" của finding không dẫn
tới đâu): đã thêm hai bảng trong PerformanceMonitoringView.ascx (các dòng idle-in-transaction được tô sáng). Đo được: weak key
+0.2 µs (1 thread) / +0.45 µs (8 thread) mỗi lần mở connection so với strong key; Sessions() 54 ms với 100 session (OUTER APPLY
sysprocesses = LEFT JOIN, không cần thay đổi). Các harness test pass; script của trang qua node --check OK; trang chưa được mở trên trình duyệt.
Tab "Slow moments" (2026-10-26, người dùng: tổng số trong To fix không cho biết cái gì bận VÀO LÚC HRM chậm): SlowMomentTop.cs
(slow-moments.json, RetentionDays, tối đa 300 entry) được nạp ở cuối TakeSnapshot từ dữ liệu snapshot (không thêm SQL):
các statement / procedure / function của sqlIncident (delta trong những phút trước lần phân tích; bỏ qua khi Cumulative = không có
baseline, nếu không thì nhiều ngày lịch sử sẽ lọt vào) + các statement đang chạy tại giây đó (bên trong một procedure → entry của procedure).
Key: q:+text đã normalize (dòng đang chạy không có query_hash, nên key theo text thống nhất cả hai), p:/f:+tên; một thời điểm chỉ được đếm
một lần cho mỗi entry (HashSet cho mỗi lần phân tích). Hiển thị số thời điểm, lý do ×n, CPU trong các thời điểm đó, % CPU HRM tệ nhất kèm link tới
snapshot đó (có thể đã bị xóa sau retention → renderSnapshot giờ hiển thị "removed"). Text DMV của monitor bị loại trừ bằng
SqlIncidentReport.MonitorQuery. Reflection harness (scratch SlowTest.cs) pass; trang chưa được mở trên trình duyệt.
Phân tích tự động khi SQL timeout / deadlock (2026-10-26): trước đây, -2 / 1205 chỉ bật incident mode (không có snapshot).
Giờ RecordSql yêu cầu "sql-timeout" ngay lập tức; "deadlock" chờ tới khi DeadlockCollector.Found được kích hoạt (system_health được ghi
trễ ~30 s, nên một snapshot ngay lập tức không có deadlock graph), fallback sau 180 s. Cooldown 5 phút thông thường; một
max-pool-size đang chờ không bao giờ bị chúng thay thế. Statement bị lỗi được truyền tới SlowMomentTop (Failures, kể cả khi
cooldown bỏ qua lần phân tích) vì một statement đã phải chờ thì không tốn CPU và bị thiếu trong Slow moments.
Đã kiểm chứng E2E trên SQL Server dev (scratch E2E.cs, timeout WAITFOR thật + deadlock bằng bảng ##temp): phân tích sql-timeout
10 s sau đó, phân tích deadlock 64 s sau đó KÈM graph system_health, cả hai đều có trong slow-moments.json với Failures = 1.
Off = mọi thứ dừng lại (2026-10-26, yêu cầu của người dùng "khi off tất cả process đều dừng, chỉ xem data cũ"): trước đây, Off chỉ
bỏ qua Observe — các thread worker + watchdog vẫn tick, Closed/RecordUnhandled/GetConnection dùng IsRunning, nên một
"max pool size" khi đang off để lại một snapshot đang chờ sẽ được kích hoạt (sai thời điểm) khi bật lại; các nút thủ công vẫn query
SQL Server. Giờ ApplySettings start/stop các thread (StartThreads / StopThreads với một ManualResetEvent theo từng thế hệ,
join, drain, SaveTop, sau đó ConnectionTracker.Reset, InFlight.Clear, xóa pending/deadlock-due/incident). Mọi hook dùng
IsCollecting. Handler.IsActive từ chối snapshot POST, fix/slow refresh|clear, deadlocklog POST, deadlocks; blocking bỏ qua
live query. Trang: banner OFF, các nút bị disable, không tự refresh. Không bật/tắt on/off từ chính watchdog
(đã bỏ RefreshEnabled: StopThreads join watchdog). Đã kiểm chứng bằng scratch OnOff.cs: các thread kết thúc trong 23 ms, không có gì
chạy trong 25 s khi off, thread mới khi bật lại, InUse không âm.
Mặc định OFF trên một deployment mới (2026-10-26): DiagnosticsSettings.Enabled giờ mặc định là false (trước là true). Start() tải
settings.json (thiếu hoặc không đọc được → giá trị mặc định → off) và lưu lại, nên lần deploy đầu tiên ghi Enabled:false và
không thread nào khởi động; khi người dùng lưu On, settings.json (App_Data/Diagnostics, bị git-ignore, không nằm trong deployment package)
giữ trạng thái đó qua các lần restart và deploy. Vì vậy xóa thư mục Diagnostics cũng sẽ tắt monitoring.
Các test harness khởi động runtime phải ghi {"Enabled":true} vào settings.json trước. _lastMetric khởi đầu là một
dictionary rỗng (không phải null): hãy kiểm tra Count, không kiểm tra null, để biết "chưa có gì chạy".

## Cập nhật 2026-10-27: cột Total_Cost_Impact của Missing indexes (To fix) bằng 0 dù query DBA trên DMV có số
Total_Cost_Impact = Asked × AvgTotalUserCost × avg_user_impact × 0.01 (AvgTotalUserCost = giá trị mới nhất, lưu trong top-sql-server.json).
Bẫy: SqlServerTop.Feed với `_restarted` (đã có file danh sách → lần đọc đầu sau mỗi lần start chỉ là mốc) `return` TRƯỚC AddIndexes,
nên cost của index đã lưu không được cập nhật tới lần đọc thứ hai (~17 phút sau start); thêm nữa AddIndexes chỉ cập nhật khi index được hỏi thêm.
Sửa: UpdateIndexCosts(current.MissingGroups) gọi ở cả nhánh `_restarted` và đầu AddIndexes. Test harness gọi thẳng AddIndexes KHÔNG bắt được
lỗi này — phải test qua Feed + Load (file thật) + Statistics() thật: 116/152 index có cost sau lần đọc đầu, top khớp query DBA
(Security_UserTokens 2181,94 so với 2186,14; lệch vì Asked tính từ khi danh sách bắt đầu, DBA tính user_seeks từ lúc SQL start).
36 index không còn trong DMV (SQL restart / đã tạo index) giữ cost 0 và nằm cuối.
