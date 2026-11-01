---
name: record-lesson
description: Ghi lại bài học (record lesson learned) từ task vừa hoàn thành vào knowledge base dùng chung, gồm root cause, cách sửa và các hướng đi sai (dead ends), để team không phải điều tra lại. Record a lesson learned from the task just completed into the shared knowledge base, including root cause, fix and dead ends, so the team does not repeat the investigation.
---

# Record Lesson

Người dùng gõ lệnh này nghĩa là đã yêu cầu ghi: ghi ngay, không đề xuất và hỏi lại như mục 2.1.

1. Đọc rules/common/knowledge-base.md trong repository Cadena.AI-Engineering
   (đường dẫn được ghi trong file global CLAUDE.md của người dùng) và tuân thủ mục 2.
2. Xem lại cuộc hội thoại này và trích ra: triệu chứng và nguyên văn thông báo lỗi, root cause và vị trí,
   cách sửa, cách đã kiểm chứng, và mọi giả thuyết đã được điều tra rồi bị loại bỏ.
   Chỉ giữ những gì Claude đã học được, không chép lại quá trình làm task.
3. Đối chiếu với mục 2.2 đến 2.4. Không đạt thì không ghi, và nói với người dùng lý do
   hoặc còn thiếu bằng chứng gì để xác minh.
4. Chống trùng lặp theo mục 2.5.
5. Ghi theo mục 2.6 và 2.7.
6. Cho người dùng xem đường dẫn file và bản tóm tắt ngắn, đồng thời nhắc họ review, commit và push.
