---
title: Roslyn analyzer chậm và cấp phát hàng chục GB trên solution lớn do dựng tên kiểu bằng ToDisplayString mỗi lần so sánh; N+1 NHibernate báo nhầm khi chỉ đọc ?.ID, so sánh null hoặc copy tham chiếu; tool window WPF đứng khi nạp hàng chục nghìn dòng có grouping
project: common
type: performance
keywords: [GetFullMetadataName, ToDisplayString, IsOrImplements, AllInterfaces, ConditionalWeakTable, GetAnalyzerTelemetryInfoAsync, AD0001, VSP006, lazy proxy, "?.ID", N+1, IsVirtualizingWhenGrouping, "Cannot change the VirtualizationMode attached property on an ItemsControl after Measure is called", ObservableCollection, ListCollectionView]
files: [src/PerformanceTracker.Analyzers/AnalysisHelpers.cs, src/PerformanceTracker.Analyzers/NHibernateNPlusOneAnalyzer.cs, src/PerformanceTracker.Vsix/PerformanceTrackerControl.cs]
commit:
date: 2026-10-29
author: Claude (Visual Studio Performance Tracker)
status: active
---

## Triệu chứng (Symptom)
- Chạy 11 analyzer của Performance Tracker trên Cadena HRM 5.0 (59 project, 18.158 file): 103 giây mỗi lần quét toàn solution, cấp phát ~51 GB, `GetAnalyzerTelemetryInfoAsync` cho thấy VSP008 385 s và VSP005 177 s thời gian thực thi cộng dồn.
- VSP006 báo 3.013 Warning "lazy association ... N+1", trong đó nhiều dòng chỉ là `x.Company?.ID`, `x.ActorGroup == null`, `FixWorkflowActor = item.FixWorkflowActor`.
- Tool window WPF: nạp 12.639 dòng bằng `ObservableCollection.Add` từng phần tử khi đang grouping làm UI thread đứng 2–6 giây.

## Nguyên nhân gốc (Root cause)
- `GetFullMetadataName` dựng chuỗi bằng `ns.ToDisplayString()` + `StringBuilder.Insert` mỗi lần gọi; `IsOrInheritsFrom/IsOrImplements` gọi nó cho từng base type và từng interface của mọi kiểu, ở mọi invocation, trong mọi analyzer.
- Proxy lazy many-to-one của NHibernate không nạp khi đọc identifier, so sánh tham chiếu với null hay gán tham chiếu sang object khác; analyzer chỉ bỏ qua `.Id` trực tiếp, không xử lý `?.ID` (IConditionalAccessOperation), so sánh null, gán, truyền tham số.
- WPF tắt UI virtualization khi có `GroupDescriptions` trừ khi đặt `VirtualizingPanel.IsVirtualizingWhenGrouping=true`; mỗi `Add` còn làm view lọc/nhóm lại.

## Cách sửa (Fix)
- Cache tên metadata theo `OriginalDefinition` bằng `ConditionalWeakTable<ITypeSymbol,string>`; thêm `HasFullMetadataName` so sánh nhanh `MetadataName` với đuôi chuỗi cần tìm (kèm ký tự phân cách `.`/`+`) trước khi lấy tên đầy đủ.
- VSP006: chỉ báo khi association thực sự được dùng: truy cập member khác identifier (kể cả qua `?.`), gọi method, extension method (LINQ), hoặc với collection thì truyền tham số/`foreach`.
- Tool window: dựng `ListCollectionView` mới một lần rồi gán `ItemsSource`; đặt `IsVirtualizingWhenGrouping` và `VirtualizationMode.Recycling` trong constructor (đặt sau lần Measure đầu sẽ ném `InvalidOperationException`).

## Kiểm chứng (Verification)
- Harness MSBuildWorkspace chạy đúng `SolutionPerformanceAnalyzer.AnalyzeAsync` của VSIX trên HRM, 3 lần: 103 s → 56 s, cấp phát 51 GB → 12,4 GB; VSP001–VSP005 giữ nguyên số finding (cache không đổi kết quả). Không rò bộ nhớ giữa các lần (retained delta −5…+6 MB sau lần đầu). Cancel dừng sau 1–2 ms.
- VSP006: 3.013 → 2.175 Warning; trong 1.149 vị trí bị bỏ, 1.005 nằm trên dòng `?.ID`/`== null`/gán tham chiếu; 311 vị trí mới là truy cập thật (`.Level`, `.DisplayName`, `.TranslationID`).
- Benchmark WPF 12.639 dòng: không grouping 969 → 36 ms, group theo project 2.126 → 61 ms, group theo method 5.835 → 685 ms.
- 73/73 test pass, trong đó có test hồi quy cho từng trường hợp.

## Hướng đi sai (Dead ends)
- Định hạ severity của VSP008 tham số `IN` (1.471 Warning trên HRM) vì nhiều danh sách là cấu hình nhỏ: không làm, vì analyzer không chứng minh được kích thước; giữ Warning + Needs verification và để người dùng chỉnh bằng `.editorconfig`.
- Nghi `ToList()` trong VSP009 bị báo nhầm trên chuỗi NHibernate: thực ra rule chỉ báo `ToList()` thứ hai (sau khi query đã kết thúc), đúng.

## Lần sau (Next time)
Đo analyzer trên solution thật bằng `CompilationWithAnalyzersOptions(logAnalyzerExecutionTime: true)` + `GetAnalyzerTelemetryInfoAsync` và `GC.GetTotalAllocatedBytes` trước khi tối ưu; tìm trước các helper dựng chuỗi tên kiểu. Với rule ORM lazy-load, mô phỏng hành vi proxy: identifier/null/copy không nạp. Với WPF list lớn, rebuild view một lần và bật virtualization khi grouping ngay từ constructor.
