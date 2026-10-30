---
title: "devenv /rootSuffix Exp /Log <file.sln>" ghi đè file .sln bằng ActivityLog XML; VS Experimental thoát ngay hoặc kẹt ở hộp thoại lần đầu khi kiểm thử VSIX tự động
project: common
type: other
keywords: [devenv, /Log, ActivityLog.xml, /rootSuffix Exp, "No file format header found", VSIXInstaller, Experimental instance, MSBuildWorkspace, ComponentModelCache, Microsoft.VisualStudio.Default.err, "Used assemblies", "Destroying Main Window", "String load failed", "ID:1301", "is not valid", updateConfiguration, VS tự tắt, csproj bị ghi đè]
files: [samples/Samples.sln]
commit:
date: 2026-10-29
author: Claude (Security Code Analyzer)
status: active
---

## Triệu chứng (Symptom)
Khi kiểm tra VSIX bằng cách mở Visual Studio Experimental với solution mẫu:
`devenv.exe /rootSuffix Exp /Log "D:\...\Samples.sln"`
- VS 2026 Experimental tự thoát (exit code 0) sau vài giây, không có ActivityLog ở `%APPDATA%\Microsoft\VisualStudio\18.0_<id>Exp\`.
- Sau đó mọi lệnh mở solution báo lỗi `No file format header found.` (MSBuildWorkspace / dotnet sln).
- File `Samples.sln` bị thay bằng một file XML UTF-16 (~270 KB) bắt đầu bằng `<?xml version="1.0" encoding="utf-16"?>`.

## Nguyên nhân gốc (Root cause)
Switch `/Log` của devenv nhận một tham số **tùy chọn** là đường dẫn file log. Đặt đường dẫn `.sln` ngay sau `/Log` khiến VS coi file solution là file log và ghi ActivityLog đè lên nó; không có solution nào được mở.

## Cách sửa (Fix)
Luôn truyền đường dẫn log tường minh và đặt solution ở cuối:
`devenv.exe /rootSuffix Exp /Log "<scratch>\activity.xml" "<path>\Samples.sln"`
Khôi phục file `.sln` bị ghi đè từ git hoặc tạo lại.

## Kiểm chứng (Verification)
- Với log tường minh, ActivityLog được ghi vào đúng file (237–427 entry), không còn file nào trong repo bị sửa (`find . -newer <vsix>`).
- Xác nhận MEF component của extension được nạp bằng `%LOCALAPPDATA%\Microsoft\VisualStudio\<ver>_<id>Exp\ComponentModelCache\Microsoft.VisualStudio.Default.err`: các DLL của extension nằm dưới mục `----------- Used assemblies -----------` (đây là danh sách assembly được dùng, KHÔNG phải lỗi).

## Hướng đi sai (Dead ends)
- Nghĩ rằng VS 2026 Experimental crash do extension: Application Event Log không có crash, ActivityLog không có lỗi liên quan extension; nguyên nhân là tham số `/Log`.
- Thấy DLL của extension trong file `.err` và tưởng là lỗi MEF: thực ra nằm trong mục "Used assemblies".
- Chờ VS 2022 Experimental mở solution trong tự động hóa: instance Exp mới dừng ở hộp thoại lần đầu chạy/đăng nhập, không thể kiểm tra gạch chân/Quick Info mà không có người thao tác.
- Quét bản sao solution đã xóa `obj/` bằng MSBuildWorkspace: thiếu project.assets.json nên kiểu NuGet (Dapper, EF, SqlClient) không phân giải được, số phát hiện giảm từ 27 xuống 18. Phải `dotnet restore` trước khi quét.

## Cập nhật 2026-10-29 (chiều, bản 1.1.0)
- Chạy đúng cú pháp `devenv.exe /rootSuffix Exp /Log "<scratch>\activity.xml" "<sln>"` cho cả VS 2022 và VS 2026 trong phiên tự động: file `.sln` không bị đổi (đã so hash), nhưng cả hai instance Experimental vẫn tự thoát sau ~10 giây ("Shutting down pkgdef registry"), log không có lỗi nào của extension; lỗi MEF trong log là của thành phần VS chưa cài (VC++, Xamarin, LiveShare). Không mở được solution nên không kiểm tra được UI qua DTE/UIA. Nguyên nhân chưa xác định.
- MEF cache (`ComponentModelCache\*.err`) không được dựng lại sau khi cài đè 1.1.0 (vẫn mang thời gian của lần trước) nên không dùng được làm bằng chứng cho phiên bản mới.

## Cập nhật 2026-10-29 (Visual Studio Performance Tracker, audit 1.1.1)
- Lặp lại đúng lỗi `/Log` với `.csproj`: `devenv /rootSuffix Exp /log "<sample>.csproj"` thay file `.csproj` bằng ActivityLog XML UTF-16 (214 KB). Bất kỳ đường dẫn nào đứng ngay sau `/Log` đều bị ghi đè, không riêng `.sln`.
- Hiện tượng tự thoát đã được thu hẹp: VS 2022 và VS 2026 do agent khởi chạy tự đóng sau 3 giây – vài phút ở mọi hive (main, `Exp`, hive mới `PTAudit`), có hoặc không có extension đang kiểm thử, có hoặc không có solution. Mọi lần ActivityLog đều kết thúc bằng 3 dòng `String load failed. Pkg:{1B027A40-8F43-11D0-8D11-00A0C91BC942} LANG:0409 ID:1301`, đôi khi `Begin package load [ThreadedWaitDialogPackage]`, rồi `Destroying Main Window` và xuất settings (đóng bình thường, không crash).
- Đã loại trừ: extension (VS 2026 main, không cài extension đang kiểm thử, cũng tự đóng sau 74 giây với cùng dấu hiệu); client DTE nhả tham chiếu (lấy rồi nhả DTE, VS vẫn sống thêm 40 giây); bản cập nhật VS đang chờ (`dd_BackgroundDownload_*.log`: "Did not compute update information"); process lạ đóng VS (theo dõi mọi process mới mỗi 0,4 giây, chỉ thấy docker/DiagnosticsHub của chính VS). VS do người dùng tự mở trên cùng máy chạy hàng giờ bình thường.
- `extensions.configurationchanged` của hive Exp có thể cũ hơn lần cài VSIX; khi đó lệnh của extension không có trong `DTE.Commands` (`Command "..." is not valid`) dù MEF đã nạp analyzer. Chạy `devenv /rootSuffix Exp /updateConfiguration` trước khi kiểm tra lệnh.

## Lần sau (Next time)
Không đặt bất kỳ đường dẫn nào ngay sau `/Log` ngoài file log. Kiểm tra cài đặt VSIX bằng log của VSIXInstaller ("completed successfully") và file `.err` của ComponentModelCache; phần kiểm tra tương tác trong editor giao cho người dùng. Restore trước khi quét bằng MSBuildWorkspace. Nếu VS do agent mở tự đóng với dấu hiệu `String load failed ... ID:1301` → `Destroying Main Window`, không điều tra extension nữa: chạy VS main không có extension một lần để xác nhận, rồi giao kiểm thử UI cho người dùng và kiểm chứng logic bằng harness MSBuildWorkspace (xem `2026-10-29-msbuildworkspace-buildhost-vs18-max-path-immutable`).
