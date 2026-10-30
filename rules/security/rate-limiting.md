# Lack of Rate Limiting / Brute Force / Resource Exhaustion

## Nhận diện (Recognize)
- Tên trong báo cáo / scanner: Lack of Rate Limiting, No Rate Limit, Brute Force, Credential Stuffing, Password Spraying,
  OTP Brute Force, Email/SMS Bombing, Missing Account Lockout, Resource Exhaustion, Denial of Service (application layer).
- CWE / OWASP: CWE-307, CWE-770, CWE-799, CWE-400; OWASP A07 Identification and Authentication Failures, API4 Unrestricted Resource Consumption.
- Triệu chứng: tester gửi hàng trăm request liên tiếp tới login/OTP/reset/gửi email mà không bị chặn, không nhận 429.

## Nguồn dữ liệu (Sources)
- Form đăng nhập (WebForms callback), API lấy token (Mobile GetToken/GetAppToken), xác thực OTP/MFA, gửi lại OTP,
  quên mật khẩu, đổi mật khẩu, đăng ký, endpoint anonymous ghi dữ liệu, export/report nặng.
- Header `X-Forwarded-For` (attacker kiểm soát được nếu không đi qua proxy tin cậy).

## Sink và mẫu tìm kiếm (Sinks and search patterns)
- C# / .NET: `VerifyLogin`, `VerifyHash`, `ValidateUser`, `Validate(.*pin`, `VerifyOtp`, `SendEmailOtp`, `ForgotPassword`,
  `ResetPassword`, `ChangePassword`, `GetToken`, `[AllowAnonymous]`, controller không có xác thực, `List<...>.Add` trên static.
- Kiểm tra lớp bảo vệ có sẵn: `FailedPasswordAttemptCount`, `IsLockedOut`, `LimitedWrongLoginTimes`, Captcha, `RateLimiter`,
  `IsPermitted` (có bị comment không), `dynamicIpSecurity` trong Web.config, `maxInvalidPasswordAttempts` (Membership).
- WebForms: `cbp*_Callback` với `e.Parameter` (mỗi tham số callback là một entry point riêng).

## Cách sửa đúng (Correct fix)
- STD5: chặn tại MỘT chỗ bằng `Cadena.Library.Security.RateLimiting.RateLimitModule` (IHttpModule, tự đăng ký qua
  `PreApplicationStartMethod` khi AppSettings có `RateLimiter.NumItems`; không cần sửa Web.config).
  Endpoint mới = thêm 1 dòng vào `RateLimitRules.All` (path + callback/RequestAction + policy + nguồn key); policy và default nằm
  trong `RateLimitPolicies`, config `RateLimiter.<Policy>.NumItems` / `.TimePeriod`, giới hạn chung `RateLimiter.NumItems` / `.TimePeriod`.
- Giới hạn theo nhiều key: IP (chống spraying) + username/userID (chống brute force phân tán).
- Lấy IP qua `ClientIpResolver`: chỉ tin `X-Forwarded-For` từ `RateLimiter.TrustedProxies`.
- Trả 429 + `Retry-After` (+ `TrySkipIisCustomErrors`). Chặn TRƯỚC khi page/controller chạm DB hoặc gửi mail.
- Giới hạn chung theo IP phải tính cả văn phòng dùng chung IP (NAT) và số request song song khi tải một trang.
- Bộ nhớ có giới hạn, dọn key hết hạn; không quét toàn bảng mỗi request.
- OTP: giới hạn số lần sai trên mỗi user trong vòng đời OTP; gửi OTP có cooldown.
- Kết hợp với khóa tài khoản (account lockout) chứ không thay thế nó.

## Cách sửa sai (Wrong fixes)
- Key theo URL (giới hạn chung toàn hệ thống) hoặc chỉ theo session/cookie (attacker bỏ cookie là reset).
- Tin `X-Forwarded-For` không điều kiện.
- Ném Exception (trả 500) khi vượt ngưỡng; chặn bằng `Thread.Sleep` (tự DoS server).
- Chỉ validate/đếm ở client (JS).
- Chỉ dựa vào khóa tài khoản (không chặn spraying, và có thể bị dùng để khóa người khác).
- Fail-closed khi bảng theo dõi đầy (attacker làm đầy bảng = khóa mọi người).
- Rải hằng số giới hạn ở nhiều file với default khác nhau (xem lesson ratelimiter-appsetting-defaults-differ).

## Payload kiểm thử (Test payloads)
| Payload | Kết quả mong đợi sau khi sửa |
|---|---|
| 6 lần login sai cùng username trong 1 phút | Lần 6 bị từ chối với "Too many attempts..." |
| 21 lần login với 21 username khác nhau từ 1 IP trong 1 phút | Lần 21 bị từ chối |
| 6 lần nhập OTP sai trong 15 phút | Lần 6 bị từ chối |
| Bấm "Gửi lại OTP" 2 lần trong 60 giây | Lần 2 bị từ chối, không gửi email |
| 4 lần quên mật khẩu cùng username trong 1 giờ | Lần 4 bị từ chối, không đổi mật khẩu |
| Gửi kèm `X-Forwarded-For: <IP ngẫu nhiên>` khi không qua proxy | Không né được giới hạn |
| Login đúng sau vài lần sai | Thành công, bộ đếm theo user được reset |

## Kiểm chứng (Verification)
- Test RateLimiter với đồng hồ giả (sliding window, reset, bảng đầy, dọn key) và test song song (đúng N request được phép).
- Test integration endpoint trả 429 + Retry-After.
- Retest thủ công bằng Burp Intruder / script với số request vượt ngưỡng; gửi đội pentest danh sách endpoint và ngưỡng.
- Kiểm tra môi trường: proxy/load balancer (cấu hình TrustedProxies), web farm (bộ đếm trong RAM theo server).

## Bài học liên quan (Related lessons)
- knowledge/std5/2026-10-28-lack-of-rate-limiting-login-otp-forgot-password.md
- knowledge/std5/2026-10-20-ratelimiter-appsetting-defaults-differ.md
