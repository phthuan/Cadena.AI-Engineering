---
title: Chuyển Performance Monitoring từ MAI-02 (5.3.136) sang MOL-02 (5.3.143) — diff theo khoảng commit kéo theo merge commit, 5 file WebApp phải merge tay
project: std5
type: other
keywords: [move-source, Performance Monitoring, Cadena.Diagnostics, git apply --check, git apply --exclude, merge commit, Main.aspx, Web.config, Global.asax.cs, _5.SiteMapIndexing.txt, Cadena.WebApp.csproj, 671c418bea, 77e7366432]
files: [Cadena HRM 5.0/Cadena.NHibernateProvider/Diagnostics/*.cs, Cadena HRM 5.0/Cadena.WebApp/Main.aspx, Cadena HRM 5.0/Cadena.WebApp/Web.config, Cadena HRM 5.0/Cadena.WebApp/Global.asax.cs, Cadena HRM 5.0/Cadena.WebApp/Cadena.WebApp.csproj, Cadena HRM 5.0/Cadena.SQLScripts/_5.SiteMapIndexing.txt]
commit: (chưa commit ở đích NVW-MOL-02_5.3.143.0)
date: 2026-10-27
author: Claude Code (session of phthuan136)
status: active
---

## Triệu chứng (Symptom)
Chuyển 2 commit Performance Monitoring (671c418bea, 77e7366432) từ D:\Source Project\MAI-02\STD5 sang D:\Source Project\MOL-02\STD5.

## Nguyên nhân gốc (Root cause)
- Giữa 2 commit có merge commit 678a53cba9 sửa JobScheduler.cs và Main.aspx: `git diff A^ B` trên khoảng commit sẽ mang theo thay đổi của người khác.
- Ở đích, 5 file có context khác: _5.SiteMapIndexing.txt (cuối danh sách khác), Cadena.WebApp.csproj (số dòng), Global.asax.cs
  (không có dòng trắng sau `{`), Main.aspx (menu System Setup thụt 64/68 dấu cách thay vì 56/60), Web.config.
- Dependency đều có sẵn ở đích: NHibernate 4.0.4, ConfigurationFileCache trong ModuleRegister, JobDataKey.CompanyID, System.Web.Extensions. Đích dùng .NET 4.8 (nguồn 4.6.2): không ảnh hưởng.

## Cách sửa (Fix)
- `git show --binary --format= <commit>` cho từng commit (không lấy diff khoảng) → `git apply --check -v` → `git apply --exclude=<5 file>` cho commit 1, merge tay 5 file, rồi apply commit 2 (sạch).
- Merge tay bằng script Python đọc/ghi bytes, giữ BOM + CRLF (Main.aspx, Web.config, Global.asax.cs có BOM). Python trên máy: C:\Users\thuan.pn\AppData\Local\Programs\Python\Python314\python.exe (lệnh `python` là alias Microsoft Store).

## Kiểm chứng (Verification)
- 24 file mới giống hệt nguồn ở 77e7366432 (so hash sau khi bỏ CR). Số dòng thêm vào 5 file merge tay khớp nguồn (1/8/26/5/6).
- MSBuild VS2022 Debug Cadena.WebApp.csproj (kèm reference): 0 error; Cadena.NHibernateProvider.dll và Cadena.WebApp.dll được build lại chứa DiagnosticsRuntime / PerformanceMonitoringView.
- Chưa chạy app, chưa chạy SiteMap_PerformanceMonitoring.sql trên DB MOL-02.

## Hướng đi sai (Dead ends)
- `$(git diff --name-only ...)` làm danh sách file: đường dẫn có dấu cách bị tách → patch chỉ còn .gitignore.
- `git diff --pathspec-from-file` với 2 commit: lệnh không chạy (git báo usage).

## Lần sau (Next time)
Chuyển tính năng này sang branch khác: patch theo từng commit, exclude 5 file WebApp/SQLScripts, merge tay sau SQL Assistant trong Main.aspx (đo thụt lề trước),
build Cadena.WebApp, rồi chạy SiteMap_PerformanceMonitoring.sql. Chưa có bản sửa lỗi phân quyền (xem 2026-10-27-system-setup-page-superadmin-only-by-menu-basicform-no-permission-check.md).
