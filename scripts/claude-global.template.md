# Quy tắc kỹ thuật dùng chung của Cadena (Shared Cadena Engineering Rules)

Với mọi project mã nguồn trên máy này, PHẢI tuân thủ các quy tắc dùng chung sau.

## Quy tắc chung (Common rules)
Đọc:
{{REPO}}\rules\common\CLAUDE.md

Đọc thêm:
{{REPO}}\rules\common\common-rules.md

## Quy tắc theo loại công việc (Task-specific rules)
- Performance (hiệu năng): xem các rule áp dụng được trong {{REPO}}\rules\performance\
- Bug fixing (sửa lỗi): xem các rule áp dụng được trong {{REPO}}\rules\bug-fixing\
- Feature development (phát triển tính năng): xem các rule áp dụng được trong {{REPO}}\rules\feature-development\
- Security (bảo mật): xem các playbook áp dụng được trong {{REPO}}\rules\security\

## Knowledge base (cơ sở tri thức)
Knowledge base: {{REPO}}\knowledge\
Quy trình: {{REPO}}\rules\common\knowledge-base.md
Với mọi tác vụ không tầm thường (non-trivial), PHẢI tuân thủ quy trình này. Chỉ duy nhất quy trình này quyết định khi nào tra cứu và khi nào ghi lại bài học (lesson).

## Skills
Dùng Skill dùng chung phù hợp với tác vụ:
{{SKILLS}}

Đồng thời PHẢI tuân thủ hướng dẫn riêng của project đích.
Không bao giờ tuyên bố test đã pass nếu test chưa thực sự được chạy.
KHÔNG comment code đã sửa: không thêm comment giải thích lý do sửa/thay đổi, không giữ code cũ dưới dạng comment, không thêm comment mới trừ khi người dùng yêu cầu. Lý do sửa chỉ ghi trong phản hồi hoặc commit message. Rà lại diff và xóa comment vi phạm trước khi báo hoàn thành.
