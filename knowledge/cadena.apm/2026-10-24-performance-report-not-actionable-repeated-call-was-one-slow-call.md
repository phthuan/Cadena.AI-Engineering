---
title: Báo cáo performance không giúp developer hành động được — "Repeated calculation" của CacheBase.GetOrSet thực ra là một lời gọi chậm duy nhất mỗi request (SiteMapManager.GetAllSiteMaps)
project: cadena.apm
type: feature
keywords: [Repeated calculation, METHOD-REPEATED, Slow single call (not repetition), CacheBase.GetOrSet, GetAllSiteMaps, Instrument the callees, Cadena.APM.Trace.Probe.Enter, Cause & fix, What is slow, IssueCaller, CallersOf, FunctionOf, cadena.http.fid, cadena.http.view, not in source]
files: [src/Cadena.APM.Analyzer/ActionableIssues.cs, src/Cadena.APM.Analyzer/CodeAdvisor.cs, src/Cadena.APM.Analyzer/HrmModules.cs, src/Cadena.APM.Collector/Storage/SqlServer/SqlServerTelemetryStore.Performance.cs, src/Cadena.APM.Collector/wwwroot/dashboard/perf.js, tests/Cadena.APM.Analyzer.Tests/ActionableIssueTests.cs, tests/Cadena.APM.Collector.Tests/Dashboard/perf.views.test.js]
commit:
date: 2026-10-24
author: Thuan Pham Ngoc
status: active
---

## Triệu chứng (Symptom)
Từ mục "Cause & fix" của báo cáo, developer không biết được cái gì chậm, chậm bao nhiêu, cần sửa file / SP nào và sửa gì.
Issue C# đứng đầu: RUNTIME "Repeated calculation" của `Cadena.Caching.CacheBase.GetOrSet`, 53 lời gọi/request, "Not determined", bước tiếp theo
"Instrument the callees (Cadena.APM.Trace.Probe.Enter, …)". Phần chi tiết hiển thị "(not in source)" và ẩn các evidence fact.

## Nguyên nhân gốc (Root cause)
- Dữ liệu store đã có nhưng không bao giờ được đưa vào issue: HRM function của request (root span `cadena.http.fid` /
  `cadena.http.view`), thời lượng request, và các caller trực tiếp của method (parent span + method aggregate).
- METHOD-REPEATED chỉ nhìn vào số lần gọi: 52 trên 53 lời gọi là 0 ms; MỘT lời gọi (từ SiteMapManager.GetAllSiteMaps) mất 30–57 ms trong
  20 trên 20 request. Bên trong nó: CacheBase.Get (miss) → SQL `select sitemapbas0_…` 51 ms → CacheBase.Set.
- Bản thân HRM: Cadena.BusinessLayer/SiteMap/Services/SiteMapManager.cs:25 gọi `_cache.RemoveAll("System$SiteMapElements")`
  ngay trước GetOrSet. Bảng SiteMap bị tải lại ở mọi request BasicForm (≈20 % trong 143 ms của Salary Calculation).
- CodeAdvisor liệt kê các lời gọi probe APM được inject (Cadena.APM.*) như là callee.

## Cách sửa (Fix)
- Analyzer: IssueOccurrence/ActionableIssue có thêm Function, RequestMs (median) và Callers (số lời gọi, ms, lời gọi dài nhất, cái gì chiếm
  thời gian bên trong lời gọi dài nhất, file:line của caller). ExplainCallers điền "called from". Nếu một caller chiếm ≥ 60 % thời gian với
  ≤ 1 lời gọi mỗi request, issue trở thành "Slow single call (not repetition)": nó cho biết lời gọi chậm ở mọi request hay
  chỉ thỉnh thoảng, và Where-to-fix trỏ tới source của caller. Validation và missing evidence suy ra từ đó.
- CodeAdvisor: loại bỏ các callee Cadena.APM.*.
- HrmModules: pages fid → nhãn menu; FunctionOf cho ra "Payroll › Salary Calculation".
- Phần chi tiết của dashboard gồm năm phần: What is slow / How slow (ms mỗi request, % của request) / Where to fix / What to change
  (cách sửa hoặc bước tiếp theo, lý do, evidence fact) / How to verify.

## Kiểm chứng (Verification)
- Analyzer 218/218 (net10.0 + net48), Collector 104 passed + 75 skipped, dashboard JS 42/42, Contract 7/7.
- Live: một collector Debug tạm thời (port 4399, tắt Analysis, cùng telemetry DB và code map) đã sinh ra các đoạn text mới cho
  dữ liệu thật; đã kiểm tra bằng screenshot.

## Hướng đi sai (Dead ends)
- Rule single-call đầu tiên so sánh tổng thời gian của caller qua 20 trace với giá trị max của MỘT lời gọi: không bao giờ khớp. Hãy so sánh theo từng request.
- "Thường là cache miss sau khi restart" là sai với dữ liệu này: lời gọi chậm ở mọi request. Hãy kiểm tra số lời gọi so với số request trước.

## Lần sau (Next time)
Với issue METHOD-REPEATED, xem cách thời gian được chia giữa các caller trước khi xem số lần gọi. Chạy một collector tạm thời với
Collector__Analysis__Enabled=false trỏ vào DB của session để kiểm tra thay đổi của báo cáo mà không phải dừng session đang chạy
(Collector__KeyPepper và ApiKeys Hash phải là base64).
