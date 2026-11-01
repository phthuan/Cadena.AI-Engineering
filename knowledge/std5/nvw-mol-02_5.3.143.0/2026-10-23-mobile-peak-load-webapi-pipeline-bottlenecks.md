---
title: ESS / Mobile chậm, CPU và RAM cao khi hàng nghìn người dùng đăng nhập lúc chốt timesheet / tính lương — kiểm tra token mỗi request, logging và workflow N+1 trong Cadena.WebAPI
project: std5
branch: NVW-MOL-02_5.3.143.0
type: performance
keywords: [DefaultDelegatingHandler, ApiPermissionHelper, GetUserToken, DeleteUserTokenExpire, SaveUserTokenDetail, GetUserByID, Security_UserTokens, Security_UserTokenDetails, ValidateTokenQuery, ValidateAppTokenQuery, LogRequestInfo, FileLogger, GetPendingButtons, WorkflowHandler, Request.ID.ToString(), S_ESS_LoadTimeSheet, F_Lib_GetValueByLanguageCode, F_Lib_GetValueFixByLanguageCode, F_LIB_GetEffectiveDateRangeOfEmployee, GetPendingActionMobileQuery, GetESSTimesheetQuery, GetFilterDataWFByCurrentUserQueryHandler, ETag GetMd5, EnableService]
files: [Cadena HRM 5.0/Services/Cadena.WebAPI/DelegatingHandlers/DefaultDelegatingHandler.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/Helpers/APIPermissionHelper.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/Helpers/DelegatingHandlerHelper.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/DelegatingHandlers/AuthenticationDelegatingHandler.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/Global.asax.cs, Cadena HRM 5.0/Cadena.BusinessLayer/API/Handlers/ValidateTokenQueryHandler.cs, Cadena HRM 5.0/Cadena.Core/Logging/Providers/FileLogger.cs, Cadena HRM 5.0/Cadena.BusinessLayer/AdvanceWorkflow/WorkflowHandlers/IWorkflowHandler.cs, Cadena HRM 5.0/Cadena.BusinessLayer/ESS/Handlers/Alert/GetPendingActionQueryHandler.cs, Cadena HRM 5.0/Cadena.BusinessLayer/ESS/Handlers/Timesheet/GetESSTimesheetQueryHandler.cs, Cadena HRM 5.0/Cadena.BusinessLayer/Commons/Handlers/GetFilterDataWFByCurrentUserQueryHandler.cs, Cadena HRM 5.0/Cadena.SQLScripts/3.SPFunctionsViews/S_ESS_LoadTimeSheet.sql]
commit: (chỉ review, không thay đổi code)
date: 2026-10-23
author: Thuan Pham Ngoc
status: active
confidence: high
---

## Triệu chứng (Symptom)
Branch NVW-MOL-02_5.3.143.0: lúc chốt timesheet / phân tích lương, khoảng 7k người dùng truy cập ESS / Mobile cùng lúc
(nghỉ phép, realtime, timesheet, tăng ca; quản lý phê duyệt). Hệ thống treo hoặc chậm, CPU và RAM tăng cao.

## Nguyên nhân gốc (Root cause)
Tìm ra bằng đọc code và static scan; cần DMV / profiler production để xếp hạng.

Chi phí cố định trên MỌI request ESS/Mobile (DefaultDelegatingHandler.SendAsync):
- `ApiPermissionHelper.GetUserToken`: `Token.ToLower() == x || RefreshToken.ToLower() == x` trên Security_UserTokens. LOWER() trên cột
  không seek được, và script không có index trên Token / RefreshToken / UserID / ExpiredOn: mỗi request scan bảng.
- `DeleteUserTokenExpire` chạy ở mọi request: 2 SELECT + một DELETE cho mỗi dòng, trong session riêng. Vòng lặp thứ hai dựng
  `DELETE Security_UserTokens ...` nhưng không gọi ExecuteUpdate (dòng ~187), nên các dòng đó không bao giờ bị xóa.
- Mỗi helper (GetUserToken, DeleteUserTokenExpire, GetUserByID, GetUserTokenDetail, SaveUserTokenDetail) mở session RIÊNG:
  một request giữ nhiều pooled connection cùng lúc, cộng ISession theo request scope.
- `SaveUserTokenDetail` (thao tác ghi) trên mọi master API ([HasDetailApi]); TokenSecond là nvarchar(max), không có index trên UserTokenID.
- ETag: `response.Content.ReadAsStringAsync().Result.GetMd5()` buffer và hash toàn bộ JSON của mọi response.
- `DelegatingHandlerHelper.LogRequestInfo` → Log.Warn 2-3 lần mỗi request; FileLogger mở file cho mỗi entry không có lock,
  gặp IOException thì retry tới 20 lần không delay và nuốt lỗi: tốn CPU khi tải đồng thời (logLevel Infor nên Warn được ghi).
- Bug thread-safety: DefaultDelegatingHandler là MỘT instance (`config.MessageHandlers.Add(new ...)`) nhưng giữ state theo request
  trong field `_accessTokenValues` / `_userToken`: request A có thể đọc user của request B.
- Route generic cũ (Authentication/CommandDelegatingHandler): ValidateAppTokenQuery + ValidateTokenQuery (session thứ hai) ở mọi lời gọi.

Workflow / phê duyệt:
- GetPendingActionMobileQuery gọi `WorkflowHandler.GetPendingButtons` cho TỪNG dòng; mỗi lời gọi mở session mới và lọc
  `string.Compare(x.Request.ID.ToString(), id) == 0` → CAST(column AS nvarchar), không dùng được index; sau đó lazy load ActorUser / ActorGroup
  + CheckUserBelongGroupUser từng dòng. `Request.ID.ToString()` xuất hiện ở 53 chỗ trong Cadena.BusinessLayer.
- Không có index trên ActorUserID/ActorGroupID/RequestID của Setting_*WFs (Leave/OverTime/InvalidTimeSheet/TIMShiftDetail/ExpenseClaim/Profile/Resignation),
  Setting_WorkflowGroupUsers(UserID), BEN_ExpenseClaimDetails(ExpenseClaimID), ESS_RequestEmployeeTIMRecords(EmployeeID, RecordDate).
- Commit 4dc21b5 ("1 API for ESS / Mobile"): GetFilterDataWFByCurrentUserQueryHandler tải TOÀN BỘ Transaction IsActiveTransaction và
  ManagersOrgStructureActive (không lọc tenant / nhân viên) mỗi khi có nhiều request ID.

Màn hình timesheet (S_ESS_LoadTimeSheet + S_ESS_LoadTimeSheet_Output_OT_ParameterV2):
- ~6 scalar UDF có truy cập dữ liệu cho mỗi dòng ngày (F_Lib_GetValueByLanguageCode dùng trong 378 file SQL): chạy từng dòng
  và ép plan serial trừ khi SQL 2019+ inline được.
- Join multi-statement TVF F_LIB_GetEffectiveDateRangeOfEmployee (ước lượng cardinality kém); ~10 OUTER APPLY mỗi ngày;
  C# lazy-load WorkflowStatus, TIMShiftDetailStatus, LastModifiedBy.Employee trong vòng lặp (N+1).

Điểm nóng load-all khác: GetEmployeeDashboardInforQueryHandler.GetListEmployeeLeaves (`Query<EmployeeTIMLeave>().ToList().Where(...)`),
GetOvertimeRemainingQueryHandler.LoadData, GetESSRealTimeAttendanceQueryHandler:90, GetDataEmployeeProfileQueryHandler /
SubmitEmployeeProfileESSCommandHandler (`.ToList().Where`).

Background job dùng chung SQL Server cùng lúc (xem knowledge/std5/_shared/2026-10-23-hang-max-pool-size-suspects-and-monitoring-design.md): WebAPI không có key
EnableService nên mặc định true và Global.asax.cs gọi jobScheduler.Start(); phân tích timesheet/lương chạy bên trong web process.

## Cách sửa (Fix)
Chưa áp dụng (chỉ review). Thứ tự đề xuất:
1. Cache tra cứu token (MemoryCache, key là hash token, TTL ngắn); bỏ ToLower() (token được sinh ra, so sánh chính xác); index
   Security_UserTokens(Token) INCLUDE(...) / (UserID, ExpiredOn) và Security_UserTokenDetails(UserTokenID); chuyển DeleteUserTokenExpire
   sang job (và thêm ExecuteUpdate còn thiếu); dùng lại session của request.
2. DefaultDelegatingHandler stateless (giá trị theo request trong `request.Properties`).
3. Logging: chỉ Warn cho response khác 200, writer async/có lock, bỏ vòng retry.
4. ETag chỉ cho GET endpoint opt-in, hoặc bỏ.
5. GetPendingButtons: một batch query cho mỗi danh sách (`RequestID IN (...)`), so sánh Guid, preload thành viên group; index các bảng *WFs.
6. S_ESS_LoadTimeSheet: thay scalar UDF bằng JOIN / inline TVF, multi-statement TVF bằng inline TVF hoặc temp table; sửa lazy load bằng Fetch.
7. Lọc phần preload của 4dc21b5 theo nhân viên của các request.
8. Chuyển Quartz ra khỏi WebAPI/WebApp (EnableService=false), chạy phân tích trong BackgroundJobs với pool / Application Name riêng.

## Kiểm chứng (Verification)
Chỉ đọc code và static scan, không có load test hay DMV production. Static scan (script Node, 16k file .cs + 6k .sql, ~16 s) map
controller E*/PendingAction/Dashboard/ESSMain/Auth → Query/Command → handler → SP lồng nhau: hot path 196 handler, 61 SP;
N+1 trong vòng lặp 38, filter `.ToString()` của workflow 30, load-all entity lớn 19, `ToLower()` tra token 4.
Đo trước khi sửa: chạy HangDiagnostics (nằm ngoài source repo) 03 (top SP/query) và 05 (waits) trong giờ cao điểm, và các DMV missing-index.

## Hướng đi sai (Dead ends)
- `Cadena HRM 5.0/MobileApp` (Cordova) là legacy, không có tên Query/Command nào. App mobile hiện tại gọi route E*Controller (header Caller: Mobile)
  qua DefaultDelegatingHandler.
- DataTranslationManager.GetData: nghi gọi DB mỗi dòng, nhưng được cache 30 phút theo translationID (kể cả kết quả rỗng). Không phải nguyên nhân chính.
- Grep index bằng regex một dòng bỏ sót `CREATE INDEX ... ON [dbo].[T]` + xuống dòng + `(`: nối các dòng trước (`tr '\n' ' '`).
- Static scan cho false positive: bảng lookup bị tính là "load all" (loại *Status/*Type/*Mode), ternary cache-hoặc-DB, `CASE WHEN ISNULL()`
  bị tính là non-sargable, PK không parse được ở một số script CREATE TABLE; kiểm tra index theo SP+table ("không index nào bắt đầu bằng cột được lọc"),
  không theo từng cột. Script SQL có thể không khớp DB: kiểm tra `sys.indexes`.

## Lần sau (Next time)
Với "ESS/Mobile chậm khi có tải", xem DefaultDelegatingHandler + APIPermissionHelper trước (chi phí cố định × mọi request),
sau đó GetPendingButtons (màn hình quản lý), rồi S_ESS_LoadTimeSheet. Xác nhận bằng sys.dm_exec_query_stats sắp theo total_worker_time
và execution_count trong giờ cao điểm: query token sẽ có execution_count rất cao.
