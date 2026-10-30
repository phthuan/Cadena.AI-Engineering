---
title: ESS / Mobile chậm, CPU và RAM cao khi hàng nghìn người dùng đăng nhập lúc chốt timesheet / tính lương — kiểm tra token mỗi request, logging và workflow N+1 trong Cadena.WebAPI
project: std5
type: performance
keywords: [DefaultDelegatingHandler, ApiPermissionHelper, GetUserToken, DeleteUserTokenExpire, SaveUserTokenDetail, GetUserByID, Security_UserTokens, Security_UserTokenDetails, ValidateTokenQuery, ValidateAppTokenQuery, LogRequestInfo, FileLogger, GetPendingButtons, WorkflowHandler, Request.ID.ToString(), S_ESS_LoadTimeSheet, F_Lib_GetValueByLanguageCode, F_Lib_GetValueFixByLanguageCode, F_LIB_GetEffectiveDateRangeOfEmployee, GetPendingActionMobileQuery, GetESSTimesheetQuery, GetFilterDataWFByCurrentUserQueryHandler, ETag GetMd5, EnableService]
files: [Cadena HRM 5.0/Services/Cadena.WebAPI/DelegatingHandlers/DefaultDelegatingHandler.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/Helpers/APIPermissionHelper.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/Helpers/DelegatingHandlerHelper.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/DelegatingHandlers/AuthenticationDelegatingHandler.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/Global.asax.cs, Cadena HRM 5.0/Cadena.BusinessLayer/API/Handlers/ValidateTokenQueryHandler.cs, Cadena HRM 5.0/Cadena.Core/Logging/Providers/FileLogger.cs, Cadena HRM 5.0/Cadena.BusinessLayer/AdvanceWorkflow/WorkflowHandlers/IWorkflowHandler.cs, Cadena HRM 5.0/Cadena.BusinessLayer/ESS/Handlers/Alert/GetPendingActionQueryHandler.cs, Cadena HRM 5.0/Cadena.BusinessLayer/ESS/Handlers/Timesheet/GetESSTimesheetQueryHandler.cs, Cadena HRM 5.0/Cadena.BusinessLayer/Commons/Handlers/GetFilterDataWFByCurrentUserQueryHandler.cs, Cadena HRM 5.0/Cadena.SQLScripts/3.SPFunctionsViews/S_ESS_LoadTimeSheet.sql]
commit: (chỉ review, không thay đổi code)
date: 2026-10-23
author: Claude Code (session of phthuan136)
status: active
---

## Triệu chứng (Symptom)
MOL-02 (branch NVW-MOL-02_5.3.143.0): lúc chốt timesheet / phân tích lương, khoảng 7k người dùng truy cập ESS / Mobile cùng lúc
(nghỉ phép, realtime, timesheet, tăng ca; quản lý phê duyệt). Hệ thống bị treo hoặc chậm, CPU và RAM tăng cao.
Được yêu cầu review kiến trúc. Không có gì được đo trên production trong session này.

## Nguyên nhân gốc (Root cause)
Tìm ra bằng cách đọc code. Cần DMV / profiler của production để xếp hạng các mục.

Chi phí cố định trên MỌI request ESS/Mobile dùng attribute routing (DefaultDelegatingHandler.SendAsync):
- ApiPermissionHelper.GetUserToken: `Token.ToLower() == x || RefreshToken.ToLower() == x` trên Security_UserTokens. LOWER() trên
  cột khiến SQL không seek được, và dù sao script cũng không có index trên Token / RefreshToken / UserID / ExpiredOn, nên mỗi request đều scan bảng.
- DeleteUserTokenExpire chạy ở mọi request: 2 SELECT cộng một DELETE cho mỗi dòng, trong session riêng. Vòng lặp thứ hai dựng
  `DELETE Security_UserTokens ...` nhưng không bao giờ gọi ExecuteUpdate (dòng ~187), nên các dòng đó không bao giờ bị xóa.
- Mỗi helper (GetUserToken, DeleteUserTokenExpire, GetUserByID, GetUserTokenDetail, SaveUserTokenDetail) mở session RIÊNG
  của nó, nên một request dùng nhiều pooled connection cùng lúc, cộng thêm ISession theo request scope.
- SaveUserTokenDetail (một thao tác ghi) trên mọi master API ([HasDetailApi]); Security_UserTokenDetails.TokenSecond là nvarchar(max) và không có index trên UserTokenID.
- ETag: `response.Content.ReadAsStringAsync().Result.GetMd5()` trên mọi response, nên toàn bộ JSON bị buffer và hash sau khi mọi công việc DB đã xong.
- `DelegatingHandlerHelper.LogRequestInfo` → Log.Warn, được gọi 2-3 lần mỗi request. FileLogger mở file log theo ngày
  cho mỗi entry mà không có lock. Khi gặp IOException (file đang được dùng) nó retry tới 20 lần không có delay và nuốt lỗi, gây tốn CPU
  khi có tải đồng thời (logLevel của Web.config là Infor, nên Warn được ghi).
- Bug thread-safety: DefaultDelegatingHandler là một instance duy nhất (config.MessageHandlers.Add(new ...)) nhưng giữ state theo request trong
  các field `_accessTokenValues` / `_userToken` (CurrentUserID, CurrentTenantID). Khi chạy đồng thời, request A có thể đọc user của request B.
Route generic cũ (Authentication/CommandDelegatingHandler): ValidateAppTokenQuery + ValidateTokenQuery (mở session thứ hai) ở mọi lời gọi.

Workflow / phê duyệt (quản lý trực tiếp):
- GetPendingActionMobileQuery gọi WorkflowHandler.GetPendingButtons cho TỪNG dòng đang chờ. Mỗi lời gọi mở một session mới và lọc
  `string.Compare(x.Request.ID.ToString(), id) == 0`, biến thành CAST(column AS nvarchar) và không dùng được index. ToList() mọi kết quả khớp chạy
  trước, sau đó là lazy load ActorUser / ActorGroup + CheckUserBelongGroupUser cho từng dòng. Có 53 chỗ dùng `Request.ID.ToString()` trong Cadena.BusinessLayer.
- Script không có nonclustered index trên Setting_EmployeeRequestLeaveWFs / OverTimeWFs / InvalidTimeSheetWFs,
  ESS_RequestEmployeeTIMRecords(EmployeeID, RecordDate), hoặc Security_UserTokens*. Kiểm tra production bằng sys.indexes, vì script có thể không khớp với database.

Màn hình timesheet (GetESSTimesheetQuery → S_ESS_LoadTimeSheet + S_ESS_LoadTimeSheet_Output_OT_ParameterV2):
- Khoảng 6 scalar UDF có truy cập dữ liệu cho mỗi dòng ngày (F_Lib_GetValueByLanguageCode được dùng trong 378 file SQL, F_Lib_GetValueFixByLanguageCode trong 170).
  Chúng chạy từng dòng một và ép plan chạy serial trừ khi SQL 2019+ inline được chúng.
- Join với multi-statement TVF F_LIB_GetEffectiveDateRangeOfEmployee (table variable + tách chuỗi, ước lượng cardinality kém).
- Khoảng 10 OUTER APPLY mỗi ngày trên TIM_EmployeeTIMShiftDetails. Phía C# sau đó lazy-load WorkflowStatus, TIMShiftDetailStatus và
  LastModifiedBy.Employee bên trong vòng lặp (N+1).

Nguy cơ regression trong commit 4dc21b5 (2026-10-23, "Enhance Performance - 1 API for ESS / Mobile"):
GetFilterDataWFByCurrentUserQueryHandler giờ tải TOÀN BỘ `Transaction where IsActiveTransaction` và TOÀN BỘ ManagersOrgStructureActive
(không lọc theo tenant / nhân viên) vào session mỗi khi có nhiều hơn một request ID được truyền vào. Đó là RAM + CPU cho mỗi lời gọi.

Các background job dùng chung SQL Server vào cùng thời điểm: xem [[2026-10-23-hang-max-pool-size-suspects-and-monitoring-design]].
Trên branch này: WebApp EnableService=true. WebAPI không có key EnableService, mặc định là true, và Global.asax.cs gọi jobScheduler.Start().
23 file job dùng `new Thread(`, SystemThreadCapacity 3 (WebApp) / mặc định 4. Phân tích timesheet/lương do HR khởi động chạy bên trong web process.

## Cách sửa (Fix)
Chưa áp dụng (chỉ review). Thứ tự đề xuất:
1. Hot path: cache việc tra cứu token (MemoryCache với key là hash của token, TTL ngắn). Bỏ ToLower() khỏi query (token được
   sinh ra, nên so sánh chính xác). Thêm index trên Security_UserTokens(Token) INCLUDE(...) / (UserID, ExpiredOn), và trên
   Security_UserTokenDetails(UserTokenID). Chuyển DeleteUserTokenExpire sang một job (và thêm ExecuteUpdate còn thiếu). Dùng lại session của request.
2. Làm DefaultDelegatingHandler thành stateless (giữ các giá trị theo request trong request.Properties).
3. Logging: chỉ Warn cho response khác 200, dùng NLog provider hoặc một writer async/có lock, và bỏ vòng retry quay liên tục.
4. ETag: chỉ tính cho các GET endpoint chủ động bật (opt-in), hoặc bỏ đi.
5. GetPendingButtons: một batch query cho mỗi danh sách (WHERE RequestID IN (...)), so sánh Guid thay vì string, và preload thông tin thành viên group.
   Thêm index trên các bảng *WFs (RequestID, IsProcessed) INCLUDE (ActorUserID, ActorGroupID, WorkflowStepID, Sequence).
6. S_ESS_LoadTimeSheet: thay các scalar UDF bằng JOIN / inline TVF và multi-statement TVF bằng inline TVF hoặc temp table.
   Sửa các lazy load bằng Fetch.
7. Lọc phần preload của 4dc21b5 theo nhân viên của các request.
8. Chuyển Quartz ra khỏi WebAPI/WebApp (EnableService=false) và chạy phân tích trong BackgroundJobs với pool / Application Name riêng.

## Kiểm chứng (Verification)
Không có. Chỉ đọc code, không có load test, không có dữ liệu DMV của production. Các rule yêu cầu đo trước: chạy
`D:/Source Project/HRM-Tools/HangDiagnostics` (nằm ngoài source repo, không commit cùng HRM) 03 (top SP/query) và 05 (waits) trong giờ cao điểm, và kiểm tra các DMV missing-index.

## Hướng đi sai (Dead ends)
- `Cadena HRM 5.0/MobileApp` (Cordova) trong repo là legacy. Nó không có tên Query/Command nào. Ứng dụng mobile hiện tại gọi
  các route E*Controller của WebAPI (header Caller: Mobile) qua DefaultDelegatingHandler.
- DataTranslationManager.GetData: nghi ngờ mỗi dòng gọi DB một lần, nhưng nó được cache 30 phút theo translationID, và kết quả rỗng cũng được cache.
  Không phải nguyên nhân chính.
- Grep index bằng regex một dòng bỏ sót `CREATE INDEX ... ON [dbo].[T]` + xuống dòng + `(`. Hãy nối các dòng trước (tr '\n' ' ').

## Static scan (không truy cập server), 2026-10-23
Một script Node (máy dev không có Python) quét 16k file .cs và 6k file .sql trong khoảng 16 s. Nó map các controller E*/PendingAction/Dashboard/ESSMain/Auth → Query/Command
→ file handler (`IQueryHandler<X`) → `EXEC sp` → các SP lồng nhau. Hot path: 196 file handler, 61 SP. Sau khi tinh chỉnh, số lượng trên hot path là:
N+1 read trong vòng lặp 38, filter `.ToString()` của workflow trong LINQ 30 (67 trên toàn repo), tải toàn bảng các entity lớn 19, `ToLower()` trong LINQ 4 (tra cứu token).
Các nguồn false positive đã phải sửa: bảng lookup bị tính là "load all" (loại trừ *Status/*Type/*Mode...),
ternary cache-hoặc-DB (`DataWorkflowSetup?... : session.Query`), `CASE WHEN ISNULL()` bị tính là predicate non-sargable,
PK không được parse với một số script CREATE TABLE (filter trên `id` trông như không có index), và kiểm tra index theo từng cột (hãy kiểm tra theo SP+table: "không index nào bắt đầu bằng bất kỳ cột được lọc nào").
Các mục tiêu đã xác nhận từ scan: Setting_*WFs (Leave/OverTime/InvalidTimeSheet/TIMShiftDetail/ExpenseClaim/Profile/Resignation) KHÔNG có index trên
ActorUserID/ActorGroupID/RequestID; Setting_WorkflowGroupUsers(UserID); BEN_ExpenseClaimDetails(ExpenseClaimID);
Staffing_Transactions không có index bắt đầu bằng EmployeeID. Các điểm nóng load-all: GetEmployeeDashboardInforQueryHandler.GetListEmployeeLeaves
(`Query<EmployeeTIMLeave>().ToList().Where(...)`), GetOvertimeRemainingQueryHandler.LoadData, GetESSRealTimeAttendanceQueryHandler:90,
GetDataEmployeeProfileQueryHandler / SubmitEmployeeProfileESSCommandHandler (EmployeeBank/Relationship/Education `.ToList().Where`).

## Lần sau (Next time)
Với "ESS/Mobile chậm khi có tải", xem DefaultDelegatingHandler + APIPermissionHelper trước (chi phí cố định × mọi request),
sau đó GetPendingButtons (các màn hình của quản lý), rồi S_ESS_LoadTimeSheet. Xác nhận bằng sys.dm_exec_query_stats sắp xếp theo total_worker_time
và execution_count trong giờ cao điểm. Các query token sẽ có execution_count rất cao.
