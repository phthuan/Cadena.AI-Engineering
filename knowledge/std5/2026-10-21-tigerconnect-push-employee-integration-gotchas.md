---
title: Gọi external API (TigerConnect ReciveAPI.aspx) sau khi thêm / import nhân viên - các bẫy trong BaseApiClient, session-per-request và thread của import job
project: std5
type: feature
keywords: [TigerConnect, CadenaConnectEmployeeSyncView, GetTigerConnectPendingEmployeesQuery, GetTigerConnectEmployeeSyncListQuery, TIM_TigerConnectEmployeeMachines, get_machine, SyncTigerConnectEmployeeMachinesCommandHandler, TigerConnectEmployeeMachineRepository, resend, ReciveAPI.aspx, PushEmployeesToTigerConnectCommandHandler, ITigerConnectApiClient, TigerConnectApiClient, BaseApiClient, JsonConvert.DeserializeObject, SessionPerRequestModule, NewEmployeeImporter, ImportDataJob, BootStrapper.Container, AddNewEmployeeView, InsertEmployee, MSB4062, Microsoft.Dependency.dll]
files: [Cadena HRM 5.0/Cadena.BusinessLayer/TigerConnectApi/Handlers/PushEmployeesToTigerConnectCommandHandler.cs, Cadena HRM 5.0/Cadena.Web/API/Consumer/TigerConnectApiClient.cs, Cadena HRM 5.0/Cadena.Core/WebApi/ITigerConnectApiClient.cs, Cadena HRM 5.0/Cadena.BusinessLayer/ImportData/NewEmployeeImporter.cs, Cadena HRM 5.0/Modules/Cadena.Modules.Staffing/Views/AddNewEmployeeView.ascx.cs]
commit:
date: 2026-10-21
author: Thuan Pham Ngoc
status: active
---

## Triệu chứng (Symptom)
Công việc tính năng, không phải bug: push nhân viên mới (Type "add") sang TigerConnect khi nhân viên được thêm trên màn hình hoặc được import.

## Nguyên nhân gốc (Root cause)
Những điều không hiển nhiên và sẽ làm hỏng một cách triển khai ngây thơ:
1. BaseApiClient.CallApiAsync luôn chạy JsonConvert.DeserializeObject<T> trên body và chỉ bắt AggregateException.
   TigerConnect trả về chuỗi "OK" thuần, nên một response 200 sẽ ném JsonReaderException.
2. Web request dùng SessionPerRequestModule: transaction (ReadUncommitted) được commit ở EndRequest, không phải bởi
   Mediator.Execute. Sau InsertEmployee dữ liệu vẫn chưa được commit, nên một handler được resolve trong cùng request
   phải đọc bằng ISession của request; một session mới sẽ không thấy dữ liệu đó một cách tin cậy.
3. NewEmployeeImporter.Import chạy trên một thread riêng do ImportDataJob khởi động (Quartz, trong process WebApp).
   Request scope (Mediator, ISession) có thể đã không còn; mỗi nhân viên được commit bằng session riêng của nó.
   Ngoài ra Import có một parameter tên _sessionFactory che khuất (shadow) field cùng tên (thường là null khi gọi từ job).
4. Không thể tham chiếu các type của Cadena.Web (TigerConnectApiClient) từ Cadena.BusinessLayer.
5. `sed -i` của Git Bash xóa CRLF khỏi toàn bộ file. Một file không có newline ở cuối còn bị thêm một CR lẻ ở EOF,
   và git khi đó báo `w/-text` cùng diff toàn bộ file.

## Cách sửa (Fix)
- ITigerConnectApiClient (Cadena.Core/WebApi) với PostJsonAsync trả về body thô; được implement bởi
  TigerConnectApiClient (Cadena.Web) và đăng ký `.As<ITigerConnectApiClient>()` trong ModuleRegister của Cadena.Web.
- 2026-10-29 (người dùng xác nhận): ReferenceID gửi sang TigerConnect (add/cnl/del, cùng ToCommands) = Staffing_Employees.ID,
  không phải LocalEmployeeID. ReferenceID của clock upload chiều ngược lại là AttendanceID (khác ý nghĩa).
- PushEmployeesToTigerConnectCommand + handler (ISessionFactory, IAppSetting, ITigerConnectApiClient), dùng session riêng.
  Không bao giờ ném exception; ghi log DataKeys và status. Bỏ qua khi TigerConnect.ApiUri rỗng. Batch 100, timeout 30 s.
  Ghi Staffing_Employees.TigerConnectPushStatus BIT NULL (NULL chưa push, 1 thành công, 0 thất bại) bằng raw SQL;
  EmployeeMapping là một ClassMap, nên cột này không cần property trên Employee.
- Bất đồng bộ: TigerConnectEmployeePushQueue.Enqueue chạy handler qua HostingEnvironment.QueueBackgroundWorkItem
  (Task.Run khi ở ngoài IIS), resolve mọi thứ từ BootStrapper.Container.
- AddNewEmployeeView: Context.AddOnRequestCompleted(_ => Enqueue(...)) sau một InsertEmployee thành công và không phải transfer.
  RequestCompleted chạy sau khi SessionPerRequestModule commit ở EndRequest; nếu rollback thì không tìm thấy gì để push.
- NewEmployeeImporter: Enqueue(employeeInserted) sau vòng lặp (mỗi nhân viên đã được commit).
- cnl: AdvanceEmployeeResignationWorkflowCommandHandler.UpdatePendingRequestData (phê duyệt cuối, status Resigned)
  gọi EnqueueCancel(resignationID). Lần push đọc lại resignation và chỉ gửi khi nó vẫn là Resigned;
  EffDateFrom = LastWorkingDate + 1 ngày.
- del: TransactionHandler.Handle(DeleteEmployee) gọi EnqueueDelete(_session, id) TRƯỚC S_STA_DeleteDataEmployee,
  vì SP xóa Staffing_Employees / EmployeeInformations. Lần push chỉ gửi nếu dòng nhân viên đã không còn
  (một lần xóa bị rollback không bao giờ gửi del, vì TigerConnect thực thi del như một lần xóa vĩnh viễn). EffDateFrom = hôm nay.
- cnl / del chạy sau request (HttpContext.AddOnRequestCompleted, hoặc chạy ngay khi không có HttpContext);
  các kiểm tra dùng transaction ReadCommitted để chúng chờ transaction đang commit thay vì đọc dòng dirty.
  TigerConnectPushStatus: add ghi 1/0 theo kết quả; cnl luôn ghi 0 (dù thế nào cũng không có quyền truy cập máy);
  del không ghi được vì dòng Staffing_Employees đã bị xóa.
- appSettings mới: TigerConnect.MachineCode (mặc định "*") và TigerConnect.PatternGroup.

## Kiểm chứng (Verification)
MSBuild Cadena.Modules.Staffing đã biên dịch Cadena.Core, Cadena.BusinessLayer, Cadena.Web và module (các dll đã được cập nhật).
Bước post-build Module.build của module thất bại với MSB4062 (thiếu Dlls\Microsoft.Dependency.dll trên máy này),
không liên quan tới thay đổi. Chưa chạy với TigerConnect hoặc database.

## Hướng đi sai (Dead ends)
- Dùng BaseApiClient.PostAsJsonAsync<string>: thất bại với body "OK" không phải JSON (xem root cause 1).
- Gọi Mediator.Execute từ thread của importer: ISession theo request scope có thể đã bị dispose.

## Thay đổi về performance (2026-10-21, cho các lần import 1-2k nhân viên)
- LoadEmployees là một câu SQL cho mỗi batch 100: ROW_NUMBER() OVER (PARTITION BY EmployeeID ORDER BY EffectiveDate DESC,
  Sequence DESC) trên Staffing_Transactions, loại trừ TransactionActionCatalogID = Resignation, chỉ lấy các cột scalar.
- Handler async từ đầu đến cuối (HandleAsync + await PostJsonAsync, không có Task.Run(...).Result) và nhận
  token của QueueBackgroundWorkItem: khi IIS shutdown nó dừng giữa các batch và ghi log các ID chưa gửi
  (các dòng add giữ TigerConnectPushStatus NULL).
- TigerConnectEmployeePushQueue giới hạn số lần push đồng thời là 2 (SemaphoreSlim), nên các lần phê duyệt hàng loạt xếp hàng thay vì
  mở N kết nối cùng lúc. Việc gộp (coalescing) theo request KHÔNG được thực hiện.

## Các phát hiện khi review performance (2026-10-21; ba mục dưới đây đã được xử lý bởi các thay đổi ở trên, trừ coalescing)
- ApproveMultipleEmployeeResignationCommandHandler gọi phê duyệt đơn lẻ cho mỗi request; mỗi lần gọi
  EnqueueCancel, nên N lần phê duyệt = N callback AddOnRequestCompleted = N lần push nền đồng thời, mỗi lần có
  DB connection và HTTP call riêng. Gộp theo request (HttpContext.Items) thành một command.
- LoadEmployees tải mọi dòng Staffing_Transactions không phải resignation (full entity + 4 fetch join) cho batch và
  chọn dòng mới nhất trong memory. ĐÍNH CHÍNH: Cadena.SQLScripts không có index bắt đầu bằng EmployeeID, nhưng database thật
  (HAS_HRM_CONS_20261015, schema giống production) có IX_Staffing_Transactions_EmployeeID (EmployeeID) và
  UQ_Employee_EffectiveDate_TransactionAction_Company_Tenant (EmployeeID, EffectiveDate, TransactionActionID, ...),
  nên query ROW_NUMBER seek theo EmployeeID; không cần index mới. Kiểm tra index trong sys.indexes, không chỉ trong script.
- Kích thước batch sau đó đặt thành 50 và HTTP timeout thành 100 s (= mặc định của HttpClient dùng chung; giá trị dài hơn không có tác dụng
  nếu không thay đổi SignletonHttpClient). Không retry, theo quyết định (một lần "add" bị retry có thể tạo trùng dòng ADD trong queue).
- Send dùng Task.Run(...).Result bên trong một background work item: hai thread pool cho mỗi batch, không được lợi gì từ async.

## Lần sau (Next time)
Để gọi bất kỳ external API nào sau khi nhân viên thay đổi, dùng lại pattern của PushEmployeesToTigerConnectCommandHandler:
ISession của request trên màn hình, session riêng + root container trên thread import. Sửa file CRLF bằng tool Edit,
không dùng sed; nếu đã dùng sed, kiểm tra `git ls-files --eol <file>` hiển thị w/crlf, không phải w/-text.

## Trang gửi lại (Resend page) (2026-10-22)
- Modules/Cadena.Modules.TimeAttendance/Views/CadenaConnectEmployeeSyncView.ascx (FormID C4B3BBAF-6AF0-4399-BB1B-10EAC5746F6A),
  sitemap Cadena.SQLScripts/5.SiteMaps/Sitemap_CadenaConnectEmployeeSync.sql dưới "Time Attendance ID Management"
  (866D24D4-62C0-4B1E-BE64-A51D00C68502; ParentID của nó là module Time Attendance, không phải dòng Data Setup 9FF89762...).
  Bản thân trang Time Attendance ID là CardIDManagementView.ascx (sitemap 52EC96B0..., chỉ có trong DB, không có script).
- Liệt kê TigerConnectPushStatus NULL/0 và LOẠI TRỪ EmployeeStatusID = 2 (đã nghỉ việc): cnl ghi 0, nên chỉ dùng "<> 1"
  sẽ gửi lại "add" cho nhân viên đã nghỉ và cấp lại quyền truy cập máy cho họ.
- Send / Send All đọc lại danh sách chờ ở phía server, sau đó gọi TigerConnectEmployeePushQueue.Enqueue (chạy nền).
  Enqueue giờ trả về số lượng đã xếp hàng và bỏ qua các ID đang được xử lý (static ConcurrentDictionary, được giải phóng trong
  finally của PushAsync) để double click không thể tạo trùng dòng ADD trên TigerConnect.
- Thông báo chung của trang: đặt grid.JSProperties["cpPageInformationMessage"]; onGlobalEndCallback của MasterDataForm.aspx hiển thị nó.
- Build module copy các view sang Cadena.WebApp/Modules/... (bị git-ignore). Đã kiểm chứng: MSBuild TimeAttendance + Staffing biên dịch thành công;
  SQL danh sách chờ đã chạy trên dev DB. Chưa chạy trên trình duyệt, chưa thực thi script sitemap.
- "Vẫn đang làm việc" phải được xác định từ dòng Staffing_Transactions mới nhất (ORDER BY EffectiveDate DESC, Sequence DESC, bất kỳ ngày nào)
  không phải là TransactionActionCatalog.Resignation (= 2): trên dev DB có 3 nhân viên có EmployeeStatusID = 1 nhưng transaction mới nhất
  là resignation (1 cái có ngày trong tương lai). ROW_NUMBER join = 38 ms trên 16k transaction; CROSS APPLY TOP 1 = 224 ms.
- QUYẾT ĐỊNH (2026-10-22, người dùng): trang gửi lại chỉ lọc theo Staffing_Employees.EmployeeStatusID <> 2, KHÔNG lọc theo
  transaction mới nhất. Trade-off đã biết: nhân viên vẫn Active theo status nhưng có transaction resignation (trong tương lai hoặc chưa được phản ánh)
  sẽ được liệt kê và có thể bị add lại.
- Review performance (2026-10-22): resend dùng TigerConnectEmployeePushQueue.EnqueueResend -> thêm ResendThrottle(1), nên một lần
  Send All dài chỉ giữ tối đa 1 trong 2 slot push và các lần push add/import/cnl/del vẫn chạy. Send các dòng được chọn
  lấy giao với danh sách mà grid đã tải trong cùng callback (callback của grid luôn rebind; một query riêng theo từng
  ID là việc thừa hoàn toàn). SQL danh sách chờ chỉ được dựng với các filter đang bật và điều kiện sargable
  "TigerConnectPushStatus IS NULL OR = 0" (index IX_Staffing_Employees_TenantID_TigerConnectPushStatus sau đó đã bị DROP theo quyết định: Staffing_Employees vốn đã có nhiều index trên DB khách hàng, chi phí ghi không đáng cho một trang admin hiếm khi dùng; dev DB OHM-01-HRM chỉ có PK, hãy kiểm tra DB khách hàng trước khi đánh giá số lượng index)
  (bản copy tempdb, 95% đã push: 267 reads scan -> 28 với index + ISNULL -> 7 với 2 seek).
  Các lookup Company / EmployeeStatus không được cache: 1 company, 3 status, phần dịch currency đã được cache.

## Push theo từng máy + get_machine (2026-10-29, người dùng duyệt) - THAY THẾ các mục TigerConnectPushStatus ở trên
- Cột Staffing_Employees.TigerConnectPushStatus đã bị DROP (script Staffing_Employees_DropTigerConnectPushStatus.sql).
  Trạng thái nằm trong TIM_TigerConnectEmployeeMachines (EmployeeID, MachineID unique, FK employee ON DELETE CASCADE):
  1 = NotPushed (gồm cả push lỗi; không có dòng cũng = NotPushed), 2 = Pushed (chờ get_machine kiểm tra), 3 = OnMachine.
- Máy đích = TIM_TigerConnectMachines với ActiveStatus = '1' VÀ ConnectionStatus = '1' (quyết định của người dùng).
  Setting TigerConnect.MachineCode đã bị xóa; PatternGroup lấy của máy, rỗng thì dùng TigerConnect.PatternGroup.
- add/import: gửi theo từng máy, chỉ các cặp chưa Pushed/OnMachine; OK -> 2, lỗi -> 1. Màn hình gửi kèm máy đang chọn
  (EnqueueResend(ids, machineID)); key chống trùng của queue = employeeID|machine.
- cnl/del: gửi tới mọi máy có trạng thái 2/3 của nhân viên (không còn "*"). Nhân viên chưa lên máy nào thì không gửi gì.
- get_machine: response là {"MachineCode": ["..."]} cho MỘT nhân viên -> mỗi nhân viên một request (song song tối đa 4,
  chạy đồng bộ trong callback của grid). Máy có trong list -> 3; máy đang 2/3 mà không có -> 1. MachineCode null / JSON lỗi
  = thất bại, KHÔNG reset (tránh reset hàng loạt khi TigerConnect trả lỗi dạng JSON khác).
- Code: TigerConnectEmployeeMachineRepository (SQL, dùng được cả ISession và IStatelessSession qua Func<string, ISQLQuery>),
  TigerConnectCommandBuilder, TigerConnectCommandSender (gửi + log, không ném exception).
- Đã build: BusinessLayer, TimeAttendance, TigerConnectApi, Cadena.Web; Staffing compile được (post-build MSB4062 như cũ).
  Chưa chạy trên DB/trình duyệt, chưa gọi TigerConnect thật. Format request của get_machine (MachineCode "*") chưa được xác nhận.

## Gán thẻ chấm công sau khi push (2026-10-29, người dùng yêu cầu)
- Time Attendance ID (TIM_Cards.Code) = Staffing_Employees.ID, để Clock/Upload (ReferenceID = AttendanceID) map được qua MappingRawData.
- TigerConnectEmployeeCardAssigner chạy sau khi push add thành công lên ít nhất một máy, mỗi nhân viên một ISession + transaction riêng:
  chưa có thẻ hiện hành -> tạo/tái dùng thẻ [EmployeeID] và gán từ hôm nay; thẻ hiện hành khác mã -> AssignToDate = hôm qua, gán thẻ mới từ hôm nay.
  Bỏ qua (log Warn): có assignment tương lai, thẻ hiện hành bắt đầu hôm nay, thẻ [EmployeeID] inactive/lost hoặc đang thuộc nhân viên khác.
- Dùng entity Card / EmployeeCard (không raw SQL) vì repo không có script CREATE TABLE của TIM_Cards / TIM_EmployeeCards.
  TIM_Cards có UQ_TIM_Code_TenantID; TIM_EmployeeCards không có unique, nên 2 lần push đồng thời cho cùng nhân viên (2 máy khác nhau) hiếm khi có thể tạo trùng assignment.
- AuditEventListener chỉ ghi audit khi UserAccount.Current != null, nên ISession trên thread nền không lỗi.
