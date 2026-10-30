---
title: RateLimiter.NumItems / RateLimiter.TimePeriod có giá trị mặc định khác nhau ở mỗi nơi đọc chúng
project: std5
type: feature
keywords: [RateLimiter.NumItems, RateLimiter.TimePeriod, RateLimiter.MaxTrackedClients, RequestRateLimiter, CommonSettings, AppSettingHelper.GetConfigValue, ConfigurationManager.AppSettings, ISettingsProvider, Func<TigerConnectSettings>]
files: [Cadena HRM 5.0/Services/Cadena.TigerConnectApi/Settings/CommonSettings.cs, Cadena HRM 5.0/Services/Cadena.TigerConnectApi/Settings/ISettingsProvider.cs, Cadena HRM 5.0/Services/Cadena.TigerConnectApi/RateLimiting/RequestRateLimiter.cs, Cadena HRM 5.0/Cadena.BusinessLayer/ConfigManager/AppSetting.cs, Cadena HRM 5.0/Cadena.Library/Security/RateLimiter.cs]
commit:
date: 2026-10-20
author: Thuan Pham Ngoc
status: active
---

## Triệu chứng (Symptom)
Không có lỗi. Nếu một key RateLimiter.* bị thiếu hoặc gõ sai, rate limit thực tế âm thầm thay đổi,
và thay đổi rất nhiều tùy vào đoạn code nào đọc nó. Phát hiện trong một lần review kiến trúc appSettings của Cadena.TigerConnectApi.

## Nguyên nhân gốc (Root cause)
Cùng các key được đọc ở nhiều nơi, mỗi nơi có giá trị mặc định hard-code riêng:
- Cadena.BusinessLayer/ConfigManager/AppSetting.cs: NumItems mặc định 10, TimePeriod mặc định 1.
- Cadena.Library/Security/RateLimiter.cs: NumItems mặc định 15, TimePeriod mặc định 1.
- Cadena.TigerConnectApi RequestRateLimiter (trước khi sửa): 15 mỗi 1 s, trong khi AppSettings.config của nó đặt 20 mỗi 60 s
  và tài liệu của nó ghi 10. Một key bị thiếu biến 20/phút thành 15/giây (lỏng hơn khoảng 45 lần).
Rate limiter của TigerConnectApi còn đọc trực tiếp ConfigurationManager.AppSettings, nên bỏ qua cơ chế
override bằng biến môi trường mà mọi key khác có được qua AppSettingHelper.GetConfigValue.

## Cách sửa (Fix)
Chỉ trong Cadena.TigerConnectApi:
- Các key rate limit và giá trị mặc định giờ nằm trong CommonSettings (gộp chung với các setting HTTPS/trusted-proxy; secret vẫn ở TigerConnectSettings). Class này sở hữu các key và giá trị mặc định (20 / 60 s, giống cấu hình đi kèm bản phát hành); MaxTrackedClients không còn là appSetting mà là hằng số RequestRateLimiter.MaxTrackedClients = 10000,
  đọc qua AppSettingHelper, báo cáo các key có đặt nhưng không hợp lệ trong InvalidKeys (ghi log mức warning trong Global.asax).
- ISettingsProvider<T> / SettingsProvider<T> mới thay thế Func<TSettings>. Các service đọc .Current một lần cho mỗi thao tác.
  Bản thân các class settings không còn được đăng ký trong Autofac, nên không singleton nào có thể giữ một bản copy cũ.
- Config/AppSettings.config.sample mô tả mọi key.
Giá trị mặc định của WebAPI / BusinessLayer / Library KHÔNG được thay đổi (ngoài phạm vi).

## Kiểm chứng (Verification)
MSBuild Cadena.TigerConnectApi.Tests, sau đó vstest.console: 187/187 passed, bao gồm các test mới
CommonSettingsTests và SettingsProviderTests.

## Hướng đi sai (Dead ends)
Đã cân nhắc đổi tên key thành TIGERCONNECT_RATE_LIMIT_*; bị loại vì tài liệu được sinh ra trong
Services/Docs/TigerConnectApi và Cadena.WebAPI dùng RateLimiter.*.

## Lần sau (Next time)
Khi một rate limit "không được áp dụng như đã cấu hình", grep tên key trên toàn bộ solution và so sánh
các giá trị mặc định. Trong TigerConnectApi, nguồn sự thật duy nhất là Settings/CommonSettings.cs.
