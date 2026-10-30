---
title: Lack of Rate Limiting - Add Employee x50, login, Admin login, OTP, quên mật khẩu, Mobile GetToken không giới hạn; RateLimiter của master bị comment
project: std5
type: security
keywords: [Lack of Rate Limiting, Brute Force, CWE-307, CWE-770, Too many attempts, 429, Retry-After, RateLimiter, IsPermitted, RateLimitModule, RateLimiter.Action, RateLimiter.Auth, RateLimiter.MaxTrackedKeys, ClientIpResolver, X-Forwarded-For, RateLimiter.TrustedProxies, token bucket, __CALLBACKID, __EVENTTARGET, RequestAction, DXUploadingCallback, cbAddNewEmployeeView, SaveEmployee, LoginAuthorization, ValidateEmailOtpMfa, SendEmailOtp, ResendEmailOtp, GetToken, GetAppToken]
files: [Cadena HRM 5.0/Cadena.Library/Security/RateLimiting/RateLimiter.cs, Cadena HRM 5.0/Cadena.Library/Security/RateLimiting/RateLimitModule.cs, Cadena HRM 5.0/Cadena.Library/Security/RateLimiting/ClientIpResolver.cs, Cadena HRM 5.0/Cadena.WebApp/Config/AppSettings.config, Cadena HRM 5.0/Services/Cadena.WebAPI/Config/AppSettings.config]
commit:
date: 2026-10-28
updated: 2026-10-29
author: Thuan Pham Ngoc (with Claude)
status: active
---

## Triệu chứng (Symptom)
Pentest: "Lack of Rate Limiting". Case thực tế trong báo cáo: Burp Intruder gửi 50 lần `POST /BasicForm.aspx?fid=f9f6dd47-5754-4940-9347-a3f700a5bacd`
(Add New Employee, callback `cbAddNewEmployeeView` tham số `SaveEmployee`, đổi `LocalIDClientName` 2..51) và cả 50 nhân viên được tạo
("MS045 Employee 51 has been saved successfully"). Không phải login - hỏi ảnh/request của pentest TRƯỚC khi audit.
Branch TMF-MTL-02 không có rate limit ở đâu (WebApp, WebAPI), không có IIS Dynamic IP Restrictions.

## Nguyên nhân gốc (Root cause)
- Chỉ có khóa tài khoản theo user (`LoginAuthorization`, policy `IsAutoLockWhenFailLogins`/`LimitedWrongLoginTimes`, cấu hình trong DB theo tenant).
  Không có giới hạn tần suất cho thao tác nghiệp vụ, Admin login `cdn.admin`, OTP verify/gửi OTP, Forgot password (reset ngay + gửi mail),
  Mobile `GetToken`, `auth/token`.
- Master (`C:\SourceCode\STD5`) có `Cadena.Library/Security/RateLimiter.cs` (token bucket, namespace sai `Cadena.BusinessLayer`) nhưng
  `IsPermitted` bị COMMENT trong cả 3 Global.asax; key = `Request.Url` (chung toàn hệ thống, né bằng query string), quét cả bảng mỗi
  request, không giới hạn số key, ném Exception (500), race trong `AddOrUpdate` (biến `permitted` không reset khi delegate chạy lại),
  request đầu tiên luôn qua nên NumItems=0 không tắt được, TimePeriod=0 chia cho 0, parse config theo culture.

## Cách sửa (Fix)
Bản 2 (2026-10-29, thay bảng rule hard-code theo màn hình vì khó cho dev; yêu cầu "đơn giản như source tham chiếu"):
- Chỉ 3 file trong `Cadena.Library/Security/RateLimiting/`:
  - `RateLimiter`: token bucket như master nhưng sửa lỗi: lock theo bucket, đếm key bằng Interlocked (không gọi `ConcurrentDictionary.Count`),
    giới hạn `RateLimiter.MaxTrackedKeys` (mặc định 100.000/limiter, đầy thì fail-open), dọn bucket rảnh ≥ TimePeriod mỗi phút,
    đồng hồ Stopwatch (không nhảy theo giờ hệ thống), NumItems=0 tắt, parse InvariantCulture, trả retry-after giây.
  - `RateLimitModule`: IHttpModule (PostAcquireRequestState) tự đăng ký bằng `[assembly: PreApplicationStartMethod]` khi có key
    `RateLimiter.NumItems`. Không sửa Web.config/page/controller.
  - `ClientIpResolver`: giữ nguyên (chỉ tin X-Forwarded-For từ `RateLimiter.TrustedProxies`).
- 3 tầng chung, KHÔNG khai báo theo màn hình:
  - Global `RateLimiter.NumItems/TimePeriod` (15/1s): mọi request trừ file tĩnh, đếm theo identity
    (`Session["UserName"]` → hash header `Token`/`AppToken` (không dùng cho endpoint Auth) → SessionID nếu session không phải mới
    (`!IsNewSession`, Global.asax có `Session_Start` nên ID ổn định) → IP). Nhờ SessionID, 1.000 nhân viên chung IP NAT login
    không chặn nhau; cookie giả/ngẫu nhiên là session mới nên rơi về IP.
  - Anonymous `RateLimiter.Anonymous.*` (mặc định 200/1s): thay Global cho request chỉ nhận diện được bằng IP (chưa có session),
    để văn phòng NAT đông người mở trang cùng lúc không bị chặn. Trên ~300/s không nên: mỗi request không cookie tạo 1 session InProc
    (Global.asax có Session_Start, timeout 20 phút) → 300/s ≈ 360.000 session/IP trong RAM.
  - Bị chặn khi trình duyệt mở trang (GET + Accept text/html, không X-Requested-With): trang HTML "The system is busy" + meta refresh
    (không dùng script vì CSP nonce). Callback/AJAX/API vẫn JSON.
  - Action `RateLimiter.Action.*` (mặc định 30/60s): mọi POST, key = identity + path + `__CALLBACKID` (hoặc `__EVENTTARGET`, hoặc
    JSON `RequestAction` khi path `~/`). Bỏ qua `~/signalr/*` và upload chunk DevExpress (`?DXUploadingCallback=`).
    Màn hình mới tự được bảo vệ.
  - Auth `RateLimiter.Auth.*` (mặc định 600/60s, chốt chặn theo IP khi attacker xoay vòng session hợp lệ; ban đầu 30/60s
    nhưng chặn nhầm văn phòng NAT 1.000 nhân viên login): POST vào danh sách endpoint xác thực cố định (`~/login.aspx`, `~/admin/login.aspx`,
    `~/forgotpassword.aspx`, `~/authenticate.aspx`, `~/auth/token`, `~/user/sendemailotp`, `~/user/validateemailotpmfa`, RequestAction GetToken/GetAppToken),
    đếm theo IP và BỎ QUA token (attacker gửi Token giả xoay vòng để né).
  - GetToken/GetAppToken (body top-level `UserName`, deserialize thẳng vào command `GetToken`/`GetAppToken`): tầng Action đếm theo
    IP + UserName (Trim, lowercase) để nhiều điện thoại chung Wi-Fi không chặn nhau (token hết hạn theo `ApiTokenExpireInMinutes`,
    mặc định 30 phút → 10.000 user ≈ 330 GetToken/phút). Spraying nhiều tài khoản bị chặn bởi Auth 600/phút/IP.
    Chỉ đọc tiếp tìm UserName khi RequestAction là lệnh đăng nhập (body lớn ở request thường vẫn dừng sớm).
    Route `api/commands/{command}` là DynamicCommandWebApiDelegatingHandler, không chạy GetToken.
- Không giải mã token trong module: `DataSecurityWrapper.DecryptData` dẫn xuất khóa mỗi lần (nặng) và nằm ở BusinessLayer.
- AppSettings vẫn chỉ 2 key (15/1); các key Action/Auth/MaxTrackedKeys/TrustedProxies dùng default, thêm khi cần chỉnh.
- Bị chặn: 429 + Retry-After + `TrySkipIisCustomErrors`, body JSON `messageReturnType: 2`, `contentResult`, `message`, `isSuccess:false`.

## Kiểm chứng (Verification)
- MSBuild Cadena.Library, Cadena.WebAPI, Cadena.WebApp: thành công (2026-10-29).
- Harness console (không có test project), HttpContextBase giả, cấu hình thật 15/1: 28/28 pass - engine (burst, retry-after, refill,
  tắt, bảng đầy fail-open, dọn key, 5.000 request song song đúng 1.000), Add Employee x50 cùng user → ~31 qua (token hồi trong lúc gửi),
  user khác/control khác không ảnh hưởng, Login/Admin/Forgot/OTP xoay IP/GetToken với Token giả xoay vòng/auth/token/SendEmailOtp → ~31,
  200 user mobile chung 1 IP NAT → đều qua, upload chunk x60 → qua, file tĩnh không đếm, body JSON đọc lại được, JSON lỗi không ném.
- Hiệu năng: ~1,2 µs/request GET, ~0,2 µs/request POST song song 12 core, body JSON nhỏ ~7-12 µs, body 12KB có RequestAction ở cuối ~150 µs.
  25.000 key ~9 MB managed memory.
- Chưa test trên IIS và màn hình thật; chưa test web farm.

## Hướng đi sai (Dead ends)
- Port nguyên RateLimiter của master: key theo URL, đang bị comment, không chặn được case pentest (xem Root cause).
- Chỉ giới hạn chung theo IP (giống master): pentest gửi chậm 1 req/s vẫn tạo đủ 50 nhân viên; văn phòng NAT bị chặn nhầm.
- Bảng rule hard-code theo màn hình (bản 1: `RateLimitRules`/`RateLimitPolicies`/`RateLimitRule`/`RateLimitKeys`...): chặn đúng nhưng
  mỗi màn hình phải sửa Cadena.Library và build lại - đã bỏ.
- Tin header Token làm identity cho endpoint đăng nhập: Token giả xoay vòng tạo key mới mỗi request.
- Đếm theo IP cho mọi request API: user mobile chung IP NAT văn phòng chạm ngưỡng.
- Login đếm theo IP với ngưỡng thấp (30/60s): 1.000 nhân viên chung IP NAT login buổi sáng bị 429. Đếm theo SessionID + IP ngưỡng cao.
- `AuthenticateUser()` trong Global.asax (AcquireRequestState) redirect request chưa login TRƯỚC khi module chạy (PostAcquireRequestState),
  nên các request đó không bị đếm (chưa sửa, cần quyết định chuyển module sang AcquireRequestState).
- Đọc IP từ X-Forwarded-For không điều kiện; fail-closed khi bảng đầy (attacker làm đầy bảng sẽ khóa mọi người).

## Lần sau (Next time)
- Màn hình/API nghiệp vụ mới: không cần làm gì. Endpoint đăng nhập/OTP/reset mới: thêm path vào `AuthPaths` (hoặc `AuthRequestActions`).
- User thao tác nhanh bị 429 trên grid (paging/filter cùng control): tăng `RateLimiter.Action.NumItems`.
  Văn phòng NAT bị 429 ở login: tăng `RateLimiter.Auth.NumItems`.
- Loại request lặp hợp lệ mới (polling, upload kiểu khác): thêm vào `ActionExcludedPathPrefixes`/`ActionExcludedQueryKeys`.
- Sau load balancer/reverse proxy: khai báo IP proxy trong `RateLimiter.TrustedProxies`.
- Nhiều server: bộ đếm trong RAM từng server (session InProc nên sticky, theo user vẫn đúng; theo IP nhân theo số server); cần Redis/WAF nếu muốn chính xác.
- Harness 42/42 (2026-10-29, bản có Anonymous/HTML/GetToken theo UserName). Lưu ý khi viết harness: `Thread.Sleep(5)` trên Windows
  ngủ ~15ms nên token hồi nhiều hơn tính toán; so sánh với 600 + 10 × thời gian đo bằng Stopwatch.
- Còn mở: GetToken ghi log token plaintext chứa username/password (GetTokenCommandHandler); callback "Login" của Login.aspx gọi
  this.Login không kiểm tra OTP; chưa rà hết API anonymous ngoài danh sách Auth.
- Còn mở: forgot password chỉ giới hạn theo IP (chưa theo username → có thể spam/reset mật khẩu nạn nhân 30 lần/phút/IP);
  bypass MFA qua callback `Login`, secret OTP suy ra từ username, `cdn.admin` hard-code, khóa AES hard-code trong DataSecurityWrapper,
  FailedPasswordAttemptCount không nguyên tử.
- Review 2026-10-29 (chưa sửa): identity `t:` lấy từ header Token/AppToken chưa xác thực → POST với Token giả xoay vòng tạo key mới
  không giới hạn, né Anonymous theo IP. Khi bảng đầy (MaxTrackedKeys) limiter fail-open, và mỗi request key mới chạy `RemoveExpired`
  quét toàn bảng (~13 ms/request với 100k key, đo bằng harness). Hướng sửa: throttle RemoveExpired khi đầy (tối đa 1 lần/giây) và
  đếm thêm request có token theo IP (ngưỡng cao, config được).
- Default `RateLimiter.Anonymous.NumItems` đã đổi thành 300; test harness "Anonymous 200 per second" cần cập nhật theo.
- Test thật trên IIS Express (2026-10-29, site Cadena.WebApp cổng 60879): module tự đăng ký và chạy OK; POST callback
  `cbpLoginProcessing` vào Login.aspx bị chặn từ request ~33 (khớp Action 30/phút); file tĩnh (DXR.axd) 60 lần đều 200;
  status 429 + header Retry-After tới được client.
- CRITICAL phát hiện khi test IIS: body 429 bị IIS NUỐT. Web.config (cả WebApp lẫn WebAPI) có
  `<httpErrors errorMode="Custom" existingResponse="Replace">`. Với `Replace`, IIS luôn thay body response lỗi và BỎ QUA
  `TrySkipIisCustomErrors=true`. Kết quả: 429 trả về "The custom error module does not recognize this error" (text/html, 54 byte)
  thay vì JSON `{messageReturnType:2,...}` cho API/AJAX, và không hiện được trang W2 "system busy" cho trình duyệt.
  Harness không bắt được vì đây là hành vi pipeline IIS.
  → Hướng sửa (cần team duyệt, KHÔNG tự sửa): đổi `existingResponse="Replace"` thành `"Auto"` ở cả 2 Web.config; với Auto,
  response có body + TrySkipIisCustomErrors sẽ đi qua, còn các lỗi 400/401/403/404/405/500 (body rỗng) vẫn hiện Error.html như cũ.
  Phải regression lại các trang lỗi đó. App mobile hiện parse theo body JSON nên status 429 không là đủ.
- Xác nhận W3 trên IIS: GET trang nghiệp vụ (Default.aspx) khi chưa đăng nhập bị Global.asax redirect 302 sang Authenticate.aspx
  ở AcquireRequestState, TRƯỚC module (PostAcquireRequestState) → request đó không được đếm. Ảnh hưởng thấp (chỉ là redirect).
- Giới hạn Global 15/giây rất khó chạm bằng điều hướng bình thường (40 curl "song song" vẫn 200 vì process curl trên Windows
  khởi động chậm, trải >1s) → trang W2 gần như chỉ xuất hiện khi thực sự flood; UX người dùng thật không bị phiền.
