---
title: <một dòng: điều gì đã sai, dùng đúng những từ mà người khác sẽ dùng để tìm kiếm>
project: <project-key>
type: bug | security | performance | feature | other
keywords: [<nguyên văn thông báo lỗi>, <ClassName>, <MethodName>, <TableName>, <sp_Name>]
files: [<path/relative/to/product/repo>]
commit: <short hash của commit sửa lỗi, nếu đã commit>
date: YYYY-MM-DD
author: <tên>
status: active
---

## Triệu chứng (Symptom)
<Nguyên văn thông báo lỗi, endpoint hoặc màn hình, và các điều kiện gây ra lỗi.>

## Nguyên nhân gốc (Root cause)
<Thực sự sai ở đâu và sai gì (file, method, query).>

## Cách sửa (Fix)
<Đã thay đổi gì và vì sao đó là đúng chỗ để sửa.>

## Kiểm chứng (Verification)
<Cách đã xác nhận cách sửa: test đã chạy, query đã kiểm tra, các bước thủ công.>

## Hướng đi sai (Dead ends)
<Các giả thuyết đã điều tra và hóa ra sai, kèm bằng chứng đã loại bỏ chúng.
Ví dụ: "Nghi ngờ Redis cache; tắt cache đi thì kết quả không đổi.">

## Lần sau (Next time)
<Con đường ngắn nhất tới câu trả lời nếu triệu chứng này xuất hiện lại.>
