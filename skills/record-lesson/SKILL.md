---
name: record-lesson
description: Ghi lại bài học (record lesson learned) từ tác vụ vừa hoàn thành vào knowledge base dùng chung, gồm root cause, cách sửa và các hướng đi sai (dead ends), để team không phải điều tra lại. Record a lesson learned from the task just completed into the shared knowledge base, including root cause, fix and dead ends, so the team does not repeat the investigation.
---

# Record Lesson

1. Đọc `rules/common/knowledge-base.md` trong repository Cadena.AI-Engineering
   (đường dẫn được ghi trong file global CLAUDE.md của người dùng) và tuân thủ mục 2.
2. Xem lại cuộc hội thoại này và trích ra: triệu chứng và nguyên văn thông báo lỗi, root cause và vị trí,
   cách sửa, cách đã kiểm chứng, và mọi giả thuyết đã được điều tra rồi bị loại bỏ.
3. Xác định project key từ repository sản phẩm hiện tại.
4. Tìm trong knowledge base bài học đã có với cùng root cause; nếu có thì cập nhật bài học đó.
5. Nếu không có, tạo bài học mới từ `knowledge/_template.md`.
6. Cho người dùng xem đường dẫn file và bản tóm tắt ngắn, đồng thời nhắc họ review, commit và push.
