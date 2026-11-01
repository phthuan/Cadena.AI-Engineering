# Knowledge Base

Các bài học (lesson learned) rút ra từ những task đã hoàn thành, được chia sẻ cho cả team qua Git.
Claude tìm trong thư mục này trước khi điều tra một task. Khi task phát hiện được điều đáng ghi, Claude đề xuất
bài học và chỉ ghi khi người dùng đồng ý, để không ai phải tự tìm lại cùng một root cause lần thứ hai.

Quy trình đầy đủ (khi nào tra cứu, khi nào ghi, ghi vào đâu) nằm trong `rules/common/knowledge-base.md`.

## Cấu trúc

```
knowledge/
├── _template.md
├── common/                         # bài học chung cho mọi project
└── <project-key>/                  # mỗi repository sản phẩm một thư mục
    ├── _shared/                    # bài học chung cho mọi branch của project
    │   └── YYYY-MM-DD-short-slug.md
    └── <branch-key>/               # bài học riêng của một branch
        └── YYYY-MM-DD-short-slug.md
```

- `common/`: bài học chung cho mọi project.
- `<project-key>/`: mỗi repository sản phẩm một thư mục.
- `<project-key>/_shared/`: bài học chung cho mọi branch của project.
- `<project-key>/<branch-key>/`: bài học riêng của một branch. Đây là nơi Claude ghi mặc định.

`<project-key>` là tên thư mục gốc của Git repository sản phẩm, viết thường
(ví dụ `std5`, `cadena.documentsign.coreservice`).

`<branch-key>` là tên branch đang checkout, viết thường, thay `/` và `\` bằng `-`
(ví dụ `has260102_5.3.145.0`, `master`).

Khi làm việc trên một branch, Claude chỉ đọc thư mục của branch đó, `<project-key>/_shared/`
và `common/`. Bài học chỉ được ghi vào `<project-key>/_shared/` khi người dùng yêu cầu ghi cho tất cả branch.

## Quy tắc

- Mỗi bài học một file, để nhiều người có thể thêm bài học mà không bị merge conflict.
- Không bao giờ lưu secret, connection string, token hoặc dữ liệu khách hàng.
- Review từng bài học trước khi commit; commit và push để team nhận được khi pull.
- Giữ nguyên các key frontmatter và giá trị máy đọc (`branch`, `type`, `status`, `confidence`, `keywords`, `files`, `date`) bằng tiếng Anh/nguyên văn;
  nội dung giải thích viết bằng tiếng Việt.
