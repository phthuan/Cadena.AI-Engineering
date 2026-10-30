---
title: Báo cáo performance (#/report, /performance-report) mất ~28 s — code map bị merge lại cho từng trace, execution group bị tính lại cho từng finding
project: cadena.apm
type: performance
keywords: [performance-report, performance-issues, ActionableIssues, AnalyzeProblems, CodeMapCatalog.CodeMapFor, CodeMap.Merge, ConditionalWeakTable, EntityCache, CodeAdvisor.Recommend, ExecutionAnalyzer.Groups, ExecutionGroups, slow report]
files: [src/Cadena.APM.Collector/Api/CodeMapCatalog.cs, src/Cadena.APM.Collector/Storage/SqlServer/SqlServerTelemetryStore.Performance.cs, src/Cadena.APM.Analyzer/CodeAdvisor.cs]
commit: (chưa commit)
date: 2026-10-22
author: Claude Code (session of phthuan136)
status: active
---

## Triệu chứng (Symptom)
Dashboard #/report (GET /api/v1/performance-report?top=20) mất ~28 s trên session `smoke`. Session có code map HRM thật
(~145k method, hai map) và 20 trace đã phân tích, vài trace chạm ngưỡng 5,000 span với tới 189 finding mỗi trace.

## Nguyên nhân gốc (Root cause)
Đo bằng log từng giai đoạn với Stopwatch ("actionable issues: …" / "performance report: …" trong log của collector):
- 25.5 s trong 28.5 s là phần code advice. Tải trace mất 2.4 s, SQL Server events 0.26 s, contention 0.02 s.
- `CodeMapCatalog.CodeMapFor` trả về `CodeMap.Merge(maps)`, một CodeMap MỚI, ở mỗi lần gọi, tức là một lần cho mỗi trace. Mỗi
  instance mới dựng lại các dictionary `Find` / `Type` (GroupBy trên 145k method). Nó cũng bỏ lỡ mọi cache có key là instance của map:
  `CodeAdvisor.EntityCache` (ConditionalWeakTable) phải phân loại lại mọi method NHibernate. Việc đó tốn ~8 s cho mỗi
  trace có finding đầu tiên dùng tới nó.
- `CodeAdvisor.Recommend` gọi `ExecutionAnalyzer.Groups(spans, aggregates, map, blocking)` cho MỌI finding, nhưng
  kết quả chỉ phụ thuộc vào trace. Trên một trace 5,000 span, đó là ~0.2–0.3 s mỗi finding × 189 finding.

## Cách sửa (Fix)
- CodeMapCatalog giữ map đã merge theo từng tập instance map đã parse (so sánh bằng ReferenceEquals, tối đa 8 entry).
  Một file thay đổi sẽ được parse thành instance mới, nên sẽ có bản merge mới.
- Thêm `CodeAdviceInput.ExecutionGroups` (null = tính như trước). AnalyzeProblems tính các group một lần cho mỗi trace và
  truyền cho từng finding. Nếu tính toán thất bại, nó fallback về null, nên lỗi của một finding vẫn chỉ là lỗi của finding đó.
- Dùng chung các group là an toàn: Containing và Recommend chỉ đọc chúng. Clean() của collector redact chúng tại chỗ, nhưng
  Redactor.Clean là idempotent.
- Kết quả: 28.5 s → 3.7–5.1 s (warm). Request đầu tiên sau khi collector khởi động vẫn dựng index của map và cache một lần.

## Kiểm chứng (Verification)
- Analyzer tests: 210/210 trên net10.0 và net48. Mới: ExecutionAnalyzerTests.Precomputed_execution_groups_give_the_same_advice_as_groups_computed_per_finding.
- Collector tests: 171 passed, 7 skipped (thiếu golden data) với APM_TEST_SQLSERVER đặt về instance local. Mới:
  CodeMapCatalogVersionTests.The_same_files_give_the_same_merged_map_and_a_changed_file_a_new_one.
- Live: log collector trên session smoke hiển thị thời gian từng giai đoạn.

## Hướng đi sai (Dead ends)
- Một diagnostic đo thời gian theo rule đổ lỗi cho METHOD-DOMINANT trên một trace 35 span (~8.6 s mỗi finding). Thời gian đó thực ra là của
  CodeMapFor / PlansFor / ToAggregates, bị tính vào finding đầu tiên của trace.
- Restart collector khiến các tab dashboard đang mở kết nối lại và request lại. Khi đó nhiều báo cáo chạy
  cùng lúc và làm phồng mọi số đo thời gian. Hãy đọc các dòng log của từng request riêng lẻ, hoặc đóng các tab khác trước.
- Gọi API từ ngoài trình duyệt: POST /dashboard/session yêu cầu lời gọi dashboard cùng Origin (nếu không sẽ 403), và
  không được giải mã session.secrets. Hãy đo qua log của chính collector.

## Lần sau (Next time)
Với một endpoint phân tích chậm, đọc dòng log giai đoạn "actionable issues:" của collector trước. Sau đó tìm các object tạo mới theo từng lời gọi
làm vô hiệu cache có key là instance (Merge / map mới) và các công việc làm cho từng finding mà chỉ phụ thuộc vào trace. Chi phí còn lại là
tải trace (~2–2.7 s cho 20 trace); cache kết quả theo từng trace với key là findings + instance của map là bước tiếp theo nếu cần.
