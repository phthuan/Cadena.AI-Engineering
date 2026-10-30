---
title: Tìm hàm C# sinh ra một câu SQL NHibernate nặng (không có stack) — đọc alias transactio0_/employee1_… theo thứ tự Fetch; câu Staffing_Transactions 31 join = GetAllTransactionsQueryHandler (DataChecker.TransactionByEmployeeIDs, nghiệp vụ nghỉ phép)
project: std5
type: performance
keywords: [transactio0_, globalempl2_, alapplydat9_, sgptimeshe16_, ID63_0_, GetAllTransactionsQueryHandler, GetAllTransactionsQuery, DataChecker, TransactionByEmployeeIDs, CalculateEmployeeLeaveBalanceHandler, ThenFetchMany, cartesian product, Staffing_Transactions, query_hash 0xE6C695D01E2A8383, Slow moments, Performance Monitoring]
files: [Cadena HRM 5.0/Cadena.BusinessLayer/LiteData/Handlers/GetAllTransactionsQueryHandler.cs, Cadena HRM 5.0/Cadena.BusinessLayer/Utils/DataChecker.cs, Cadena HRM 5.0/Cadena.BusinessLayer/TimeAttendance/Handlers/CalculateEmployeeLeaveBalanceHandler.cs]
commit: (chưa sửa)
date: 2026-10-27
author: Claude Code (session of phthuan136)
status: active
---

## Triệu chứng (Symptom)
Performance Monitoring (MOL-02, DB MOL_CAD_20260825) > Slow moments: câu `select transactio0_.ID as ID63_0_, employee1_.ID as ID10_1_, globalempl2_.ID ...`
~72 000 page đọc/lần, 4 620 dòng trả về cho 3 lần chạy, cột Code trống.

## Nguyên nhân gốc (Root cause)
- Cột Code trống vì câu không chạy trong process HRM web được monitor: monitor bật từ 11:35, ghi MỌI câu SQL của process, không câu nào đụng Staffing_Transactions;
  SQL Server ghi lần chạy 11:49. sys.dm_exec_sessions trên DB lúc đó: ngoài CDV164 (máy monitor) còn một app .Net SqlClient trên CDV150 (HRM/WebAPI của người khác).
  Plan cache đã xóa câu (query_hash ra 0 dòng) nên không lấy được host/nguyên văn.
- Câu do `GetAllTransactionsQueryHandler.Handle` (nhánh không có TransactionCalculations) sinh ra: 31 alias khớp đúng thứ tự 31 Fetch/ThenFetch
  (employee1_=Employee, globalempl2_=GlobalEmployeeInfo, company3_, currency4_/5_=Company.Currency/LocalCurrency, tenant6_, currency7_, timesheeta8_=TimeSheetALPolicy,
  alapplydat9_, alcalculat10-12_, timesheeta13/14_, timesheets15_, sgptimeshe16_→timesheetc17_, … timesheeth23_, timesheetp24_→timesheeto25_/g26_/m27_, paycyclety28_,
  transactio29_/30_=TransactionAction/Catalog, employeere31_=EmployeeResignation).
- Gọi duy nhất từ property `DataChecker.TransactionByEmployeeIDs` (lần đọc đầu), dùng bởi CalculateEmployeeLeaveBalanceHandler, CalculationEmployeeSGPBalanceQueryHandler,
  CheckIsOverLeaveBalance, CheckIsAssignLeaveAfterApplyDate/AfterResignation, CalculationTotalEntitlementQueryHandler = tính số dư / kiểm tra khi đăng ký, duyệt, import nghỉ phép (cả ESS).
- Nặng vì 10 ThenFetchMany (collection) trong một query → tích Descartes, rồi `.Distinct()` trong RAM; EmployeeIDs rỗng = lấy mọi transaction của company.

## Cách sửa (Fix)
Chưa sửa. Hướng: bỏ ThenFetchMany khỏi query chính (tải các policy collection bằng query riêng / FetchMany theo batch hoặc cache theo policy ID vì nhiều transaction dùng chung policy),
chỉ fetch những gì caller dùng, đảm bảo luôn có EmployeeIDs.

## Kiểm chứng (Verification)
Đối chiếu alias 1..31 với code (đọc tay). sys.dm_exec_sessions (read-only) lúc 13:37. Chưa chạy lại chức năng để bắt stack.

## Hướng đi sai (Dead ends)
- Đoán theo bảng/cột (Staffing_Transactions + nhiều bảng timesheet) → TransactionAndPeriod.cs:183: SAI. Thứ tự alias (Company→Currency×2, AL policy collections) không khớp.
- Tìm nguyên văn WHERE trong snapshot/top-sql-server.json/.sqlplan: monitor chỉ giữ 4 000 ký tự đầu, câu NHibernate dài phần SELECT nên không có FROM/WHERE.
- PowerShell SqlConnectionStringBuilder.ApplicationName/ConnectTimeout: "Keyword not supported" (PS gọi indexer) — dùng `$b['Application Name']` nếu cần.

## Lần sau (Next time)
Với SQL NHibernate không có stack: liệt kê alias theo số (tên = 10 ký tự đầu tên entity viết thường + số thứ tự join), rồi grep chuỗi Fetch có đúng thứ tự đó
(thường grep 2-3 entity hiếm như ALApplyDateMode, SGPTimeSheet*). Sau đó grep `new <Query>` → property/handler → nghiệp vụ.

## Cập nhật 2026-10-27 (chiều): code map trong Performance Monitoring
Đã thêm "code map" (Diagnostics/CodeMap.cs, chưa commit, MAI-02 + MOL-02): lần đầu process HRM web chạy mỗi câu SQL (nhanh hay chậm),
lấy stack một lần (CodeCapture.FirstRun, fingerprint = độ dài + 32 ký tự đầu + 96 ký tự cuối, tối đa 20 stack/giây, bỏ qua khi quá tải),
lưu App_Data/Diagnostics/code-map.json (≤ 5 000 câu). To fix / Slow moments: cột Code "First run seen by HRM (...)", khớp câu SQL Server bằng
Analyzer.MatchKey(sql, 1900) — KHÔNG dùng 150 ký tự: select list NHibernate dài làm nhiều query trùng 150 ký tự đầu. Câu khác nhau chỉ sau ~2 000 ký tự
(Normalizer cắt key 2 000, SQL Server giữ 4 000) dùng chung khóa → giữ tối đa 3 nơi gọi, nối bằng "— or —". Không khớp: "not run by this HRM web process".
Đo (harness scratch codemaptest): 0,43 µs/câu đã thấy (0,70 µs với 8 thread); burst 1 000 câu mới → 20 stack; trang tra 5 000 entry: 29 ms.
E2E MOL-02: sau restart, code-map.json có 7 câu khởi động, đều có frame Cadena. Tắt riêng: Settings > Advanced > CodeMapEnabled.
Bẫy khi viết: FindByName quét IndexOf 5 000 key dưới StatsSync → đổi sang chỉ mục tên store/function (regex exec/dbo.) dựng lười.
Review + sửa (2026-10-27 tối): ước tính "3-4 MB" là SAI — đo 5 000 entry: 13-39 MB RAM, file 6,7-20 MB, Serialize 108-201 ms dưới StatsSync,
Load 179-493 ms trong Application_Start. Đã sửa: MatchKey (gần bản sao của Key) → MatchHash FNV-1a 64-bit [ScriptIgnore], không lưu;
đọc file trên thread nền (CodeMap.ReadFile ngoài lock + AddLoaded dưới lock, cờ Loaded chặn SaveTop ghi đè file trước khi đọc xong);
Snapshot() dưới lock + ToJson ngoài lock; "nơi gọi" so theo 3 frame trong cùng. Đo lại: 7-20 MB RAM, file 3,7-10,6 MB, giữ lock khi lưu 0,3-0,6 ms,
khi đọc 4-11 ms (phần nền 255-665 ms). File định dạng cũ (có MatchKey) đọc được, lưu lại bỏ trường đó. Bài học: luôn đo dung lượng thật với dữ liệu đầy trước khi hứa con số.
