---
title: Project service mới (Cadena.TigerConnectApi) có App_Data/nh.cfg (chứa connection string) và Config/AppSettings.config (secret thật) không bị gitignore
project: std5
type: security
keywords: [nh.cfg, App_Data, AppSettings.config, ConnectionStrings.config, .gitignore, TIGERCONNECT_SECRET_KEY, TIGERCONNECT_JWT_SIGNING_KEY, TIGERCONNECT_CLIENT_CODE, connection.connection_string, Cadena.TigerConnectApi, git check-ignore]
files: [.gitignore, Cadena HRM 5.0/Services/Cadena.TigerConnectApi/App_Data/nh.cfg, Cadena HRM 5.0/Services/Cadena.TigerConnectApi/Config/AppSettings.config]
commit:
date: 2026-10-30
author: Thuan Pham Ngoc
status: active
---

## Triệu chứng (Symptom)
Phát hiện khi review kiến trúc các thay đổi TigerConnect (chưa commit). `git status` liệt kê dưới dạng untracked, và
`git check-ignore -v` không trả về gì cho:
- Services/Cadena.TigerConnectApi/App_Data/nh.cfg (~12 MB, cache NHibernate Configuration đã serialize, có chứa
  connection.connection_string)
- Services/Cadena.TigerConnectApi/Config/AppSettings.config (giá trị thật của TIGERCONNECT_CLIENT_CODE / SECRET_KEY / JWT_SIGNING_KEY)
Một lệnh `git add .` sẽ commit connection string và secret lên Gitea.

## Nguyên nhân gốc (Root cause)
.gitignore ignore nh.cfg theo từng đường dẫn project (Cadena.WebApp, Services/Cadena.WebAPI), không dùng pattern chung.
Khi tạo project mới, chỉ Config/ConnectionStrings.config được thêm vào .gitignore; nh.cfg do Cadena.Infrastructure.NHibernate
tự sinh lúc chạy và AppSettings.config chứa secret thì bị bỏ sót.

## Cách sửa (Fix)
Đề xuất (chưa áp dụng, chờ người dùng quyết định):
- Thêm vào .gitignore: `/Cadena HRM 5.0/Services/Cadena.TigerConnectApi/App_Data/nh.cfg` và
  `/Cadena HRM 5.0/Services/Cadena.TigerConnectApi/Config/AppSettings.config` (đã có AppSettings.config.sample).
- Nếu secret thật đã từng được commit hoặc chia sẻ: đổi SECRET_KEY / JWT_SIGNING_KEY.

## Kiểm chứng (Verification)
`git check-ignore -v <file>` không trả về gì; `grep -a "connection.connection_string" nh.cfg` có kết quả. Giá trị secret không được in ra.

## Hướng đi sai (Dead ends)
Không có.

## Lần sau (Next time)
Khi thêm một project web/service mới, chạy `git status --porcelain -uall <project>` rồi `git check-ignore -v` trên mọi file
trong App_Data/ và Config/ trước khi commit. Ưu tiên pattern chung (vd `**/App_Data/nh.cfg`) thay vì đường dẫn từng project.
