---
title: Form Employee Profile hiển thị UI chậm ở lần mở đầu tiên — toàn bộ cây tab chạy phía server, query trong OnInit ở mọi DevExpress callback, kiểm tra full name N+1
project: std5
type: performance
keywords: [EmployeeProfileView, EmployeeProfileDetailView, GetSelectedEmployees, GetEmployeeFullNameByEmployeeID, GetEmployeeFullNamesByEmployeeIDsQuery, GetEmployeePrefixesByCompanyQuery, GetLiteCountries, LoadLiteCountry, CountryByUserPermissions, DefaultBankID, ClientVisible, EnableCallBacks, ASPxPageControl, OnInit, IsPostBack, N+1, form load slow, first load slow]
files: [Cadena HRM 5.0/Modules/Cadena.Modules.Staffing/Views/EmployeeProfileView.ascx.cs, Cadena HRM 5.0/Modules/Cadena.Modules.Staffing/Views/EmployeeProfileGeneralView.ascx.cs, Cadena HRM 5.0/Modules/Cadena.Modules.Staffing/Views/EmployeeProfileEmploymentView.ascx.cs, Cadena HRM 5.0/Modules/Cadena.Modules.Staffing/Views/EmployeeProfileDocumentView.ascx.cs, Cadena HRM 5.0/Modules/Cadena.Modules.Staffing/Messages/GetEmployeeFullNamesByEmployeeIDsQuery.cs, Cadena HRM 5.0/Modules/Cadena.Modules.Staffing/Handlers/GetEmployeeFullNamesByEmployeeIDsQueryHandler.cs]
commit: (chưa commit)
date: 2026-10-26
author: Thuan Pham Ngoc (with Claude Code)
status: active
---

## Triệu chứng (Symptom)
Staffing > Employee Profile (EmployeeProfileView.ascx, FormID 8601E363-E701-42B1-9A5E-A3F700A5BACD) mất nhiều thời gian
trước khi UI xuất hiện ở lần mở đầu tiên, và việc chọn một nhân viên chậm. Càng nhiều nhân viên được chọn càng tệ.

## Nguyên nhân gốc (Root cause)
Tìm ra bằng cách đọc code (chưa profile):
- Một trang = 16 user control, ~19,700 dòng .ascx, ~1,460 server control, 137 binding DataSourceID.
  Các tab chỉ được ẩn bằng `ClientVisible` / `<% if (...) %>` — cách đó ẩn phần render, nhưng mọi control con vẫn
  chạy Init/Load ở phía server (bao gồm cả các tab statutory của toàn bộ 8 quốc gia). `ASPxPageControl EnableCallBacks="true"`
  chỉ bỏ qua việc render các tab không active, không bỏ qua vòng đời (lifecycle) của chúng.
- Các DB query trong `OnInit` chạy ở MỌI request, bao gồm mọi DevExpress callback:
  GeneralView `GetEmployeePrefixesByCompanyQuery`, EmploymentView `LoadLiteCountry()` (GetLiteCountries).
  DocumentView query GetLiteCountries lần nữa ở lần tải đầu vào CÙNG session key (`fid` + CountryByUserPermissions).
- `EmployeeProfileView.GetSelectedEmployees` gọi `GetEmployeeFullNameByEmployeeID` một lần cho mỗi nhân viên được chọn
  (mỗi lần tải một entity Employee đầy đủ) và chạy ở mọi grid callback (endless paging, filter row, refresh).
- Chọn một nhân viên kích hoạt 4–5 callback tuần tự (cbSelectEmployee → cbbEmployeeCompany →
  cbpEmployeeProfileGeneralView "CompanyChange" → cbpnEmployeeProfile "CompanyChange" → refresh tab statutory),
  mỗi callback dựng lại toàn bộ cây control. CHƯA được sửa.

## Cách sửa (Fix)
- `GetEmployeeFullNamesByEmployeeIDsQuery` mới (ID → FullName, projection 2 cột, chia chunk 1000 ID vì
  giới hạn 2100 parameter). `SyncFullNamesWithDatabase` giữ ngữ nghĩa cũ (nhân viên không tồn tại => tên rỗng, chỉ
  session CurrentSelectionEmployees được cập nhật) nhưng đọc/ghi session chỉ một lần.
- GeneralView: setting prefix chỉ được query khi `!IsPostBack` (hoặc khi thiếu cache), cache trong session theo tenant + company.
- EmploymentView: khi postback và đã có danh sách quốc gia trong cache, bỏ qua query nhưng vẫn tính lại DefaultBankID.
  Đặt `HttpContext.Items[LiteCountriesLoadedInRequestKey]` sau khi tải.
- DocumentView ở lần tải đầu: dùng lại danh sách khi marker đó đã được đặt, vẫn tính lại DefaultBankID bằng công thức riêng của nó.

## Kiểm chứng (Verification)
- `Cadena.Modules.Staffing.csproj` build bằng MSBuild 2022 (BuildProjectReferences=false): 0 lỗi.
- Không có automated test cho các view này; vẫn cần kiểm tra thủ công trên trình duyệt
  (mở form, chọn nhân viên, giá trị bank mặc định ở Employment, combo quốc gia ở Document, trạng thái enabled của Employee Local ID ở General).

## Hướng đi sai (Dead ends)
- Phân quyền query theo `[Operation]`: đã kiểm tra AuthorizationQueryHandlerDecorator — phần kiểm tra bị comment out, nên một
  query message mới không cần permission/Operation GUID.
- KHÔNG được đơn giản bỏ việc tính lại DefaultBankID khi bỏ qua GetLiteCountries: EmploymentView và DocumentView
  ghi cùng session key `fid_DefaultBankID` nhưng tính EmployeeSupportCountryID từ các session khác nhau
  (ProfileEmployeeSelected.SupportCountryID so với SessionNames.EmployeeSupportCountryID). Giữ nguyên mọi thao tác ghi như trước.
- Dùng `FormID` trong session key bên trong OnInit: nó là `Guid.Parse(Request.QueryString["fid"])` và ném exception khi không có fid.

## Lần sau (Next time)
Với một form WebForms/DevExpress chậm: đếm số control và DataSourceID trước, sau đó grep `OnInit`/`Page_Load` của mọi file con
.ascx.cs tìm `Mediator.Query` không có guard `IsPostBack`/`IsCallbackPanel`, rồi trace chuỗi `PerformCallback` phía client
trong các handler EndCallback. Các cải thiện lớn còn lại ở đây: `Visible=false`/LoadControl phía server cho các tab statutory
của quốc gia khác, và gộp các callback CompanyChange thành một.
