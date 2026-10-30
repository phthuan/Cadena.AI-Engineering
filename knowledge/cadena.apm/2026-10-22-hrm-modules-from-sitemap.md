---
title: Danh sách module HRM lấy từ SiteMap_SiteMaps cho báo cáo APM — các dòng Module, key lấy từ qualifiedName, map issue vào module theo thư mục code
project: cadena.apm
type: feature
keywords: [SiteMap_SiteMaps, ClassType, Module, qualifiedName, pathUrl, PhysicalPath, hrm.modules.json, HrmModules, HrmModuleReader, --modules, performance-report modules, Login failed for user]
files: [src/Cadena.APM.Analyzer/HrmModules.cs, src/Cadena.APM.Analyzer/PerformanceReport.cs, tools/Cadena.APM.DevRunner/Runtime/HrmModuleReader.cs, tools/Cadena.APM.DevRunner/Commands/StartCommand.cs, src/Cadena.APM.Collector/Api/CodeMapCatalog.cs, src/Cadena.APM.Collector/wwwroot/dashboard/perf.js]
commit: (chưa commit)
date: 2026-10-22
author: Claude Code (session of phthuan136)
status: active
---

## Triệu chứng (Symptom)
Người dùng muốn chọn những module HRM mà source scan / báo cáo bao phủ (Payroll, phân tích timesheet, Insurance …), lấy từ
bảng HRM SiteMap_SiteMaps, vì nhiều function chậm hiếm khi được dùng.

## Nguyên nhân gốc (Root cause)
(Tính năng, không phải bug.) Các sự thật mà tính năng phụ thuộc vào:
- **Bảng dữ liệu.** SiteMap_SiteMaps là một bảng duy nhất với discriminator `ClassType`: Module / BasicForm / DynamicForm /
  *Group (FluentNHibernate SiteMapMapping.cs). Đây là một cây thông qua `ParentID`. Các dòng Module có PhysicalPath, PathUrl,
  Installed và QualifiedName.
- **Dữ liệu thật** (SGS-02_30092026, 25 dòng Module):
  - `physicalPath` RỖNG.
  - `pathUrl` = `Modules/Cadena.Modules.<X>` và `qualifiedName` = `Cadena.Modules.<X>`. `Name` đã là tên trong code
    (Payroll, TimeAttendance, LeaveManagement …).
  - Các module ESS (EClaim, ELeave …) và "Main" (Cadena.WebApp) có sortOrder 0.
- **Code.** Code HRM được chia theo thư mục module: Cadena.Modules.<X> trong WebApp, Cadena.BusinessLayer/<X>. Một vài
  thư mục không mang tên module: AnalyzeTimeSheetData và ClockInOut thuộc TimeAttendance, Reward thuộc
  RewardDiscipline.

## Cách sửa (Fix)
- **DevRunner** `--modules`: một câu SELECT read-only qua DB connection đã resolve của session (cùng shared-DB guard như
  --contention) → `codemaps/<deployment>/hrm.modules.json`.
- **Analyzer** `HrmModules`:
  - Key lấy từ `Cadena.Modules.X` trong các đường dẫn.
  - Module của một issue là thư mục đầu tiên của file chứa nó, sau đó đến namespace, rồi đến các C# caller của SQL đó.
  - Báo cáo được lọc theo `?modules=`.
- **Dashboard**: các checkbox trên tab Summary của #/report. Lựa chọn chỉ được lưu trong hash, vì có một test cấm
  localStorage.

## Kiểm chứng (Verification)
- Analyzer 214/214 (net10.0, net48), DevRunner 217/217, DevControl 101/101, Collector 172 passed + 7 skipped, dashboard JS 42/42.
- Live: `start --session smoke --scan-only --modules --db-from-source --confirm-shared-db` đọc được 25 module từ
  SGS-02_30092026.

## Hướng đi sai (Dead ends)
- `sqlcmd -E` vào HRS05\SQL2017CSS: "Login failed for user 'CADENA\thuan.pn'". Windows auth không được phép ở đó. Không
  tự lục SQL login từ cấu hình HRM: hãy để DevRunner resolve (`--db-from-source`).
- Chạy start mà chưa có `--confirm-shared-db` trước là một lần dry run an toàn: nó từ chối và in ra Server / Database. Dùng cách này để
  kiểm tra đích trước khi xác nhận. Trên HRS05 chỉ SGS-02_30092026 được phép.
- localStorage để ghi nhớ lựa chọn: bị cấm bởi perf.views.test.js (source scan tìm 'localStorage').

## Cập nhật 2026-10-24: cây menu như HRM hiển thị
- Nhãn: `Localization_LocalTexts.EnglishText` có cùng ID với dòng SiteMap (Main.aspx: LocalTextManager.GetLocalText(id, name)).
- Sidebar (SiteMapNhRepository.LoadFullModuleInfos): module (IsPublic) → các con trực tiếp có IsShowInNavBar = 1 và không phải
  IsMasterPage / IsImportPage / IsReportPage; sắp xếp theo SortOrder, rồi Name; SupportCountryID IS NULL hoặc = Company.BusinessCountryID
  (MultiTenant_Companies.BusinessCountryID → FIX_SupportCountries).
- Các mục hub trong sidebar là BasicForm theo UserControlUrl: `DataSetupView.ascx` ("<X> Data Setup": các con DataSetupGroup của module
  → các trang, theo tên), `MasterReportView.ascx` (ReportGroup → các trang báo cáo), `MasterImportView.ascx` (ImportGroup).
- CAM_BIGC_01: Payroll có tổng cộng 168 trang nhưng chỉ 51 trang trong menu KHM. Nhiều trang bị giới hạn theo quốc gia (VNM / IDN / SGP / MYS …) hoặc bị ẩn.
- hrm.modules.json schema 2: pages (+label, master, navBar, country, depth), groups, countries. Control Center hiển thị cây menu
  với bộ lọc quốc gia (mặc định: quốc gia của các company).
- Bẫy: Control Center (DevControl) được chạy dưới Visual Studio debugger; một breakpoint ở đó làm treo mọi request /control/v1.

## Lần sau (Next time)
Đọc hrm.modules.json của session để có module key thật. Để hỗ trợ từng function riêng lẻ (dòng BasicForm: UserControlUrl →
type code-behind của .ascx), code map cần các liên kết page → presenter → command → handler. Lên kế hoạch như một tính năng call-graph.
