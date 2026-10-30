---
title: Lần đầu chạy source / sau khi update production, mở report (BasicForm) màn hình trắng rất lâu — compile .ascx lúc chạy + Application_Start; precompile bị chặn bởi trang mồ côi/lỗi
project: std5
type: performance
keywords: [first load slow, lần đầu mở chậm, màn hình trắng, treo, update source, deploy, Temporary ASP.NET Files, batch compilation, aspnet_compiler, PrecompileBeforePublish, EnableUpdateable, optimizeCompilations, ASPPARSE, Could not load type, CS1061, CS0123, DashboardViewer_DashboardLoading, Application_Start, CorrectDataLocalization, S_SETTING_BuildLocalizationsForFix, jenkins.pubxml, AscxToCopy]
files: [Cadena HRM 5.0/Cadena.WebApp/Global.asax.cs, Cadena HRM 5.0/Cadena.WebApp/Web.config, Cadena HRM 5.0/Cadena.WebApp/Web.Release.config, Cadena HRM 5.0/Cadena.WebApp/Properties/PublishProfiles/jenkins.pubxml, Cadena HRM 5.0/Cadena.WebApp/Properties/PublishProfiles/jenkins-ha.pubxml, Cadena HRM 5.0/Cadena.WebApp/Controls/DashboardViewer.ascx, Cadena HRM 5.0/Cadena.Core/Bootstrapper.cs]
commit:
date: 2026-10-28
author: Thuan Pham Ngoc (with Claude Code)
status: active
---

## Triệu chứng (Symptom)
Lần đầu chạy source (sau build) hoặc sau khi update bản production, mở một report trong Payroll Reports (vd Allowances & Deductions)
thì vùng nội dung trắng rất lâu. Các lần mở sau nhanh.

## Nguyên nhân gốc (Root cause)
Hai chi phí "lần đầu" cộng lại:
1. Application_Start (Global.asax.cs) 16-31s trên dev (log "Application starting." -> "Application started."): DevExpress init,
   Autofac quét Cadena.*.dll, build NHibernate SessionFactory (config đã cache ra file), và chạy job sửa dữ liệu ở MỌI lần start:
   CorrectDataLocalization, S_SETTING_BuildLocalizationsForFix + insert sitemap (DB ở máy khác). Chưa đo từng bước.
2. Markup .aspx/.ascx được compile lúc chạy: các profile jenkins.pubxml / jenkins-ha.pubxml KHÔNG precompile
   (chỉ local-ad.pubxml có PrecompileBeforePublish). Mỗi lần compile tham chiếu 233 assembly (~1.5s/lần đo bằng csc với đúng .cmdline của ASP.NET).
   Production (Release bỏ debug -> batch compile) compile cả thư mục khi trang đầu tiên của thư mục được mở
   (Modules/Cadena.Modules.Payroll/Views/Reports có 243 .ascx) — hành vi chuẩn của ASP.NET, chưa đo trên production.

## Cách sửa (Fix)
Chưa sửa. Hướng đề xuất:
- Production: bật precompile trong jenkins.pubxml (PrecompileBeforePublish=True, EnableUpdateable=False) + IIS Application Initialization
  (startMode=AlwaysRunning, preloadEnabled=true). Precompile cần dọn trang hỏng trước (xem Kiểm chứng).
- Dev: `<compilation debug="true" optimizeCompilations="true">`.
- Application_Start: đo từng bước; chỉ chạy job sửa dữ liệu localization/sitemap 1 lần mỗi version (hoặc chuyển vào script deploy).

## Kiểm chứng (Verification)
- aspnet_compiler trên bản copy của Cadena.WebApp (đúng bộ file Jenkins publish: ngoài Modules chỉ lấy Content trong csproj;
  Modules lấy toàn bộ Modules\**\*.ascx/aspx theo AscxToCopy) thất bại lần lượt vì:
  - 29 trang trong Modules có Inherits trỏ tới class không còn trong DLL (Competency, MasterData, Payroll ExchangeRateView/ReportsOfModulePayrollView,
    PerformanceAppraisal KPIs, Setting ImportSalaryRemarkView, Staffing/TimeAttendance DataSetup..., LeaveProfileView(2)).
  - Controls/DashboardViewer.ascx: CS0123 handler DashboardViewer_DashboardLoading sai kiểu delegate (control không được tham chiếu ở đâu).
  - Modules/Cadena.Modules.Competency/Views/EmployeeCompetencyManagement.ascx: CS1061 các handler gridCompetency_* không còn trong code-behind.
  - Có thể còn lỗi khác sau các lỗi này (đã dừng lặp).
- Bỏ tham chiếu Cadena.SQLScripts.dll (119MB) khỏi lệnh compile chỉ nhanh hơn 0.04s.

## Hướng đi sai (Dead ends)
- Nghi Cadena.SQLScripts.dll (119MB) làm compile chậm: đo 1.50s vs 1.47s -> không phải. Bootstrapper cũng đã skip SQLScripts.
- Lọc trang mồ côi bằng danh sách Content trong Cadena.WebApp.csproj: sai cho thư mục Modules (do build module copy vào và Jenkins publish bằng wildcard).
  Phải kiểm tra Inherits có tồn tại trong bin\Cadena*.dll.
- Tìm App_Web_*.dll trong Temporary ASP.NET Files để đo thời gian compile trang: ASP.NET xóa output cũ khi app restart, không còn dấu vết.

## Lần sau (Next time)
Mở trang lần đầu chậm sau build/deploy: xem log Application_Start, rồi chạy aspnet_compiler lên một bản copy theo đúng bộ file publish
để vừa đo thời gian vừa lộ trang hỏng. Quét trang có Inherits không tồn tại bằng reflection trên bin\Cadena*.dll thay vì chạy aspnet_compiler từng vòng (~75s/vòng).
