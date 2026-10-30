---
title: Security Code Analyzer quét source thật - MSBuildWorkspace không mở được .slnx ("No file format header found"), đường dẫn > 260 ký tự khi restore, lộ secret qua bằng chứng của finding khác cùng dòng, bỏ sót HMAC replay khi xác minh tách nhiều method
project: common
type: security
keywords: ["No file format header found", .slnx, MSBuildWorkspace, OpenSolutionAsync, "exceeds the OS max path limit", "must be less than 260 characters", subst, NU1903, "Msbuild failed when processing the file", WorkspaceFailed, HmacSignature.Verify, FixedTimeEquals, replay, timestamp, nonce, SignatureValidationMiddleware, CommandDefinition, string.Format, valuesClauses, "public static string X =>", SecretSpans, evidence, SARIF]
files: [src/SecurityCodeAnalyzer.Cli/Program.cs, src/SecurityCodeAnalyzer.Core/Files/FileScanner.cs, src/SecurityCodeAnalyzer.Rules/Analyzers/ApiAuthenticationAnalyzer.cs, src/SecurityCodeAnalyzer.Rules/Infrastructure/ConstantMembers.cs, src/SecurityCodeAnalyzer.Rules/Infrastructure/TaintAnalysis.cs, src/SecurityCodeAnalyzer.Engine/SecurityScanner.cs]
commit:
date: 2026-10-29
author: Claude (Security Code Analyzer v1.1.0)
status: active
---

## Triệu chứng (Symptom)
Khi dùng CLI `sca` (Security Code Analyzer) quét bản sao của DocSign CoreService/WorkerService và chính bộ mẫu:
1. `Không mở được solution/project: No file format header found.` với file `.slnx` (định dạng mặc định của VS 2026 và `dotnet new sln` trên .NET SDK 10).
2. `dotnet restore` bản sao trong thư mục scratchpad dài báo `...\bin\Debug\net10.0\publish\/ exceeds the OS max path limit. The fully qualified file name must be less than 260 characters.`
3. Cảnh báo nạp project kiểu `Msbuild failed when processing the file ... Package 'NHibernate' 5.3.0 has a known high severity vulnerability`, thực ra chỉ là NuGet audit (NU1903) nhưng bị hiểu nhầm là quét lỗi.
4. Test SARIF thật phát hiện secret xuất hiện nguyên văn trong `snippet` của một finding KHÁC (customErrors) khi web.config viết trên một dòng.
5. DocSign có mã HMAC thật (`SignatureValidationMiddleware` → `HmacSignature.Verify` → `ComputeHmacSha256Hex`) nhưng không có finding replay; ngược lại 2 finding SQL Injection Dapper giả ở `DataTranslationReadRepository`.
6. Quét `samples/Samples.sln` báo "HSTS khai báo trùng" giữa hai web project của một solution KHÁC nằm trong thư mục con.

## Nguyên nhân gốc (Root cause)
1. Microsoft.CodeAnalysis.Workspaces.MSBuild 4.14 `OpenSolutionAsync` chỉ đọc định dạng `.sln` văn bản cũ.
2. Restore đánh giá đường dẫn publish dài; thư mục scratchpad của Claude Code đã dài ~150 ký tự.
3. `WorkspaceFailed` trả cả cảnh báo NuGet audit với kind Failure.
4. Bằng chứng (evidence) của mỗi finding chỉ che các vùng secret của CHÍNH finding đó; `SecretMasker.Scrub` không nhận dạng `key="...Secret" value="..."` của XML.
5. (a) Bộ phát hiện replay yêu cầu tạo HMAC + so sánh + đọc request trong CÙNG một method; code thật tách 3 lớp. DocSign thực sự không có timestamp/nonce trong luồng ký (đã xác nhận bằng grep: không có "timestamp"/"nonce" trong 6 file HMAC) → rủi ro replay cần xác minh với gateway. (b) SQL template khai báo `public static string X => @"..."` không có ConstantValue nên bị coi là dữ liệu không rõ nguồn; danh sách placeholder `valuesClauses.Add($"(@RowKey{i}, ...)")` cũng bị coi là không rõ nguồn.
6. Quét file theo solution duyệt đệ quy toàn bộ thư mục solution; file không thuộc project nào gom chung nhóm "(solution)".

## Cách sửa (Fix)
1. CLI: với `.slnx` đọc XML `<Project Path="...">` rồi `OpenProjectAsync` từng project; truyền `ScanOptions.SolutionDirectory` để đường dẫn tương đối/suppression/quét file vẫn đúng.
2. Quét bản sao qua ổ ảo: `subst R: <thư mục bản sao>`, xong `subst R: /D`. Xóa thư mục dài bằng `robocopy <thư mục rỗng> <đích> /MIR` rồi `Remove-Item`.
3. Gắn nhãn cảnh báo chứa "known ... vulnerability" là "NuGet audit (khi nạp project, không phải lỗi quét)".
4. `FileScanner.Scan` gom mọi vùng secret theo file và che trong bằng chứng của mọi finding (gộp vùng chồng lấn); thêm `ScrubKeyValueAttributes` vào `SecretMasker.Scrub`.
5. (a) Coi là "xác minh HMAC" khi method so sánh chữ ký (`FixedTimeEquals`/==) và tạo HMAC hoặc gọi method có tên chứa "Hmac", kèm tên Verify*/Validate*/IsValid* hoặc đọc request; tìm từ khóa replay trong cả method và class. (b) `ConstantMembers.TryGetText` đọc property/field static chỉ trả literal; `TaintAnalysis` coi phần tử thêm vào `List<string>` (Add/Insert/initializer) là giá trị của biến; chuỗi chỉ chứa hằng + số không cảnh báo SQL.
6. Bỏ qua thư mục con chứa `.sln/.slnx/.csproj` không thuộc solution đang quét; nhóm file không thuộc project theo thư mục chứa nó.

## Kiểm chứng (Verification)
- 133/133 unit test pass, gồm test hồi quy cho từng điểm (layered HMAC, placeholder list, static template, rò rỉ SARIF thật kiểm định bằng schema SARIF 2.1.0 chính thức, thư mục web không thuộc project).
- Quét lại bản sao DocSign: SQL Injection giả 2 → 0; HMAC replay 0 → 1 ở mỗi service; không còn chuỗi `Password=` chưa che trong mọi báo cáo.
- Bộ mẫu HRM: 36 finding ở bản lỗi, 0 ở bản đã sửa.

## Hướng đi sai (Dead ends)
- Thử `dotnet restore` trực tiếp trong scratchpad: lỗi 260 ký tự; không cần copy ra thư mục khác ngoài scratchpad, dùng `subst` là đủ.
- `cmd /c rd /s /q "\\?\..."` qua biến PowerShell bị chặn bởi kiểm tra an toàn (biến rỗng); `Remove-Item -Recurse` thất bại im lặng với đường dẫn dài.
- Tưởng thiếu replay chỉ cần tìm từ khóa trong method: code thật kiểm tra (nếu có) có thể nằm ở class/middleware khác.

## Lần sau (Next time)
Quét solution thật: copy (bỏ bin/obj/.git/.vs) vào scratchpad → `subst` ổ ngắn → `dotnet restore` → `sca scan` (hỗ trợ `.slnx`) → rà từng nhóm finding trên source rồi xóa bản sao (có secret thật). Mọi finding mới dạng "lộ secret" phải kiểm tra cả bằng chứng của finding khác trên cùng dòng.
