---
title: Report Payroll Master File Change mở chậm — SP gọi F_STA_SelectAllTransactionHaveMaxSequenceOnDate(SE.ID, ...) theo từng nhân viên trong APPLY; lấy giao dịch 1 lần vào #Transaction
project: std5
type: performance
keywords: [F_STA_SelectAllTransactionHaveMaxSequenceOnDate, OUTER APPLY, CROSS APPLY, S_PAY_GetEmpHaveOtherTransChangeByPeriod, S_PAY_GetEmpNewHireByPeriod, S_PAY_GetEmpResignedByPeriod, PayrollMasterFileChangeReport, F_STA_SelectLastTransactions, RowID, report chậm, mở report chậm, temp procedure collation conflict, Cannot resolve the collation conflict, IO_COMPLETION, mở lần đầu chậm, lần 2 nhanh, WITH RECOMPILE, multi-statement TVF, shared server I/O]
files: [Cadena HRM 5.0/Cadena.SQLScripts/3.SPFunctionsViews/S_PAY_GetEmpHaveOtherTransChangeByPeriod.sql, Cadena HRM 5.0/Cadena.SQLScripts/3.SPFunctionsViews/S_PAY_GetEmpNewHireByPeriod.sql, Cadena HRM 5.0/Cadena.SQLScripts/3.SPFunctionsViews/S_PAY_GetEmpResignedByPeriod.sql]
commit:
date: 2026-10-28
author: Thuan Pham Ngoc (with Claude Code)
status: active
---

## Triệu chứng (Symptom)
Payroll \ Payroll Reports \ Payroll Master File Change mở chậm (19-71s SQL cho 5 SP, kỳ 05/2026, company 388).
Phần III (S_PAY_GetEmpHaveOtherTransChangeByPeriod) chiếm 13-39s.

## Nguyên nhân gốc (Root cause)
SP lặp qua Staffing_Employees (toàn bộ nhân viên mọi company) và trong OUTER/CROSS APPLY gọi inline TVF
F_STA_SelectAllTransactionHaveMaxSequenceOnDate(SE.ID, CompanyID, TenantID) — phần III gọi 2 lần (cur, pre) để so lương với giao dịch liền trước.
Mỗi lần gọi phải xếp hạng (ROW_NUMBER) toàn bộ giao dịch của nhân viên đó. Đo: gọi theo từng nhân viên cho 1.525 người ~2.5s/lượt.
TVF hỗ trợ @valEmployeeID = NULL (tất cả nhân viên của company); RowID = ROW_NUMBER PARTITION BY EmployeeID nên gọi 1 lần cho ra cùng RowID.

## Cách sửa (Fix)
Trong 3 SP: sau khi tạo #Employee, lấy giao dịch 1 lần:
`SELECT <cột cần> INTO #Transaction FROM F_STA_SelectAllTransactionHaveMaxSequenceOnDate(NULL, @CompanyID, @TenantID) T WHERE EXISTS (#Employee)`
+ clustered index (EmployeeID[, RowID]); trong APPLY thay lời gọi TVF bằng #Transaction và thêm `EmployeeID = SE.ID`
(phần III: join pre thêm `pre.EmployeeID = cur.EmployeeID`). Giữ nguyên join, filter, cột, ORDER BY, join #Employee (giữ cả trùng lặp nếu có).

## Kiểm chứng (Verification)
So sánh SP cũ trên DB với thân SP mới (chạy qua sp_executesql, trong transaction rollback, không tạo object):
số dòng + EXCEPT 2 chiều trên mọi cột kèm số thứ tự dòng (rn IDENTITY khi INSERT EXEC) -> 0 khác biệt cho:
- III: 5 kỳ 01-05/2026 admin + 05/2026 non-admin (40 org) — 129/492/17/10/26/114 dòng.
- I, II: 5 kỳ admin + 05/2026 non-admin.
Thời gian (cache nóng): III 13s -> ~1s; I 1.1-2.0s -> 0.7-0.9s; II 1.8-3.5s -> 0.5-0.7s. Tổng 5 SP kỳ 05/2026: ~19s -> ~5.5s.
Repo SP == DB SP (so sánh thân đã chuẩn hóa khoảng trắng) trước khi sửa. Chưa chạy trên UI.

## Hướng đi sai (Dead ends)
- Tạo SP mới dạng temporary procedure (#proc) để so sánh: lỗi "Cannot resolve the collation conflict between Latin1_General_100_CI_AS
  and SQL_Latin1_General_CP1_CI_AS" (temp proc compile theo collation của tempdb). Dùng sp_executesql với thân SP + danh sách tham số.
- Lọc trước theo #Employee một mình chỉ bớt ~40% (2.494 -> 1.525 nhân viên); lợi ích chính là bỏ gọi TVF theo từng dòng.

## Phần còn lại sau khi tối ưu (đo 2026-10-28)
- 5 SP ~5.5s, trong đó F_STA_SelectLastTransactions (~0.6s/lần) được tính lại ở mỗi SP để tạo #Employee (4 SP cùng tham số,
  Resigned khác tham số) và SP Allowance gọi thêm lần nữa trong CROSS APPLY -> ~3-3.7s là việc lặp lại.
- C# (benchmark C# với số dòng thật, ~1.900 dòng): EPPlus fill 0.4-0.5s, GetAsByteArray ~0.6s; định dạng theo cột thay vì từng dòng KHÔNG nhanh hơn.
  DevExpress LoadDocument lần đầu trong process 1.5-1.9s nhưng lần sau 0.2s (chi phí khởi tạo/JIT). ExportToPdf 2.4-3.1s là chi phí chính của download.

## SP V (Allowance) — bỏ lần gọi F_STA_SelectLastTransactions thứ hai (2026-10-28)
- Lần gọi trong CROSS APPLY khác tham số nhưng tương đương: hàm tự ISNULL EmployeeTypeID/WorkingTypeID/EmployeeStatusID về 0,
  F_SEC_EmployeeByPermissionUsers ISNULL EmployeeIDs về ''; khác thật duy nhất là @valIsUseDate (handler luôn true). Giữ nhánh gọi lại khi @valIsUseDate = 0.
- Gotcha: so sánh có thứ tự báo lệch 9-535 dòng nhưng nội dung (EXCEPT không thứ tự) = 0. Nguyên nhân: ORDER BY chỉ LocalEmployeeID,
  thứ tự các dòng phụ cấp của cùng nhân viên do plan quyết định — SP cũ chạy 2 lần cũng lệch 2 dòng. Thứ tự cũ ~ theo AllowanceID;
  thêm `ORDER BY SE.LocalEmployeeID, PA.ID, EA.ID` -> 0 lệch thứ tự ở 7 trường hợp. Handler OrderBy(AllowanceTypeName) là stable nên thứ tự SQL hiện lên report.
- 1.8s -> 1.1s.

## Khi dữ liệu tăng (10k -> 50k giao dịch)
- Đo trên bảng thật 10k: tạo #Transaction 28-47ms + index 15-23ms; F_STA_SelectLastTransactions 617-635ms/lần, mỗi SP (I-V) gọi 1 lần -> 5 lần mỗi lần mở report.
- Mô phỏng bảng tạm ×5/×10: build #Transaction tăng gần tuyến tính (65 -> 460 -> 1029ms), cách cũ (gọi theo nhân viên x2) tăng nhanh hơn.
  Mô phỏng KHÔNG tái hiện được chi phí tuyệt đối của bảng thật (cách cũ 0.46s trên bảng tạm vs 13s thật: bảng thật rộng ~45 cột, PK GUID).
- Rủi ro còn lại khi dữ liệu lớn: F_STA_SelectLastTransactions gọi 1 lần trong mỗi SP — chưa đo được khi 50k (không ghi dữ liệu giả lên DB dùng chung).

## Sau deploy: mở lần đầu 23s, lần 2 6s (đo 2026-10-29, DB ALM_PRO_HRM_261019 trên HRS05\SQL2022)
- 4 SP mới đã có trên DB. Chạy 5 SP liên tiếp (cùng tham số, plan đã cache) dao động 4.5s -> 23.5s giữa các lượt, KHÔNG đổi code/plan.
- Wait của session lúc chậm: IO_COMPLETION 2-5s mỗi SP (lúc nhanh ~0.1s); physical reads hằng định ~30/SP. Statement chậm (dm_exec_query_stats):
  `SELECT ... INTO #Employee FROM F_STA_SelectLastTransactions(...)` ở cả 5 SP (min 0.55-0.8s, lúc chậm 2.5-4.9s).
  F_STA_SelectLastTransactions là multi-statement TVF (table variable ~45 cột trong tempdb); DB compatibility_level = 100.
- Cùng lúc: session khác chạy job >22 phút ở DB khác (PAGEIOLATCH_*/WRITELOG), SQL max memory 10GB/48GB RAM -> đĩa server dev dùng chung bão hòa.
  => "Lần 2 nhanh do cache" chỉ đúng một phần; phần lớn chênh lệch là tranh chấp I/O của server dùng chung.
- Giảm phụ thuộc I/O trong code: gọi F_STA_SelectLastTransactions ít lần hơn (5 -> 2 bằng SP tổng trả nhiều result set).

## Hướng đi sai (Dead ends) — 2026-10-29
- So sánh 1 lượt "plan cache" (23s) với 1 lượt `WITH RECOMPILE` (5.6s) rồi kết luận plan xấu/parameter sniffing: SAI. Chạy xen kẽ 3 vòng
  thì cả hai đều lúc 5s lúc 24s. Luôn chạy nhiều lượt xen kẽ và xem wait stats (sys.dm_exec_session_wait_stats) trước khi kết luận.

## Lần sau (Next time)
Report chậm thất thường trên DB dev dùng chung: đo nhiều lượt + sys.dm_exec_session_wait_stats + sys.dm_exec_requests của server trước khi sửa code.
grep `F_STA_SelectAllTransactionHaveMaxSequenceOnDate(SE.ID` / `(ee.EmployeeID` trong SQLScripts — cùng pattern ở nhiều report khác.
Áp dụng cùng cách và kiểm chứng bằng harness so sánh cũ/mới (scratchpad cmp2.ps1: INSERT EXEC vào #o/#n có rn IDENTITY, EXCEPT 2 chiều).
