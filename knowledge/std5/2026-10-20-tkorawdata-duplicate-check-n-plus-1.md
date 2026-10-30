---
title: Clock upload kiểm tra trùng trong TIM_TKORawDatas bằng một query cho mỗi record (N+1, không có index, NHibernate auto-flush)
project: std5
type: performance
keywords: [TIM_TKORawDatas, TKORawData, AttendanceID, RecordTime, UploadClockDataCommandHandler, IX_TIM_TKORawDatas_AttendanceID_RecordTime, Query<TKORawData>().Any, auto flush, FlushMode.Auto, N+1]
files: [Cadena HRM 5.0/Cadena.BusinessLayer/TigerConnectApi/Handlers/UploadClockDataCommandHandler.cs, Cadena HRM 5.0/Cadena.SQLScripts/2.CreateTables/IX_TIM_TKORawDatas_AttendanceID_RecordTime.sql]
commit:
date: 2026-10-20
author: Thuan Pham Ngoc
status: active
---

## Triệu chứng (Symptom)
Phát hiện trong một lần review kiến trúc (chưa thấy trên production): một batch TigerConnectApi /api/Clock/Upload
chậm dần xấp xỉ theo bình phương kích thước batch và có thể timeout khi bảng TIM_TKORawDatas lớn.

## Nguyên nhân gốc (Root cause)
1. Handler chạy `_session.Query<TKORawData>().Any(x => x.AttendanceID == id && x.RecordTime == t)` một lần cho mỗi record.
2. TIM_TKORawDatas không có index trên (AttendanceID, RecordTime) trong Cadena.SQLScripts (chỉ có PK GuidComb),
   nên mỗi lần kiểm tra là một lần scan bảng raw punch.
3. Session dùng FlushMode.Auto. Mỗi `Save` được theo sau bởi một query trên cùng bảng, nên NHibernate
   auto-flush ở mỗi vòng lặp và dirty-check mọi entity đã có trong session: O(n^2).

## Cách sửa (Fix)
- Index mới KHÔNG unique IX_TIM_TKORawDatas_AttendanceID_RecordTime. (Bản đầu tiên đặt UNIQUE; đã revert ngày 2026-10-21 vì các luồng import / đồng bộ thiết bị cũng ghi vào TIM_TKORawDatas và sẽ lỗi duplicate-key. Script drop bản unique đã có và tạo lại dạng non-unique.)
- Handler: dedupe batch trong memory, tải các punch đã có một lần cho mỗi chunk 1000 AttendanceID, giới hạn trong
  khoảng RecordTime của batch, sau đó lưu toàn bộ dòng mới trong một transaction (một lần flush khi commit).
- So sánh key không phân biệt hoa thường và bỏ qua khoảng trắng cuối, để khớp với ngữ nghĩa `=` của SQL cũ
  (collation mặc định không phân biệt hoa thường; so sánh varchar bỏ qua khoảng trắng cuối).

## Kiểm chứng (Verification)
Đã build Cadena.TigerConnectApi + Cadena.BusinessLayer bằng MSBuild (thành công). Chưa chạy trên database;
test project đã bị người dùng xóa, nên không có automated test nào được chạy cho thay đổi này.

## Hướng đi sai (Dead ends)
Không có hướng nào được điều tra; nguyên nhân đã rõ khi đọc code và script tạo bảng.

## Lần sau (Next time)
Với mọi vòng lặp "kiểm tra tồn tại rồi insert" trên NHibernate, tìm query theo từng record và auto-flush
giữa Save và Query trên cùng bảng. Tải các key đã có theo lô (bulk), sau đó insert trong một transaction.
Index không unique, nên hai lần upload giống hệt nhau chạy đồng thời vẫn có thể cùng insert một punch (hành vi giống các luồng import khác). Không đổi sang UNIQUE khi chưa kiểm tra mọi nơi ghi vào TIM_TKORawDatas.

## Phát hiện khi review performance (2026-10-28, NGHI NGỜ, chưa đo)
- TIM_TKORawDatas.AttendanceID là varchar(50), nhưng TKORawDataMapping / DefaultStringPropertyConvention không khai báo AnsiString,
  nên LINQ gửi tham số nvarchar -> CONVERT_IMPLICIT trên cột. Với collation SQL_* có thể làm IX_TIM_TKORawDatas_AttendanceID_RecordTime
  thành index scan; với collation Windows vẫn seek nhưng tốn CPU hơn. Xác nhận bằng actual execution plan (tìm CONVERT_IMPLICIT / Index Scan).
- Query lấy khoảng RecordTime min..max chung cho cả chunk 1000 ID: một batch trộn punch cũ (máy offline) và punch mới sẽ đọc
  toàn bộ punch của mọi ID trong khoảng đó (over-fetch).
- ĐÃ SỬA 2026-10-28 (LoadExistingPunchKeys, chưa đo trên DB): raw SQL join với danh sách key chính xác `(VALUES (:a0,:t0),...)`, tham số AnsiString(50) + DateTime, chunk 1000 key.

## Kết quả đo (2026-10-28, dev DB OHM-01-HRM, SQL 2022, 941k dòng, collation Latin1_General_100_CI_AS)
Script: chạy từ máy dev, round trip ~0.75 ms; 500 AttendanceID / 1000 key (một nửa đã tồn tại), median 5 lần, plan đã cache.
- Query cũ (nvarchar IN + khoảng thời gian): 576 ms, trả 5.930 dòng; khi có punch cũ 30 ngày: 898 ms, 34.901 dòng.
- Query mới (VALUES join, varchar): 128 ms, 502 dòng, ở cả hai tình huống. Cả hai đều seek.
- Với collation Windows (_100_CI_AS) nvarchar vs varchar KHÔNG gây scan (SQL Server seek qua dynamic range);
  rủi ro scan chỉ còn với collation SQL_*. Kiểm tra collation trên DB khách hàng trước khi kết luận.
- Insert 1000 dòng (bảng tạm cùng cấu trúc): từng dòng 363 ms vs set-based INSERT..WHERE NOT EXISTS 400 dòng/câu 235 ms
  -> chỉ nhanh ~1.5 lần khi round trip thấp; KHÔNG đáng đổi sang raw SQL insert (khó bảo trì hơn). Chỉ xem lại nếu round trip API -> DB cao.

## Commit theo chunk + batch insert (2026-10-29, người dùng duyệt, chưa đo)
- Lý do: request mang 1-2 năm punch (hàng chục nghìn dòng) giữ một transaction dài, khóa dòng tới cuối, log lớn, lỗi ở cuối thì rollback cả lô.
- Handler nhận ISessionFactory, mở một IStatelessSession với SetBatchSize(1000). Mỗi chunk 1000 punch: BeginTransaction,
  check tồn tại cho key chưa biết, Insert dòng mới, Commit. HashSet key dùng chung qua các chunk để bỏ trùng trong cùng request.
  SwipeStatus lấy bằng Get và cache theo ID (stateless session không có Load).
- Hệ quả: lỗi giữa chừng thì các chunk trước đã lưu; gửi lại an toàn vì check trùng sẽ bỏ qua.
- Ghi chú: ngưỡng leo thang lên khóa bảng (5000 lock) tính theo từng câu lệnh; insert từng dòng không chạm ngưỡng,
  nhưng một câu INSERT..SELECT set-based lớn thì có. Nếu chuyển sang SqlBulkCopy / set-based thì vẫn phải chia chunk.
- Người dùng KHÔNG muốn thêm lock hint (UPDLOCK, HOLDLOCK) cho race 2 request đồng thời.
- Đã build Cadena.TigerConnectApi (MSBuild thành công). Chưa xác nhận NHibernate thực sự gom batch (nh.cfg mã hóa,
  cần driver SqlClient); kiểm tra bằng SQL Profiler / Extended Events: các INSERT phải đến theo nhóm trong một RPC.
