---
title: MSBuildWorkspace (Roslyn 4.14/5.0) không mở được solution .NET Framework trên máy có VS 2026 (MSBuild 18) - BuildHost timeout do MAX_PATH và XMakeElements do System.Collections.Immutable 10
project: common
type: other
keywords: ["No instances of MSBuild could be detected", "The operation has timed out", NamedPipeClientStream.ConnectInternal, BuildHostProcessManager, "The type initializer for 'Microsoft.Build.Shared.XMakeElements' threw an exception", RemoteInvocationException, BuildHost-net472, MSBuildLocator, MAX_PATH, System.Collections.Immutable 10.0.0.8, Workspaces.MSBuild, OpenSolutionAsync]
files: []
commit:
date: 2026-10-29
author: Claude (Visual Studio Performance Tracker)
status: active
---

## Triệu chứng (Symptom)
Harness console dùng `MSBuildWorkspace.OpenSolutionAsync` để chạy Roslyn analyzer trên solution .NET Framework lớn (Cadena HRM 5.0, 59 project) lần lượt gặp:
1. `InvalidOperationException: No instances of MSBuild could be detected.` khi harness target `net8.0`.
2. `System.TimeoutException: The operation has timed out.` tại `NamedPipeClientStream.ConnectInternal` / `BuildHostProcessManager.BuildHostProcess..ctor`.
3. `RemoteInvocationException: ... The type initializer for 'Microsoft.Build.Shared.XMakeElements' threw an exception.` khi `LoadProjectFileAsync`.

## Nguyên nhân gốc (Root cause)
1. Máy chỉ có .NET SDK 9/10; `MSBuildLocator.RegisterDefaults()` trong process `net8.0` không dùng được SDK mới hơn runtime.
2. Từ Roslyn 4.9, MSBuildWorkspace nạp project qua process `BuildHost-net472\Microsoft.CodeAnalysis.Workspaces.MSBuild.BuildHost.exe`. Khi output nằm trong thư mục scratchpad dài, đường dẫn exe > 260 ký tự: process .NET Framework không khởi động được (`cmd` báo "is not recognized", exit -1, không có log), và chính bước build cũng không ghi được `BuildHost.exe.config`. Harness chỉ thấy timeout của named pipe. Tắt sandbox không có tác dụng.
3. BuildHost-net472 đóng gói `System.Collections.Immutable` 9.0.0.0 và có binding redirect cố định về 9.0.0.0; MSBuild của VS 2026 (18.x) cần 10.0.0.8 (cùng System.Memory 4.0.5, Buffers 4.0.5, Unsafe 6.0.3, Tasks.Extensions 4.2.4, Numerics.Vectors 4.1.6). Gói 4.14.0 và 5.0.0 đều lỗi như nhau.

## Cách sửa (Fix)
- Harness target `net10.0`, gói `Microsoft.Build.Locator` 1.7.8, `Microsoft.CodeAnalysis.Workspaces.MSBuild` 5.0.0.
- Build ra thư mục ngắn: `dotnet build -c Release -o "$env:TEMP\pth"`.
- Chỉ trong bản copy tạm của harness: copy các DLL trên từ `C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin` vào `BuildHost-net472\` và sửa `newVersion` trong `Microsoft.CodeAnalysis.Workspaces.MSBuild.BuildHost.exe.config` cho khớp (SCI 10.0.0.8, ...). Mỗi lần build lại `-o` sẽ ghi đè các file này, phải áp lại bản vá.
- Có thể dùng thẳng code của VSIX trong harness bằng `<Compile Include="...\SolutionPerformanceAnalyzer.cs" />` để đo đúng đường chạy của tool window.

## Kiểm chứng (Verification)
- HRM: 59 project, 18.158 document, 0 lỗi biên dịch (`compilation.GetDiagnostics()`), nên semantic model đầy đủ; nạp solution 11–29 giây, dựng compilation 58–92 giây.
- `git status --porcelain` và hash của `git diff` trong repo HRM giống hệt trước/sau khi chạy (MSBuildWorkspace chỉ đọc).

## Hướng đi sai (Dead ends)
- Tắt sandbox (`dangerouslyDisableSandbox`) để sửa lỗi timeout named pipe: vẫn timeout; nguyên nhân là MAX_PATH.
- Copy thư mục output sang đường dẫn ngắn: một số file (`.exe.config`, `.deps.json`) không tồn tại ở nguồn vì build đã không ghi được chúng; phải build lại với `-o` ngắn.
- Nâng Workspaces.MSBuild 4.14 → 5.0.0 để sửa `XMakeElements`: vẫn lỗi vì 5.0.0 vẫn redirect SCI về 9.0.0.0.

## Lần sau (Next time)
Build harness MSBuildWorkspace ra `%TEMP%\<tên ngắn>`, target net10.0, rồi kiểm tra version `System.Collections.Immutable` trong `MSBuild\Current\Bin` so với `BuildHost-net472` trước khi chạy; nếu khác thì vá DLL + binding redirect như trên.
