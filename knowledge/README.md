# Knowledge Base

Các bài học (lesson learned) rút ra từ những tác vụ đã hoàn thành, được chia sẻ cho cả team qua Git.
Claude tìm trong thư mục này trước khi điều tra một tác vụ và ghi lại bài học mới
sau mỗi tác vụ không tầm thường (non-trivial), để không ai phải tự tìm lại cùng một root cause lần thứ hai.

Quy trình đầy đủ nằm trong `rules/common/knowledge-base.md`.

## Cấu trúc

```
knowledge/
├── _template.md
├── common/                 # lessons that apply to every project
└── <project-key>/          # one folder per product repository
    └── YYYY-MM-DD-short-slug.md
```

- `common/`: các bài học áp dụng cho mọi project.
- `<project-key>/`: mỗi repository sản phẩm một thư mục.

`<project-key>` là tên thư mục gốc của Git repository sản phẩm, viết thường
(ví dụ `cadena.documentsign.coreservice`).

## Quy tắc

- Mỗi bài học một file, để nhiều người có thể thêm bài học mà không bị merge conflict.
- Không bao giờ lưu secret, connection string, token hoặc dữ liệu khách hàng.
- Review từng bài học trước khi commit; commit và push để team nhận được khi pull.
- Giữ nguyên các key frontmatter và giá trị máy đọc (`type`, `status`, `keywords`, `files`, `date`) bằng tiếng Anh/nguyên văn;
  nội dung giải thích viết bằng tiếng Việt.
