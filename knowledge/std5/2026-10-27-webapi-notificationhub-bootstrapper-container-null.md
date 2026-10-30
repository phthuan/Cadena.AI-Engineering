---
title: NotificationHub.OnConnected ArgumentNullException "Value cannot be null" in WebAPI - BootStrapper.Container is null because WebAPI never calls BootStrapper.Init
project: std5
type: bug
keywords: [ArgumentNullException, Value cannot be null, Autofac.dll, BootStrapper.Container, BootStrapper.Init, NotificationHub, OnConnected, IAppSetting, AllowMultiSignedInUserInstance, registerSignalR, SignalR, ESS/Main.aspx]
files: [Cadena HRM 5.0/Cadena.Web/Hubs/NotificationHub.cs, Cadena HRM 5.0/Cadena.Core/Bootstrapper.cs, Cadena HRM 5.0/Services/Cadena.WebAPI/Global.asax.cs, Cadena HRM 5.0/Cadena.WebApp/ESS/Main.aspx, Cadena HRM 5.0/Cadena.WebApp/Content/js/signalr.initial.js]
commit:
date: 2026-10-27
author: Thuan Pham Ngoc (with Claude)
status: active
---

## Triệu chứng (Symptom)
Mở http://localhost:60879/ESS/Main.aspx trong lúc debug WebAPI bằng Visual Studio thì dừng ở
`NotificationHub.OnConnected`, dòng `BootStrapper.Container.Resolve<IAppSetting>()`:
"System.ArgumentNullException occurred in Autofac.dll. Value cannot be null."
Production không thấy lỗi, người dùng không bị ảnh hưởng.

## Nguyên nhân gốc (Root cause)
- ESS Main.aspx mở 2 kết nối SignalR: `registerSignalR(..., setting.api, 'notificationHub')` tới hub của WebAPI,
  và `$.connection.hub.start()` tới hub của WebApp. Cả hai dùng chung class Cadena.Web.Hubs.NotificationHub.
- WebApp gọi `BootStrapper.Init()` nên có container. WebAPI tự build container trong Global.asax
  (biến cục bộ, chỉ gán cho `config.DependencyResolver`) và không bao giờ gọi `BootStrapper.Init()`,
  nên `BootStrapper.Container` là null trong process WebAPI. Autofac `Resolve()` trên context null thì ném ArgumentNullException.
- Lỗi có từ 12/2020 (commit ed805a78da). Không ai thấy vì: chỉ hiện khi debugger gắn vào process WebAPI,
  và kết nối thứ 2 (hub của WebApp) vẫn lo thông báo và đăng xuất phiên cũ.
- `BootStrapper.WebApiInit()` có bug tương tự (gán `container = builder.Build()` vào tham số), nhưng không ai gọi.

## Cách sửa (Fix)
- Thêm `BootStrapper.SetContainer(IContainer)` trong Cadena.Core/Bootstrapper.cs.
- WebAPI Global.asax.cs gọi `Cadena.Core.BootStrapper.SetContainer(container)` ngay sau `builder.Build()`.
  Container của WebAPI đã quét module nên có IAppSetting (Cadena.BusinessLayer/ModuleRegister.cs);
  WebAPI Config/AppSettings.config đã có key AllowMultiSignedInUserInstance.
- Không chọn cách null-check trong hub: chỉ giấu lỗi, chức năng trong OnConnected vẫn không chạy.

## Kiểm chứng (Verification)
- Build Cadena.WebAPI.csproj (kèm project references) bằng MSBuild: thành công, không lỗi.
- Chưa chạy thử: cần chạy WebAPI + WebApp, mở ESS/Main.aspx, xác nhận không còn exception ở OnConnected.

## Hướng đi sai (Dead ends)
- Nghĩ là regression gần đây: `git log -S` cho thấy Global.asax của WebAPI và dòng Resolve trong hub không đổi từ 2017-2020.
- Nghĩ hub chạy trong WebApp (port 60879): đúng là WebApp cũng host hub, nhưng popup đến từ kết nối tới WebAPI (setting.api).

## Lần sau (Next time)
Lỗi null từ `BootStrapper.Container` hoặc `IoCHelper` trong code dùng chung (Cadena.Web, Cadena.Core):
kiểm tra trước tiên đang chạy trong process nào. WebAPI không gọi BootStrapper.Init và không gọi IoCHelper.SetResolver
(dòng này vẫn đang bị comment trong WebAPI Global.asax), nên mọi chỗ dùng 2 thứ này trong WebAPI đều có thể bị null.
