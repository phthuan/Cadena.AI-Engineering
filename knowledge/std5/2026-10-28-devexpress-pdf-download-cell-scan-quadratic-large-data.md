---
title: Report Download PDF lỗi "Oops! Something went wrong" khi data nhiều - DevExpress quét từng ô sheet.Cells[r,c] theo LastUsedIndex (Payroll Master File Change)
project: std5
type: bug
keywords: [Oops! Something went wrong, Download PDF, DownloadPdf, PayrollMasterFileChangeReport, Payroll Master File Change, ExportToPdf, Rows.LastUsedIndex, Columns.LastUsedIndex, GetDataRange, Rows.Remove, Columns.Remove, timeout, data nhiều, DevExpress Spreadsheet]
files: [Cadena HRM 5.0/Modules/Cadena.Modules.Payroll/Views/Reports/PayrollMasterFileChangeReport.ascx.cs, Cadena HRM 5.0/Cadena.WebApp/TemplateReports/Payroll/PayrollMasterFileChange.xlsx]
commit:
date: 2026-10-28
author: Thuan Pham Ngoc
status: active
---

## Triệu chứng (Symptom)
Payroll \ Payroll Reports \ Payroll Master File Change: mở report (ASPxSpreadsheet) bình thường, nhưng bấm ribbon "Download PDF"
(postback `__EVENTTARGET=DownloadPDF`) thì ra trang "Oops! Something went wrong" khi kỳ lương có nhiều dòng dữ liệu. Ít data thì download được.
Không có entry trong Cadena.WebApp/Logs (request bị timeout / quá tải chứ không có exception nghiệp vụ).

## Nguyên nhân gốc (Root cause)
`DownloadPdf()` tìm vùng dữ liệu bằng 2 vòng lặp lồng nhau `for r <= sheet.Rows.LastUsedIndex / for c <= sheet.Columns.LastUsedIndex`
đọc `sheet.Cells[r,c].Value`, rồi xóa từng dòng/cột trống một (`Rows.Remove(r)` trong vòng lặp).
- Template `PayrollMasterFileChange.xlsx` có style trên mọi cột (`<col ... max="16384" style="3"/>`, row spans 1:236) nên
  `Columns.LastUsedIndex` = 235 dù data chỉ tới cột 17.
- `LastUsedIndex` được tính lại ở mỗi vòng lặp và việc truy cập ô trống tốn kém -> chi phí tăng gần bậc hai theo số dòng.
Benchmark (PowerShell + DevExpress 19.1, template thật): 20 dòng 0.1s, 300 dòng 5.5s, 3000 dòng >600s (phải dừng).

## Cách sửa (Fix)
Dùng `sheet.GetDataRange()` (chỉ tính ô có giá trị, bỏ qua ô chỉ có định dạng) để lấy `BottomRowIndex`/`RightColumnIndex`,
và xóa dòng/cột thừa một lần bằng `Rows.Remove(index, count)` / `Columns.Remove(index, count)`.
Kết quả lastRow/lastCol giống hệt cách cũ; 3000 dòng còn 0.09s.

## Kiểm chứng (Verification)
- Script benchmark load template thật bằng DevExpress.Spreadsheet.v19.1 từ Cadena.WebApp/bin, fill N dòng x 17 cột, so sánh old/new:
  cùng lastRow/lastCol, new 0.09s ở 3000 dòng.
- Build Cadena.Modules.Payroll.csproj: không có lỗi ở file đã sửa (có lỗi có sẵn không liên quan do DLL reference cũ / thiếu Dlls\Microsoft.Dependency.dll khi build CLI).
- Chưa test end-to-end trên UI với dữ liệu thật.
- Số dòng thật kỳ 05/2026 (chạy 5 SP chỉ đọc, rollback): I=147, II=17, III=129 (10 nhóm), IV=158, V=1310 (2 nhóm) -> sheet ~1.800 dòng.
- Benchmark C# (.NET Framework, EPPlus + DevExpress 19.1 từ bin, file có merge I:K từng dòng + wrap text + border), 1.800 dòng:
  code cũ quét ô 254s (tổng 260s, vượt executionTimeout=110s); code mới quét 0.01s, tổng ~4.3s (load 1.6s, xuất PDF 2.6s).
- Benchmark bằng PowerShell cho số tuyệt đối sai lệch (overhead gọi .NET); dùng chương trình C# biên dịch bằng csc để đo đúng.

## Hướng đi sai (Dead ends)
- Nghi `Columns.LastUsedIndex` = 16383 vì template style tới cột 16384: đo thực tế chỉ = 235. Nguyên nhân chính là quét lặp + tính lại LastUsedIndex, không phải 16K cột.
- Không có log lỗi trong Cadena.WebApp/Logs -> đừng mất thời gian tìm exception, hãy đo thời gian xử lý.
- "Thời gian mở report tăng gấp đôi sau khi sửa": DownloadPdf không chạy khi mở. Nguyên nhân là app restart sau build (Application_Start 16-31s trong log)
  và SQL cache lạnh: 5 SP lần đầu ~71s, lần sau ~31s. SP chậm nhất khi mở: S_PAY_GetEmpHaveOtherTransChangeByPeriod (21-38s).

## Lần sau (Next time)
Report DevExpress/ASPxSpreadsheet "mở OK, download lỗi khi data lớn": tìm vòng lặp `sheet.Cells[r, c]` theo `LastUsedIndex` hoặc `Rows.Remove(i)` trong vòng lặp.
Thay bằng `GetDataRange()` + `Remove(index, count)`. Grep các report khác có cùng đoạn code copy-paste.
