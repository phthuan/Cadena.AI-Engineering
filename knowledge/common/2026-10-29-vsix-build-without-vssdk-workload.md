---
title: SDK-style VSIX project builds the DLL but produces no .vsix when the VS extension workload is not installed (Microsoft.VSSDK.BuildTools)
project: common
type: other
keywords: [vsix, VSSDK, Microsoft.VSSDK.BuildTools, Microsoft.VsSDK.targets, VSToolsPath, CreateVsixContainer, VSIXInstaller, "is not a valid file path", Menus.ctmenu, _EmptyResource.resources, MSYS path conversion]
files: [src/PerformanceTracker.Vsix/PerformanceTracker.Vsix.csproj]
commit:
date: 2026-10-29
author: Claude (Visual Studio Performance Tracker)
status: active
---

## Triệu chứng (Symptom)
Máy có VS 2022/2026 nhưng KHÔNG cài workload "Visual Studio extension development" (Microsoft.VisualStudio.Component.VSSDK).
Project VSIX dạng SDK-style (`<Project Sdk="Microsoft.NET.Sdk">`) có tham chiếu `Microsoft.VSSDK.BuildTools` vẫn build thành công ra `PerformanceTracker.Vsix.dll`, nhưng không tạo ra file `.vsix`, pkgdef hay `.cto`, và cũng không báo lỗi gì.

## Nguyên nhân gốc (Root cause)
`build/Microsoft.VSSDK.BuildTools.props` của gói NuGet chỉ đặt `VSToolsPath` = `<package>\tools`. Gói này KHÔNG tự import `Microsoft.VsSDK.targets`.
Project phải tự import `$(VSToolsPath)\VSSDK\Microsoft.VsSDK.targets`. Với SDK-style, import này phải đứng SAU `Sdk.targets`; đặt trong thân project thì nó chạy quá sớm.

## Cách sửa (Fix)
Dùng import SDK tường minh:
```xml
<Project>
  <Import Project="Sdk.props" Sdk="Microsoft.NET.Sdk" />
  ... (GeneratePkgDefFile, UseCodebase, CreateVsixContainer, DeployExtension=false, VSCTCompile ResourceName="Menus.ctmenu") ...
  <Import Project="Sdk.targets" Sdk="Microsoft.NET.Sdk" />
  <Import Project="$(VSToolsPath)\VSSDK\Microsoft.VsSDK.targets" Condition="Exists('$(VSToolsPath)\VSSDK\Microsoft.VsSDK.targets')" />
</Project>
```
Dùng `Microsoft.VisualStudio.SDK` / `Microsoft.VisualStudio.LanguageServices` với `ExcludeAssets="runtime"` để không đóng gói DLL của VS/Roslyn vào VSIX.

## Kiểm chứng (Verification)
- Build bằng `MSBuild.exe` của VS 2026 sinh ra `bin\Release\net472\*.vsix`. `unzip -l` cho thấy chỉ có DLL của chính extension, pkgdef và manifest.
- Menu VSCT được merge vào `_EmptyResource.resources` với key `Menus.ctmenu`. Đây là cách VSSDK làm, KHÔNG phải lỗi: kiểm bằng `ResourceReader` sẽ thấy key này.
- `VSIXInstaller.exe /quiet /rootSuffix:Exp /instanceIds:<id>` cài thành công vào cả VS 2022 và VS 2026. ActivityLog ghi "Successfully loaded extension".

## Hướng đi sai (Dead ends)
- Nghĩ rằng thiếu workload VSSDK nên không thể đóng gói VSIX: sai, gói NuGet có đủ VSCT compiler, task tạo pkgdef và task tạo VSIX.
- Thấy DLL chỉ chứa `_EmptyResource.resources` nên tưởng menu chưa được nhúng: sai, menu nằm bên trong resource đó.
- Gọi `VSIXInstaller.exe /quiet ...` từ Git Bash thì nhận lỗi "invalid file path" (exit 209), vì MSYS chuyển `/quiet` thành đường dẫn. Phải chạy từ PowerShell (hoặc đặt `MSYS_NO_PATHCONV=1`).

## Lần sau (Next time)
Khi project VSIX build ra DLL mà không có `.vsix`, kiểm tra ngay xem có dòng import `$(VSToolsPath)\VSSDK\Microsoft.VsSDK.targets` sau `Sdk.targets` chưa. Chạy VSIXInstaller từ PowerShell.
