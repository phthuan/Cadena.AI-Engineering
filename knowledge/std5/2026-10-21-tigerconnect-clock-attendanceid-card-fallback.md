---
title: TigerConnect clock upload có thể gán punch cho sai nhân viên (fallback sang thẻ ngoài khoảng ngày gán, không lọc theo tenant)
project: std5
type: bug
keywords: [ClockAttendanceIdResolver, Resolve, UploadClockDataCommandHandler, BuildAttendanceIdResolver, EmployeeCard, AssignFromDate, AssignToDate, LocalEmployeeID, TIM_TKORawDatas, AttendanceID, MappingRawData, GetPenddingTKORawData]
files: [Cadena HRM 5.0/Cadena.BusinessLayer/TigerConnectApi/Handlers/ClockAttendanceIdResolver.cs, Cadena HRM 5.0/Cadena.BusinessLayer/TigerConnectApi/Handlers/UploadClockDataCommandHandler.cs, Cadena HRM 5.0/Cadena.BusinessLayer/AnalyzeTimeSheetData/AnalyzeInOut/MappingRawData.cs, Cadena HRM 5.0/Cadena.BusinessLayer/ImportData/Handlers/ImportRealTimeCommandHandler.cs]
commit:
date: 2026-10-21
author: Thuan Pham Ngoc
status: outdated
---

## Triệu chứng (Symptom)
Phát hiện trong một lần review kiến trúc, chưa thấy trên production. Một punch /api/Clock/Upload của nhân viên A có thể bị
phân tích thành punch của nhân viên B, hoặc không được map, sau khi gán lại thẻ hoặc trong database multi-tenant.

## Nguyên nhân gốc (Root cause)
TigerConnect gửi ReferenceID = LocalEmployeeID. ClockAttendanceIdResolver viết lại nó thành mã thẻ trước khi lưu
TKORawData.AttendanceID:
1. Khi không có thẻ nào của nhân viên còn hiệu lực vào ngày punch, nó fallback sang thẻ mới nhất của nhân viên
   (`?? cards.OrderByDescending(x => x.AssignFromDate).First()`). Phần phân tích (MappingRawData) map một AttendanceID
   dạng mã thẻ theo thẻ + ngày, nên nếu vào ngày đó thẻ thuộc về người khác thì punch sẽ đi về người đó.
2. Employee / EmployeeCard được query mà không có filter Tenant (ImportRealTimeCommandHandler có lọc theo TenantID).
   Một LocalEmployeeID tồn tại ở hai tenant cho ra 2 ứng viên, nên ReferenceID gốc được giữ nguyên.
Phần phân tích vốn đã map raw data đang chờ theo cả LocalEmployeeID, nên giữ nguyên ReferenceID luôn là một fallback an toàn.

## Cách sửa (Fix)
- 2026-10-28 (người dùng duyệt): đã bỏ fallback "thẻ mới nhất". Resolve lấy thẻ hiệu lực vào ngày punch
  (FirstOrDefault trên danh sách đã sắp xếp AssignFromDate giảm dần); không có thẻ hiệu lực thì giữ nguyên ReferenceID.
- Chưa sửa: lọc Employee / EmployeeCard theo tenant (cần quyết định cách API xác định tenant).
- 2026-10-29 (người dùng xác nhận): ReferenceID của /api/Clock/Upload CHÍNH LÀ AttendanceID. ClockAttendanceIdResolver đã bị xóa;
  UploadClockDataCommandHandler lưu thẳng ReferenceID (đã trim) vào TKORawData.AttendanceID. Bài học này không còn áp dụng.

## Kiểm chứng (Verification)
Đọc code: so sánh ClockAttendanceIdResolver với ImportRealTimeCommandHandler và MappingRawData.
2026-10-28: MSBuild Cadena.BusinessLayer thành công. Không test, không chạy trên database.

## Hướng đi sai (Dead ends)
Không có.

## Lần sau (Next time)
Với lỗi "punch hiển thị ở sai nhân viên" từ TigerConnect, trước tiên kiểm tra TIM_TKORawDatas.AttendanceID so với
ngày gán của TIM_EmployeeCards vào ngày punch, sau đó đến ClockAttendanceIdResolver.Resolve.
