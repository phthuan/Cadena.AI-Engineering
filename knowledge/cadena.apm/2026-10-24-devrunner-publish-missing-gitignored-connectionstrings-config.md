---
title: DevRunner build lỗi ở bước publish WebApp - Could not find file 'Config\ConnectionStrings.config' (file bị git-ignore không có trong bản clone của workspace)
project: cadena.apm
type: bug
keywords: [Could not find file 'Config\ConnectionStrings.config', Copying file Config\ConnectionStrings.config to obj\Release\Package\PackageTmp, Microsoft.Web.Publishing.targets(3074,5), build-03-publish-webapp, Release build failed, monitoring was not started, HrmBuilder, EnsureLocalConnectionStrings, SourceAcquirer, configSource]
files: [tools/Cadena.APM.DevRunner/Build/HrmBuilder.cs, tools/Cadena.APM.DevRunner/Runtime/HrmConfigDiscovery.cs, tests/Cadena.APM.DevRunner.Tests/BuildPublishProfileTests.cs]
commit:
date: 2026-10-24
author: Thuan Pham Ngoc
status: active
---

## Triệu chứng (Symptom)
Developer Control Center, Start Monitoring trên source KH-BIGC-01\STD5: BUILDING thất bại,
"MSBuild failed (exit 1): see <workspace>\<session>\logs\build-03-publish-webapp.log". Console log hiển thị
`Microsoft.Web.Publishing.targets(3074,5): error : Copying file Config\ConnectionStrings.config to obj\Release\Package\PackageTmp\... failed. Could not find file 'Config\ConnectionStrings.config'`.
Bước Rebuild solution (build-02) thành công; chỉ bước publish thất bại.

## Nguyên nhân gốc (Root cause)
Bản copy của workspace là `git clone --shared` + checkout commit; sau đó chế độ WORKTREE chỉ copy những gì
`git status` liệt kê. File bị git-ignore không bao giờ được copy (chỉ `packages` được robocopy). Trong KH-BIGC-01,
`Cadena.WebApp/Config/ConnectionStrings.config` bị git-ignore (.gitignore dòng 215), nhưng Cadena.WebApp.csproj có
`<Content Include="Config\ConnectionStrings.config">`, nên bước copy khi publish web thất bại. (Bản WebAPI của file này được track,
nên chỉ WebApp thất bại.) Các source mà file này được track sẽ không bao giờ gặp lỗi này.

## Cách sửa (Fix)
HrmBuilder.Build, trước các bước publish: `EnsureLocalConnectionStrings` đọc Web.config của từng site
(HrmConfigDiscovery.ReadSite, đổi thành internal); nếu `<connectionStrings configSource=...>` trỏ tới một file không có trong
bản copy của workspace, nó ghi một `<connectionStrings />` rỗng vào đó (chỉ trong workspace, không có secret). StartCommand.ApplyRuntimeSettings
vốn đã ghi đè Config\ConnectionStrings.config trong bản copy runtime bằng placeholder không có password. Làm ở bước build,
không phải bước prepare, để một workspace đã được prepare (dùng lại) cũng được sửa.

## Kiểm chứng (Verification)
Test mới BuildPublishProfileTests.A_missing_local_ConnectionStrings_config_gets_an_empty_placeholder_in_the_workspace_copy_only.
DevRunner tests: 220 passed, 1 failed (HostingTests.Ctrl_c_helper..., test console Ctrl+C không liên quan; thất bại khi chạy từ một
shell không có console). Tại thời điểm viết, việc chạy lại Start Monitoring thật vẫn đang chờ.

## Hướng đi sai (Dead ends)
- Không có cho chính bug này. Không "sửa" bằng cách copy ConnectionStrings.config của source vào workspace: file đó chứa
  SQL password và thiết kế không bao giờ copy secret.

## Theo dõi tiếp (cùng ngày): tự động sử dụng đăng nhập được nhưng mở 0 trang
Kết quả scenario "login of bigc.admin did not complete" trong khi Control Center báo "completed". Telemetry (apm.span, trace của
POST /Login.aspx) cho thấy VerifyLoginHandler PASS + UPDATE Security_Users LastLoginDateTime, rồi Login1.CheckLicense →
MessageManager.Get: MS252 invalid license. Nguyên nhân: Licx\License.cad chỉ là `<Folder Include="Licx\" />` trong Cadena.WebApp.csproj,
nên output publish (build\webapp → rt\webapp) không có Licx. Cách sửa: RuntimeConfig.CopyLicense khi start (Licx của workspace → runtime,
không bao giờ ghi đè). Ngoài ra ScenarioHost giờ đánh dấu run thất bại khi mở 0 trang (trước đây báo là thành công).

## Lần sau (Next time)
Lỗi publish "Could not find file X" trong một session DevRunner → kiểm tra `git check-ignore -v X` trong source: một file bị ignore
nhưng được liệt kê là Content trong csproj sẽ không có trong bản clone. Tổng quát hóa EnsureLocalConnectionStrings nếu xuất hiện các file
Content bị ignore khác.
