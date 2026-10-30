---
title: Sửa file bằng Get-Content -Raw | Set-Content -Encoding utf8 trong Windows PowerShell 5.1 làm hỏng ký tự Unicode (→ thành â†’, · thành Â·) và thêm BOM
project: common
type: bug
keywords: [Set-Content, Get-Content -Raw, "-Encoding utf8", Windows PowerShell 5.1, mojibake, "â†’", "Â·", BOM, EF BB BF, Out-File]
files: []
commit:
date: 2026-10-29
author: Claude (SQL Server Performance Tracker)
status: active
---

## Triệu chứng (Symptom)
Sau khi thay một chuỗi bằng `(Get-Content f -Raw).Replace(...) | Set-Content f -Encoding utf8`, mọi ký tự không phải ASCII trong file bị đổi: `→` thành `â†’`, `·` thành `Â·`. Lỗi lộ ra trong UI (output pane SSMS hiện "Â·"), không phải trong build. File còn bị thêm BOM (`EF BB BF`) ở đầu.

## Nguyên nhân gốc (Root cause)
Windows PowerShell 5.1 đọc file UTF-8 **không BOM** bằng code page ANSI (Windows-1252), nên mỗi byte của ký tự UTF-8 trở thành một ký tự riêng. `Set-Content -Encoding utf8` sau đó ghi các ký tự sai này ra dạng UTF-8 **có BOM**.

## Cách sửa (Fix)
- Sửa file bằng công cụ Edit, hoặc dùng .NET với encoding rõ ràng: `[IO.File]::ReadAllText(p)` (tự nhận UTF-8) và `[IO.File]::WriteAllText(p, c, (New-Object Text.UTF8Encoding($false)))`.
- Sửa file đã hỏng: thay chuỗi mojibake về ký tự gốc (ví dụ `sed -i 's/â†’/→/g; s/Â·/·/g'`) và bỏ BOM (`sed -i '1s/^\xEF\xBB\xBF//'`).

## Kiểm chứng (Verification)
Grep `Ã|Â|â€|â†` trên repo không còn kết quả; `head -c3 | od` không còn `357 273 277`; output pane SSMS hiển thị đúng `·` và `→`.

## Hướng đi sai (Dead ends)
- Chỉ kiểm tra bằng `Select-String` thấy chuỗi version mới đúng → tưởng lệnh thay thế an toàn. Phần hỏng nằm ở các dòng khác của file.

## Lần sau (Next time)
Không dùng Get-Content/Set-Content (PS 5.1) để sửa source code. Sau mọi lệnh sửa file hàng loạt, grep `Ã|Â|â€` trên các file vừa sửa.
