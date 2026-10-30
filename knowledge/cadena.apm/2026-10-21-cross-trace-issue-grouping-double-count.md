---
title: Gom APM finding thành issue bị tính trùng thời gian khi nhiều rule cùng kích hoạt trên một statement; plan có missing-index làm finding trông như đã được xác nhận
project: cadena.apm
type: feature
keywords: [ActionableIssueBuilder, performance-issues, SQL-SLOW, SQL-HIGH-CPU, SQL-HIGH-READS, MISSING_INDEX_SUGGESTION, SUPPORTED, CodeConfidence.High, PerformanceProblemBuilder]
files: [src/Cadena.APM.Analyzer/ActionableIssues.cs, src/Cadena.APM.Collector/Storage/SqlServer/SqlServerTelemetryStore.Performance.cs, src/Cadena.APM.Collector/Api/ApiEndpoints.cs]
commit: (chưa commit)
date: 2026-10-21
author: Claude Code (session of phthuan136)
status: active
---

## Triệu chứng (Symptom)
Khi dựng một danh sách performance issue xuyên trace (GET /api/v1/performance-issues) từ các PerformanceProblem theo từng trace:
một statement chậm duy nhất hiển thị "3 executions per trace" và mức ảnh hưởng gấp ba, nên bị gắn nhãn REPEATED thay vì SINGLE_EXPENSIVE.
Một statement chậm có actual plan mang gợi ý missing-index của optimizer lại ra kết quả code-level validation là SUPPORTED.

## Nguyên nhân gốc (Root cause)
- SQL-SLOW, SQL-HIGH-CPU và SQL-HIGH-READS cùng kích hoạt trên cùng một fingerprint trong một trace. Mỗi rule mang executions = 1 và
  cùng client time. Vì vậy cộng các occurrence trong một group sẽ nhân cả hai giá trị lên.
- CodeAdvisor.SqlCost đặt CodeConfidence.High khi plan khớp và đã biết caller, kể cả khi biện pháp khắc phục duy nhất được gợi ý là
  missing-index suggestion của optimizer. Sau đó Validate() chuyển HIGH thành SUPPORTED. Các index hiện có và write workload
  không bao giờ nằm trong bằng chứng.

## Cách sửa (Fix)
- ActionableIssueBuilder.Measure: với mỗi trace lấy MAX của từng metric trên các rule của group, sau đó SUM qua các trace.
- ActionableIssueBuilder.Explain: một MISSING_INDEX_SUGGESTION trong plan findings giới hạn trần confidence. Với runtime counter thực tế
  thì là PROBABLE; với estimated plan thì là INCONCLUSIVE; không bao giờ là CONFIRMED, bất kể code-level confidence nói gì.

## Kiểm chứng (Verification)
- tests/Cadena.APM.Analyzer.Tests/ActionableIssueTests.cs: Issue_3 (single so với repeated), Issue_4 (actual → PROBABLE, estimated →
  INCONCLUSIVE) và Issue_7 (executions = 1 cho 3 rule trên một statement).
- Analyzer 196/196 trên net10.0 và net48; Collector 167 passed, 7 skipped (thiếu golden data) với APM_TEST_SQLSERVER = instance local.

## Hướng đi sai (Dead ends)
- Ban đầu PROBABLE cho trường hợp index cũng yêu cầu CodeConfidence.High. Khi không có code map thì caller không nằm trong code map, nên
  confidence là Medium, và ngay cả một scan rất rõ trong actual plan (đọc 250,000 dòng để trả về 40) vẫn ra INCONCLUSIVE. Độ mạnh của plan
  và code mapping là độc lập với nhau, nên rule giờ chỉ dựa vào plan.
- Liên kết trang issues dưới dạng #/perf/issues làm hỏng rule của fake-DOM "mọi link #/perf/… là trace id 32 ký tự hex". Giờ trang có
  route riêng là #/issues.

## Lần sau (Next time)
Khi tổng hợp các object PerformanceProblem, nhớ rằng một statement hoặc method có thể mang nhiều rule trong mỗi trace: deduplicate
theo trace trước khi cộng. Coi mọi gợi ý index lấy từ plan là ứng viên (candidate), độc lập với confidence của CodeAdvisor.

## Bổ sung 2026-10-21: source scan trên code map
- **Tra cứu batch API trên interface.** `CodeAdvisor.FindBatchApi` trả về UNKNOWN khi nhận method INTERFACE của một
  lời gọi repository: `BatchKeyType` cần các parameter, mà chỉ implementation trong code map mới có. Truyền implementation
  đã resolve (type + method key), không truyền interface khai báo của lời gọi.
- **Nhiễu trên HRM map thật** (146k method) đến từ hai nguồn:
  - code thư viện được biên dịch vào build (Dapper, Quartz) — bỏ qua theo namespace;
  - ghi repository trong vòng lặp (`CdnSession.Save` / `Delete`) — đây là câu hỏi về batching, không phải N+1.
  Sau cả hai bộ lọc: 1,206 → 1,054 risk.
- **Lambda đã được bao phủ.** `CodeCall.InLoop` cũng là true với lời gọi bên trong lambda truyền cho các API duyệt
  (Select / ForEach / Parallel.ForEach), nên không cần xử lý lambda thêm.
- Các code map cũ chỉ chứa object `CREATE PROCEDURE` (regex `Proc` của CodeMapCommand). Function và view lấy từ việc đọc
  các file *.sql dưới `build.sourceRoot`.
- **Bẫy xếp hạng.** Đếm mọi lời gọi repository-by-name trong vòng lặp đã đẩy một helper chưa được xác minh của cùng class
  (`ShiftDayOffImporter.CheckEffectiveDate`) lên #1. Chỉ chấm điểm data access đã xác minh, và loại các helper cùng class không
  được chứng minh là có query.
- **Bẫy công cụ.** Heredoc của Git Bash trên máy này biến `'\'` trong C# thành `'\'`. Dùng `Path.DirectorySeparatorChar` hoặc
  các tool Write / Edit.
- **Bẫy khi test lock (contention recorder).** `UPDATE t SET col = col` trong một transaction đang mở KHÔNG chặn reader:
  SQL Server coi đó là update không thay đổi dữ liệu và không giữ lock xung đột nào đối với reader. Để tạo một lần chờ test thật, hãy đổi
  giá trị (ví dụ `DATEADD(ms, 10, col)` trên một cột không phải key, không phải FK, không có index) và ROLL BACK.
- **Phạm vi của ingest key.** Key được giới hạn theo service name. Một producer mới bên trong thành phần SQL Monitor phải báo cáo với tên
  `Cadena.APM.SqlMonitor`, nếu không collector trả về 403 "resource outside the API key scope".
- **Session secrets** (`session.secrets`) được bảo vệ bằng DPAPI với entropy của DevRunner. Không giải mã chúng từ bên ngoài;
  hãy khởi động process của session qua DevRunner (nó truyền secret qua environment của process con).
