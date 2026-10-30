---
title: Build, install and auto-test a VSIX extension on SSMS 21 (experimental instance, first-run dialogs, DTE in ROT, RPC_E_SERVERCALL_RETRYLATER, System.Text.Json conflict)
project: common
type: other
keywords: [SSMS 21, VSIX, "Connect to Server", "line endings in the following file are not consistent", File.Disconnect, --no-incremental, Microsoft.VisualStudio.Ssms, VSIXInstaller, rootSuffix Exp, "Invalid Command Line", RPC_E_SERVERCALL_RETRYLATER, 0x8001010A, "Could not get dispatch ID", "does not contain a definition for 'ToolWindows'", "!VisualStudio.DTE.17.0", ActivityLog, System.Text.Json, Anthropic SDK, ScriptDom 17.0.0.0, BM_CLICK]
files: [src/PerfTracker.Ssms/PerfTracker.Ssms.csproj, src/PerfTracker.Ssms/source.extension.vsixmanifest]
commit:
date: 2026-10-29
author: Claude (SQL Server Performance Tracker)
status: active
---

## Triệu chứng (Symptom)
Cần cài và kiểm thử tự động một VSIX trên SSMS 21 thật trong khi SSMS chính của người dùng đang mở và có thể có thay đổi chưa lưu. Gặp lần lượt các lỗi sau:
- `SSMS.exe /rootsuffix Exp /log /nosplash` hiện hộp thoại "Invalid Command Line." rồi thoát.
- Gọi DTE qua COM bị lỗi `RPC_E_SERVERCALL_RETRYLATER (0x8001010A)`. Qua `dynamic` thì lỗi có dạng `MissingMemberException: Could not get dispatch ID for Name (error: 0x8001010A)`.
- Tìm object trong ROT theo `":" + pid` thì lấy nhầm object, dẫn tới lỗi `'System.__ComObject' does not contain a definition for 'Name'`.
- `dte.ToolWindows` bị lỗi "does not contain a definition for 'ToolWindows'".

## Nguyên nhân gốc (Root cause)
- SSMS có cú pháp command line riêng: `-log` bắt buộc phải có tên file. `/rootsuffix Exp` vẫn được chấp nhận. Chỉ dùng `SSMS.exe /rootsuffix Exp` là chạy được.
- Experimental hive còn mới nên SSMS hiện các hộp thoại modal lần đầu: Sign in, hỏi về connection dialog mới, Connect to Server. Thêm hộp thoại "reload file?" nếu file đang mở bị ghi đè. Khi có hộp thoại modal, mọi lệnh gọi COM đều bị từ chối với 0x8001010A.
- Trong ROT, cùng PID còn có `!Microsoft Visual Studio Telemetry:<pid>`. Moniker đúng là `!VisualStudio.DTE.17.0:<pid>` (SSMS 21 dùng shell VS 17), và nó chỉ xuất hiện sau khi qua hết các hộp thoại lần đầu.
- Đối tượng lấy từ ROT là IDispatch của `DTE`, không phải `DTE2`. Phải đọc output pane qua `dte.Windows.Item("{34E76E81-EE4A-11D0-AE2E-00A0C90FFFC3}").Object.OutputWindowPanes`.
- Nút trong hộp thoại WinForms của SSMS không có UIA InvokePattern.
- Anthropic C# SDK 13.3.0 hỗ trợ netstandard2.0 nhưng cần System.Text.Json 10.0.6, trong khi SSMS 21 nạp System.Text.Json 9.0.0.0 (PublicAssemblies). Nếu nạp in-proc thì có rủi ro xung đột binding.

## Cách sửa (Fix)
- Manifest: `<InstallationTarget Id="Microsoft.VisualStudio.Ssms" Version="[21.0,22.0)">` + `<ProductArchitecture>amd64</ProductArchitecture>`, `AllUsers="false"` (cài per-user, không cần admin). Import `Microsoft.VsSDK.targets` sau `Sdk.targets` (xem bài học `2026-10-29-vsix-build-without-vssdk-workload`). `dotnet build` cũng tạo được .vsix.
- Không đóng gói các DLL SSMS đã có sẵn. Dùng một target `AfterTargets="GetVsixSourceItems"` để lọc `VSIXSourceItem`, chỉ giữ DLL của extension cùng ScriptDom 170.18 (assembly 17.0.0.0, giống bản SSMS 21 dùng). Thêm `[ProvideBindingPath]`.
- Phần gửi request AI: chạy ngoài process. Extension gọi CLI (net10, dùng Anthropic SDK) được đóng gói trong thư mục `cli\` của VSIX. Khi `Exec dotnet publish -o "..."`, không để dấu `\` ở cuối đường dẫn vì `\"` sẽ escape dấu nháy, khiến output đi sai chỗ.
- Cài vào experimental instance để không đụng tới SSMS chính: `VSIXInstaller.exe /quiet /rootSuffix:Exp /instanceIds:<InstallationID trong SSMS.isolation.ini> x.vsix`. Phải chạy từ PowerShell.
- Chạy `SSMS.exe /rootsuffix Exp`. Đóng các hộp thoại lần đầu bằng UIA (click "Skip and add accounts later." qua InvokePattern). Với nút WinForms, gửi `PostMessage(hwnd, BM_CLICK=0x00F5)` dùng `NativeWindowHandle`. Không chiếm focus của người dùng.
- Driver C# (net10, `dynamic`) tìm `!VisualStudio.DTE.17.0:<pid>`, retry khi gặp 0x8001010A, gọi `dte.ExecuteCommand("PerfTracker.Analyze")` (CanonicalName đặt trong VSCT là `.PerfTracker.Analyze`), rồi đọc nội dung document và output pane. Mỗi lần chạy dùng tên file test mới.

## Kiểm chứng (Verification)
- ActivityLog của hive Exp ghi "Successfully loaded extension 'SSMS Performance Tracker'". Output pane của package ghi "listening to Query.Execute ({52692960-56BC-4989-B5D3-94C47A513E8D}:1)".
- 12 lệnh xuất hiện trong `dte.Commands`. Analyze, Format, Apply Safe Fixes, Qualify và Expand SELECT * sửa đúng nội dung editor. Option được đặt qua `dte.Properties["Performance Tracker","General"]`.
- SSMS chính của người dùng (PID khác) giữ nguyên trong suốt quá trình.

## Hướng đi sai (Dead ends)
- Thêm `/log` không kèm file theo thói quen của VS: SSMS báo "Invalid Command Line".
- Tìm moniker theo `":" + pid`: lấy nhầm object Telemetry.
- Tăng thời gian retry 0x8001010A: không giúp gì, vì nguyên nhân là hộp thoại modal. Cần chụp cửa sổ bằng `PrintWindow` (không cần focus) để biết đó là hộp thoại nào.
- Tìm nút "No"/"Cancel" theo ControlType.Button: nút WinForms hiện dưới dạng Pane, không có pattern nào.

## Bổ sung khi kiểm thử 0.2.0 (Addendum)
- **Hộp thoại Connect lấy server từ danh sách gần đây**: `-S . -d db -E` trên command line bị bỏ qua. Khi chọn Authentication qua UIA, ô server nhảy về mục đầu tiên trong MRU (một server từ xa, kèm login SQL đã lưu mật khẩu), và bấm Connect sẽ kết nối tới server đó. Sau đó Object Explorer tự kết nối lại mỗi lần khởi động, và **mọi tab .sql mới đều tự kết nối** tới server đó. Cách làm an toàn: đặt server bằng ValuePattern, chọn Windows Authentication, **đọc lại cả hai giá trị và chỉ bấm Connect khi đúng; nếu sai thì Cancel**. Trước khi chạy `Query.Execute`, kiểm tra caption cửa sổ có `(local).` hoặc `<MÁY>.`. Ngắt Object Explorer bằng `View.ObjectExplorer` rồi `File.Disconnect`; khi đó mở file sẽ hiện hộp thoại Connect thay vì tự kết nối.
- **Hộp thoại "line endings are not consistent"** chặn mọi lệnh COM (0x8001010A kéo dài). Tạo file test với line ending thống nhất (CRLF).
- **Lệnh chạy nền**: khi command handler chạy công việc ngoài UI thread, `ExecuteCommand` trả về ngay. Phải chờ một dòng cụ thể xuất hiện trong output pane, không dùng sleep.
- **Hộp thoại WPF của extension**: điều khiển bằng UIA mà không cần focus (ValuePattern.SetValue cho TextBox, InvokePattern cho Button, SelectionItemPattern cho dòng ListView). Lệnh mở modal phải gọi `ExecuteCommand` trên một thread khác, vì lời gọi COM chỉ trả về khi modal đóng. Double-click bằng chuột không tự động hóa được nếu không chiếm chuột, nên thêm nút hoặc phím Enter dùng chung handler.
- **VSIX build incremental đóng gói manifest cũ**: đổi Version trong `source.extension.vsixmanifest` mà `dotnet build` vẫn ra VSIX mang version cũ. Dùng `--no-incremental` và kiểm tra version trong `extension.vsixmanifest` của VSIX sau khi build.
- **Nâng cấp**: chạy VSIXInstaller với VSIX version lớn hơn; bản cũ được thay thế (đã kiểm thử 0.1.0 → 0.2.0).

## Lần sau (Next time)
Dùng thẳng quy trình trên: build bằng `dotnet build`, cài bằng `VSIXInstaller /rootSuffix:Exp`, chạy `SSMS.exe /rootsuffix Exp`, kiểm tra cửa sổ con bằng UIA và đóng hộp thoại (PostMessage BM_CLICK cho WinForms), rồi tìm `!VisualStudio.DTE.17.0:<pid>` trong ROT. Thư viện cần System.Text.Json ≥ 10 thì không nạp vào SSMS 21; chạy nó ngoài process.
