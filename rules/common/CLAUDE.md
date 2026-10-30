# Cadena Engineering - Quy tắc chung (Common Rules)

Đọc common-rules.md trong thư mục này trước khi thực hiện thay đổi code đáng kể.

## Quy tắc theo loại công việc (Task-specific rules)
- Performance: xem các file liên quan trong rules/performance/.
- Bug fixing: xem các file liên quan trong rules/bug-fixing/.
- Feature development: xem các file liên quan trong rules/feature-development/.
- Security: xem các playbook liên quan trong rules/security/.

Tuân theo kiến trúc và quy ước (convention) hiện có của project đích.
Giữ nguyên hành vi nghiệp vụ (business behavior) trừ khi được yêu cầu thay đổi một cách rõ ràng.
Tránh refactor không liên quan.
Không bao giờ để lộ secret hoặc credential.
Không bao giờ tuyên bố test đã pass nếu test chưa thực sự được chạy.
Phân biệt rõ sự thật đã kiểm chứng với giả định.
