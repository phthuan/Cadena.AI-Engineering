---
title: Trang System Setup chỉ "SuperAdmin" nhờ ẩn menu — BasicForm.aspx?fid= không kiểm tra quyền, Performance Monitoring cấp token API cho mọi user đã đăng nhập
project: std5
type: security
keywords: [BasicForm.aspx?fid=, LoadFormUserControlToPageContainer, SupperAdmin, RoleAdminType, RoleAdminType.SupperAdmin, Main.aspx, PerformanceMonitoringView, DiagnosticsToken.Issue, PerformanceMonitoring.axd, SQLAssistantView, broken access control, IDOR, 1D16E437-2715-48B1-8D45-B5F5ECCE31B0]
files: [Cadena HRM 5.0/Cadena.WebApp/BasicForm.aspx.cs, Cadena HRM 5.0/Cadena.WebApp/Main.aspx, Cadena HRM 5.0/Cadena.WebApp/Views/PerformanceMonitoringView.ascx.cs, Cadena HRM 5.0/Cadena.NHibernateProvider/Diagnostics/DiagnosticsHandler.cs]
commit: (chưa sửa — phát hiện khi review 77e7366432)
date: 2026-10-27
author: Claude Code (session of phthuan136)
status: active
---

## Triệu chứng (Symptom)
Review kiến trúc Performance Monitoring. Mục menu chỉ hiện với SuperAdmin, nhưng bất kỳ user nào đã đăng nhập mở thẳng
`BasicForm.aspx?fid=1D16E437-2715-48B1-8D45-B5F5ECCE31B0` vẫn tải được trang và nhận token API 60 phút
(xem SQL text, parameter, user name; bật/tắt monitoring; đổi settings; chạy phân tích).

## Nguyên nhân gốc (Root cause)
- Mục System Setup chỉ được bảo vệ bằng `if RoleAdmin == SupperAdmin` trong Main.aspx (ẩn thẻ <p>).
- BasicForm.aspx.cs LoadFormUserControlToPageContainer chỉ tra SiteMap rồi LoadControl(UserControlUrl): không kiểm tra quyền form.
- PerformanceMonitoringView.Page_Load gọi DiagnosticsToken.Issue cho mọi UserAccount.Current; handler chỉ kiểm tra chữ ký + hạn.
- Các view SuperAdmin khác tự kiểm tra trong code (vd. CustomerAdminUserView/TenantAndCompanySetupView:
  `UserAccount.Current.RoleAdminType == (int)RoleAdminType.SupperAdmin`). SQLAssistantView cũng không kiểm tra (cùng lỗ hổng, có sẵn từ trước).

## Cách sửa (Fix)
Đề xuất (chưa làm): trong view chỉ Issue token khi RoleAdminType == SupperAdmin (không thì ẩn nội dung / redirect);
đưa role vào payload token và handler từ chối nếu không phải SuperAdmin. Kiểm tra tương tự cho SQLAssistantView.

## Kiểm chứng (Verification)
Chỉ đọc code (BasicForm.aspx.cs ~401-465, grep SupperAdmin toàn WebApp). Chưa thử bằng tài khoản không phải admin.

## Hướng đi sai (Dead ends)
- Giả định "dòng SiteMap / menu đã giới hạn quyền": sai, BasicForm không đọc quyền.

## Lần sau (Next time)
Mọi trang System Setup / trang nhạy cảm mới: tự kiểm tra RoleAdminType trong view (và trong mọi handler/API đi kèm),
không dựa vào việc ẩn menu trong Main.aspx.
