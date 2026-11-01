---
title: Report Payroll Master File Change mở chậm — SP gọi F_STA_SelectAllTransactionHaveMaxSequenceOnDate(SE.ID, ...) theo từng nhân viên trong APPLY; lấy giao dịch 1 lần vào #Transaction; lần đầu chậm / lần 2 nhanh trên server dùng chung là do I/O, không phải plan
project: std5
branch: all
type: performance
keywords: [F_STA_SelectAllTransactionHaveMaxSequenceOnDate, OUTER APPLY, CROSS APPLY, S_PAY_GetEmpHaveOtherTransChangeByPeriod, S_PAY_GetEmpNewHireByPeriod, S_PAY_GetEmpResignedByPeriod, PayrollMasterFileChangeReport, F_STA_SelectLastTransactions, RowID, report chậm, mở report chậm, temp procedure collation conflict, Cannot resolve the collation conflict, IO_COMPLETION, mở lần đầu chậm, lần 2 nhanh, WITH RECOMPILE, multi-statement TVF, shared server I/O, EXCEPT]
files: [Cadena HRM 5.0/Cadena.SQLScripts/3.SPFunctionsViews/S_PAY_GetEmpHaveOtherTransChangeByPeriod.sql, Cadena HRM 5.0/Cadena.SQLScripts/3.SPFunctionsViews/S_PAY_GetEmpNewHireByPeriod.sql, Cadena HRM 5.0/Cadena.SQLScripts/3.SPFunctionsViews/S_PAY_GetEmpResignedByPeriod.sql]
commit:
date: 2026-10-28
author: Thuan Pham Ngoc
status: active
confidence: verified
---

## Triệu chứng (Symptom)
Payroll \ Payroll Reports \ Payroll Master File Change mở chậm (19-71 s SQL cho 5 SP). Phần III
(S_PAY_GetEmpHaveOtherTransChangeByPeriod) chiếm 13-39 s. Sau deploy: lần mở đầu 23 s, lần 2 6 s.

## Nguyên nhân gốc (Root cause)
- SP lặp qua Staffing_Employees và trong OUTER/CROSS APPLY gọi inline TVF `F_STA_SelectAllTransactionHaveMaxSequenceOnDate(SE.ID, CompanyID, TenantID)`
  (phần III gọi 2 lần: cur, pre). Mỗi lần gọi xếp hạng (ROW_NUMBER) toàn bộ giao dịch của nhân viên đó: ~2.5 s/lượt cho 1 525 người.
  TVF hỗ trợ `@valEmployeeID = NULL` (mọi nhân viên của company) và RowID = ROW_NUMBER PARTITION BY EmployeeID, nên gọi 1 lần cho cùng RowID.
- Phần còn lại: `F_STA_SelectLastTransactions` (multi-statement TVF, table variable ~45 cột trong tempdb, ~0.6 s/lần) được tính lại
  ở mỗi SP để tạo #Employee, và SP V (Allowance) gọi thêm một lần trong CROSS APPLY với tham số tương đương
  (hàm tự ISNULL các filter về 0 / ''; khác thật duy nhất là @valIsUseDate, handler luôn true).
- "Lần đầu chậm, lần 2 nhanh" trên DB dev dùng chung KHÔNG phải do plan: 5 SP cùng tham số, plan đã cache dao động 4.5 → 23.5 s.
  Wait lúc chậm là IO_COMPLETION 2-5 s mỗi SP (lúc nhanh ~0.1 s) trong khi một job ở DB khác gây PAGEIOLATCH/WRITELOG:
  đĩa server dùng chung bão hòa. Statement nhạy I/O nhất là `SELECT ... INTO #Employee FROM F_STA_SelectLastTransactions(...)`.
- Thứ tự dòng: ORDER BY chỉ theo LocalEmployeeID nên thứ tự các dòng phụ cấp của cùng nhân viên do plan quyết định
  (SP cũ chạy 2 lần cũng lệch). Handler OrderBy(AllowanceTypeName) là stable nên thứ tự SQL hiện lên report.

## Cách sửa (Fix)
- Trong 3 SP: sau khi tạo #Employee, lấy giao dịch 1 lần
  `SELECT <cột cần> INTO #Transaction FROM F_STA_SelectAllTransactionHaveMaxSequenceOnDate(NULL, @CompanyID, @TenantID) T WHERE EXISTS (#Employee)`
  + clustered index (EmployeeID[, RowID]); trong APPLY thay TVF bằng #Transaction và thêm `EmployeeID = SE.ID`
  (phần III: `pre.EmployeeID = cur.EmployeeID`). Giữ nguyên join, filter, cột, ORDER BY, join #Employee.
- SP V: bỏ lần gọi F_STA_SelectLastTransactions thứ hai (giữ nhánh gọi lại khi @valIsUseDate = 0), thêm
  `ORDER BY SE.LocalEmployeeID, PA.ID, EA.ID` để thứ tự ổn định.
- Hướng tiếp theo nếu cần: gọi F_STA_SelectLastTransactions ít lần hơn (5 → 2 bằng SP tổng trả nhiều result set).

## Kiểm chứng (Verification)
- So sánh SP cũ trên DB với thân SP mới (chạy qua sp_executesql trong transaction rollback): số dòng + EXCEPT 2 chiều trên mọi cột
  kèm số thứ tự dòng (rn IDENTITY khi INSERT EXEC) → 0 khác biệt cho 5 kỳ admin + 1 kỳ non-admin (40 org); SP V 0 lệch thứ tự ở 7 trường hợp.
- Thời gian (cache nóng): III 13 s → ~1 s; I 1.1-2.0 → 0.7-0.9 s; II 1.8-3.5 → 0.5-0.7 s; V 1.8 → 1.1 s; tổng ~19 s → ~5.5 s.
- Mô phỏng dữ liệu ×5/×10: build #Transaction tăng gần tuyến tính, cách cũ tăng nhanh hơn. Chưa đo với 50k giao dịch thật.
- Phía C# (~1 900 dòng): EPPlus fill 0.4-0.5 s, GetAsByteArray ~0.6 s; DevExpress LoadDocument lần đầu trong process 1.5-1.9 s (JIT),
  sau đó 0.2 s; ExportToPdf 2.4-3.1 s là chi phí chính của download. Chưa chạy trên UI.

## Hướng đi sai (Dead ends)
- So sánh 1 lượt "plan cache" (23 s) với 1 lượt `WITH RECOMPILE` (5.6 s) rồi kết luận parameter sniffing: SAI.
  Chạy xen kẽ 3 vòng thì cả hai đều lúc 5 s lúc 24 s.
- Tạo SP mới dạng temporary procedure (#proc) để so sánh: lỗi "Cannot resolve the collation conflict between Latin1_General_100_CI_AS
  and SQL_Latin1_General_CP1_CI_AS" (temp proc compile theo collation của tempdb). Dùng sp_executesql với thân SP + danh sách tham số.
- Chỉ lọc trước theo #Employee: bớt ~40 % nhân viên; lợi ích chính là bỏ gọi TVF theo từng dòng.
- Định dạng Excel theo cột thay vì từng dòng: không nhanh hơn.
- So sánh có thứ tự báo lệch 9-535 dòng trong khi EXCEPT không thứ tự = 0: do ORDER BY không đủ cột, không phải sai dữ liệu.
- Mô phỏng bằng bảng tạm không tái hiện chi phí tuyệt đối (0.46 s so với 13 s thật: bảng thật rộng ~45 cột, PK GUID).

## Lần sau (Next time)
Report chậm thất thường trên DB dev dùng chung: đo nhiều lượt xen kẽ + `sys.dm_exec_session_wait_stats` + `sys.dm_exec_requests`
của server trước khi kết luận về plan hay sửa code.
grep `F_STA_SelectAllTransactionHaveMaxSequenceOnDate(SE.ID` / `(ee.EmployeeID` trong SQLScripts — cùng pattern ở nhiều report khác.
Kiểm chứng SP viết lại bằng harness INSERT EXEC vào #o/#n có rn IDENTITY + EXCEPT 2 chiều; kiểm tra repo SP == DB SP trước khi sửa.
