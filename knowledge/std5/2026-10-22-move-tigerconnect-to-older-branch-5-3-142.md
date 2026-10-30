---
title: Chuyển TigerConnectApi từ 5.3.145 (HAS260102) sang 5.3.142 (OHM-01) - patch không apply được, thiếu AppSettingHelper, BaseApiClient không có constructor nhận name
project: std5
type: other
keywords: [move-source, TigerConnectApi, Cadena.TigerConnectApi, "error CS0103: The name 'AppSettingHelper' does not exist in the current context", "error CS1729: 'BaseApiClient' does not contain a constructor that takes 1 arguments", "'ApiResponseMessage<string>' does not contain a definition for 'Json'", TigerConnectApiClient, AppSettingHelper, BaseApiClient, ApiResponseMessage, MSB4062, git apply --include]
files: [Cadena HRM 5.0/Cadena.Web/API/Consumer/TigerConnectApiClient.cs, Cadena HRM 5.0/Cadena.Library/Common/AppSettingHelper.cs, Cadena HRM 5.0/Cadena HRM 5.0.sln, Cadena HRM 5.0/Services/Cadena.TigerConnectApi/Settings/CommonSettings.cs, Cadena HRM 5.0/Services/Cadena.TigerConnectApi/Settings/TigerConnectSettings.cs]
commit:
date: 2026-10-22
author: Thuan Pham Ngoc
status: active
---

## Triệu chứng (Symptom)
Chuyển phần việc TigerConnect chưa commit (project Services/Cadena.TigerConnectApi + các hook trong BusinessLayer/Core/Web/Staffing + SQL script)
từ D:\Source Project\HAS260102\STD5 (branch HAS260102_5.3.145.0) sang D:\Source Project\OHM-01\STD5 (branch OHM-01_5.3.142.0).
`git apply` toàn bộ diff thất bại ở 9 trên 15 file; sau khi merge thủ công, build lỗi với:
- TigerConnectApi: CS0103 'AppSettingHelper' does not exist (Settings/CommonSettings.cs, Settings/TigerConnectSettings.cs)
- Cadena.Web: CS1729 'BaseApiClient' does not contain a constructor that takes 1 arguments; CS0117 'ApiResponseMessage<string>' has no 'Json'

## Nguyên nhân gốc (Root cause)
5.3.142 cũ hơn 5.3.145:
- Cadena.Library/Common/AppSettingHelper.cs (override appSettings bằng biến môi trường, đi kèm bản sửa HA 09988b403e) không tồn tại trong 5.3.142.
- BaseApiClient trong 5.3.142 chỉ có constructor không tham số; các client tự đặt `this.ApiClientType = ...` (xem DawinboxInternalApiClient).
- ApiResponseMessage<T> trong 5.3.142 không có property Json.
- Các dòng context khác nhau (sln không có project FileAPI/OnboardingAndOffboarding và không có cấu hình ReleaseHA; AppSetting.cs, IAppSetting.cs,
  SQLScripts csproj, _2.CreateTableIndexing.txt, AppSettings.config có phần cuối khác nhau).

## Cách sửa (Fix)
- `git diff --binary > patch`; ở đích chạy `git apply --check -v` để liệt kê các file lỗi; `git apply --include=<file>...` cho các file sạch.
- Copy các file untracked từ `git ls-files --others --exclude-standard` bằng `cp -p` (giữ CRLF; ConnectionStrings.config bị ignore không được copy).
- Merge thủ công các file lỗi bằng tool Edit (thêm vào cuối danh sách / section). sln: bỏ các dòng cấu hình ReleaseHA.
- Copy AppSettingHelper.cs vào Cadena.Library ở đích + Compile Include (file mới, giữ các setting TigerConnectApi giống hệt nguồn).
- TigerConnectApiClient: constructor không tham số đặt ApiClientType; bỏ `Json = body` (không được dùng ở đâu).

## Kiểm chứng (Verification)
MSBuild Debug Services/Cadena.TigerConnectApi.csproj: thành công. MSBuild Cadena.Modules.Staffing: toàn bộ C# biên dịch được (Core, BusinessLayer, Web, module);
chỉ bước post-build Module.build thất bại với MSB4062 (thiếu Dlls\Microsoft.Dependency.dll trên máy này), không liên quan.
`git ls-files --eol` cho thấy mọi file đã sửa vẫn là w/crlf. Chưa chạy với database hoặc TigerConnect.

## Hướng đi sai (Dead ends)
- Apply toàn bộ patch bằng `git apply` thông thường: dừng ngay ở file lỗi đầu tiên; hãy dùng --check trước, rồi --include cho các file sạch.

## Lần sau (Next time)
Khi chuyển TigerConnect (hoặc bất kỳ tính năng 5.3.145 nào) sang một branch cũ hơn, trước tiên kiểm tra AppSettingHelper, constructor BaseApiClient(string) và
ApiResponseMessage.Json ở đích, sau đó build Cadena.TigerConnectApi.csproj và Cadena.Modules.Staffing.csproj.
Nhớ rằng đích cần Services/Cadena.TigerConnectApi/Config/ConnectionStrings.config được tạo từ file .sample (bị git-ignore).
