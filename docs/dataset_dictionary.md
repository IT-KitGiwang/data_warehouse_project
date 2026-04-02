# 🗂️ TỪ ĐIỂN DỮ LIỆU (DATA DICTIONARY) - CRM & ERP DATASETS

Báo cáo chi tiết ý nghĩa cụ thể của từng Field (Cột) trong tất cả 6 file dữ liệu nguồn để anh dễ dàng nắm bắt bức tranh toàn cảnh Dữ liệu.

---
### KHỐI DỮ LIỆU CRM (QUẢN LÝ QUAN HỆ KHÁCH HÀNG)

---
**FILE: `source_crm/cust_info.csv`**
*(Chứa thông tin hồ sơ cơ bản của Khách hàng, được ghi nhận lúc khách tạo tài khoản mua hàng)*
- `cst_id` : Integer : Mã ID định danh tự sinh của khách hàng trong hệ thống CRM (Dùng chủ yếu trong các bảng nội bộ CRM).
- `cst_key` : String : Mã định danh nghiệp vụ (Business Key) chuẩn của Khách hàng (VD: AW00011000). Đây là khóa cốt lõi để đối soát.
- `cst_firstname` : String : Tên (First Name) của khách hàng. Lưu ý field này bị dính nhiều khoảng trắng rác cần phải TRIM.
- `cst_lastname` : String : Họ (Last Name) của khách hàng. Cũng bị dính nhiều khoảng trắng rác.
- `cst_marital_status` : String : Dấu hiệu tình trạng hôn nhân (M = Married / Đã kết hôn, S = Single / Độc thân).
- `cst_gndr` : String : Giới tính theo chuẩn CRM ghi nhận bằng 1 ký tự (M = Male / Nam, F = Female / Nữ).
- `cst_create_date` : Date : Chấm thời gian khách hàng chính thức tạo và thiết lập tài khoản trên nền tảng CRM.

---
**FILE: `source_crm/prd_info.csv`**
*(Chứa danh mục các sản phẩm hiện có đang được chào bán. Cho phép lưu lại nhiều dòng ứng với lịch sử thay đổi giá bán của một món hàng)*
- `prd_id` : Integer : Mã ID định danh tự sinh của sản phẩm trong CRM.
- `prd_key` : String : Mã nghiệp vụ chuẩn (Mã SKU) của sản phẩm (VD: CO-RF-FR-R92B-58).
- `prd_nm` : String : Tên hiển thị đầy đủ của sản phẩm dùng trên Web/App (VD: HL Road Frame - Black).
- `prd_cost` : Decimal : Giá nhập/Chi phí gốc của sản phẩm. Có rất nhiều record đang bị NULL (Cần cho tự động chuyển thành 0 khi Load).
- `prd_line` : String : Nhãn phân loại dòng sản phẩm (VD: R = Road, M = Mountain, S = Sport). Thường bị dư khoảng trắng phía sau cần TRIM.
- `prd_start_dt` : Date : Ngày bắt đầu áp dụng mức giá `prd_cost` hiện tại của sản phẩm. (Field quan trọng dùng để theo dõi SCD Type 2).
- `prd_end_dt` : Date : Ngày hết hạn của mức giá (Nếu bị NULL tức là mức giá này đang vẫn được xài cho thời điểm hiện tại).

---
**FILE: `source_crm/sales_details.csv`**
*(Bảng bự nhất lưu chi tiết từng sản phẩm được bán ra trong một đơn đặt hàng)*
- `sls_ord_num` : String : Mã số của Đơn Hóa Đơn Bán Hàng (Sales Order Number). Một mã Order có thể xuất hiện nhiều lần nếu khách mua nhiều món cùng lúc.
- `sls_prd_key` : String : Mã sản phẩm khách mua. (Lưu ý: Nó chỉ là một chuỗi cắt ngắn phía đuôi so với `prd_key` trong file Sản phẩm, cần luật Mapping cắt chuỗi).
- `sls_cust_id` : Integer : ID của khách hàng đặt đơn này (Móc nối trực tiếp với cột `cst_id` của file Khách hàng).
- `sls_order_dt` : Integer : Ngày đặt mua đơn hàng (Format bị chuyển kỳ cục thành Số Nguyên YYYYMMDD, VD: 20101229 tương ứng 29/12/2010).
- `sls_ship_dt` : Integer : Ngày đơn hàng rời kho/được đi giao (Giống Format Số Integer YYYYMMDD).
- `sls_due_dt` : Integer : Ngày hạn chót khách bắt buộc phải nhận được hàng (Giống Format Số Integer YYYYMMDD).
- `sls_sales` : Decimal : Tổng doanh thu/Số tiền thu được từ Line bán hàng này.
- `sls_quantity` : Integer : Số lượng hàng hóa khách đã mua trong Line này.
- `sls_price` : Decimal : Giá bán niêm yết của 1 Đơn vị sản phẩm đó (Đơn giá).

---
### KHỐI DỮ LIỆU ERP (QUẢN TRỊ NGUỒN LỰC DOANH NGHIỆP)

---
**FILE: `source_erp/CUST_AZ12.csv`**
*(Chứa thông tin ngày sinh và giới tính bị ẩn tản mạn của Khách hàng, do phòng ban khác chịu trách nhiệm lưu)*
- `CID` : String : Customer ID - Khóa nhận diện. Nhắm tới Business Key của khách (VẤN ĐỀ: Bị đính kèm tiền tố rác `NAS` đứng đầu, VD `NASAW...` cần xóa đi lúc Load).
- `BDATE` : Date : Ngày tháng năm sinh (Birth Date) của Khách. (VẤN ĐỀ: Khai đại rất nhiều ngày tương lai năm 2050 cần bị lọc vứt bỏ).
- `GEN` : String : Giới tính. (Rác rất nhiều form: Male, M, F, M có phím cách ẩn, rỗng hoàn toàn). Dùng cột này bù trừ đối chiếu chéo về form chuẩn với cột `cst_gndr` bên CRM.

---
**FILE: `source_erp/LOC_A101.csv`**
*(Bảng ánh xạ chứa mã Quốc Gia gắn liền với Khách Hàng)*
- `CID` : String : Customer ID - Khóa nhận diện số 2. (VẤN ĐỀ: Bị thọc gậy cài thêm ký tự gạch nối `-` vào giữa, VD: `AW-0...` cần xóa đi lúc Load để làm key map).
- `CNTRY` : String : Tên viết tắt của Quốc gia quản lý Khách hàng (Country, ví dụ DE = Đức).

---
**FILE: `source_erp/PX_CAT_G1V2.csv`**
*(Danh mục các Phân Khúc / Loại Nhóm (Category) dán lên trên các Sản Phẩm)*
- `ID` : String : Khóa khớp nối để tìm phân khúc. (Nhưng nó lại chỉ xài ký tự `_` thay vì `-` như nhóm Product Key, VD: dùng `CO_RF` thay vì mã gốc `CO-RF`). Tính chất khóa mệt mỏi.
- `CAT` : String : Phân khúc/Nhóm lớn nhất của Sản phẩm (Category) (VD: Components, Clothing).
- `SUBCAT` : String : Phân khúc nhánh chi tiết bên dưới (Sub Category) (VD: Road Frames, Socks).
- `MAINTENANCE` : String : Cờ hiệu (Yes/No) thông báo liệu Sản phẩm thuộc nhóm này thì có cần Chính sách Bảo trì định kỳ hay không.
