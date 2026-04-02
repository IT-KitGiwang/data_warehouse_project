# 🎤 KỊCH BẢN THUYẾT TRÌNH: THIẾT KẾ DATA WAREHOUSE CHUẨN KIMBALL

> **Người trình bày:** Data Engineer  
> **Thời lượng dự kiến:** 10 - 15 phút  
> **Tài liệu chiếu (Slide):** Trình chiếu sơ đồ ERD (Mermaid) và Luồng Medallion.

---

## 🛑 PHẦN 1: MỞ ĐẦU & ĐẶT VẤN ĐỀ (2 phút)

**🎤 Lời nói:**
"Xin chào mọi người (hội đồng/thầy cô/anh chị). Hôm nay, em xin trình bày về dự án tóm tắt Thiết kế Kho dữ liệu (Data Warehouse) cho doanh nghiệp. 

Vấn đề mà doanh nghiệp đang gặp phải là Dữ liệu nằm rải rác ở hai hệ thống cốt lõi: 1 bên là **CRM** (quản lý giao dịch, chăm sóc khách hàng) và 1 bên là **ERP** (quản lý danh mục vùng miền, kho bãi). Hai hệ thống này không cùng quy chuẩn với nhau. Code mã khách hàng hay sản phẩm mỗi phòng ban làm một kiểu, rác chữ và các khoảng trắng thừa rất nhiều.

Tiêu chí dự án của em bắt buộc phải tạo ra một Cấu trúc Kho dữ liệu chuẩn mực để gom chung cái mớ hỗn độn này lại, phục vụ mục đích duy nhất: Xuất Dashboard cho Sếp xem cực nhanh và chính xác."

---

## 🛑 PHẦN 2: KIẾN TRÚC TỔNG QUAN (2 phút)
*(Chuyển slide hướng nhìn về Data Flow Medallion Architecture)*

**🎤 Lời nói:**
"Về thiết kế tổng thể, em áp dụng **Medallion Architecture (Tương tự cơ chế Bronze -> Silver -> Gold)**.

* Đầu tiên, dòng dữ liệu từ 6 file CSV khổng lồ sẽ được đưa thẳng vào tầng **Bronze** dưới dạng thô nhất.
* Tại tầng **Silver**, quá trình làm sạch Data Quality sẽ diễn ra. Bọn em phải gọt tỉa các khoản trắng, loại bỏ định dạng sai như tiền tố 'NAS' trong ERP hay dấu bị dư ở khách hàng CRM, sau đó đồng nhất sang một chuẩn format duy nhất.
* Và trái tim của dự án chính là tầng **Gold** - Chứa mô hình **Kimball Star Schema** (Lược đồ hình sao) - Phần này em xin đi chi tiết ngay sau đây."

---

## 🛑 PHẦN 3: GIẢI THÍCH SƠ ĐỒ LƯỢC ĐỒ SAO (STAR SCHEMA) VÀ QUAN HỆ KHÓA (5 phút)
*(Trình chiếu trực tiếp sơ đồ bản vẽ kỹ thuật ERD Mermaid)*

**🎤 Lời nói:**
"Mọi người đang nhìn thấy trên màn hình là Bản vẽ kỹ thuật ERD (Entity Relationship Diagram) chuẩn Lược đồ Sao. Ở trung tâm hệ mặt trời là **Bảng Sự Kiện (fact_sales)**, và bao quanh nó là các  **Bảng Chi Tiết (Dimensions)** - gồm: `dim_customers`, `dim_products` và `dim_date`.

Tất cả các đường nối mà mọi người thấy đều áp dụng triết lý thiết kế chung bắt buộc: **Mối quan hệ Một - Nhiều** (Hay còn gọi là biểu tượng Chân chim 3 râu trên bản vẽ `}o--||`). 

**Ý nghĩa của các râu ria này:**
* **Đầu 2 gạch (||) ở các bảng Dim:** Nghĩa là Đúng Một (Exactly One). Bất kỳ một giao dịch nào trong bảng Fact cũng BẮT BUỘC chỉ được sinh ra bởi ĐÚNG 1 Sản phẩm, ĐÚNG 1 Khách hàng, trong ĐÚNG 1 Ngày cụ thể.
* **Đầu Chân chim (}o) ở bảng Fact:** Nghĩa là Không hoặc Nhiều (Zero or Many). Một khách hàng (Dim) có thể tạo ra vô hạn Giao dịch (Fact), hoặc không mua gì cả (nhưng vẫn có tên trong kho).

**Về Cấu trúc Khóa - Nhịp đập của DWH:**
Em không sử dụng mã khách hàng của CRM hay ERP đem làm kết nối chính. Mà hệ thống tự động sinh ra cột Khóa Thay Thế mới tinh có đuôi `_sk` được gọi là **PK (Primary Key - Khóa chính)** đại diện tuyệt đối trong DWH. Và toàn bộ bảng Fact sẽ chứa các **FK (Khóa Ngoại)** để liên kết siêu tốc nối vào. 

Cách thiết kế này có 2 cái siêu lợi ích: Bất chấp các hệ thống nguồn bên ngoài sau này có thay hình đổi dạng (đổi thẻ căn cước khách hàng), thì Fact tụi em không bao giờ bị đứt gãy vì khoanh khóa độc lập bằng Surrogate Key rôi."

---

## 🛑 PHẦN 4: HIGHLIGHT 3 ĐIỂM SÁNG TRÔNG THIẾT KẾ (4 phút)
*(Chỉ trực tiếp vào thông số thuộc tính trên ERD)*

**🎤 Lời nói:**
"Tiếp theo, em xin phép làm nổi bật 3 quyết định thiết kế cốt lõi mà team đã thực hiện mang lại sự khác biệt lớn so với kiểu thiết kế csdl SQL CRUD thông thường:

1. **Thứ nhất, Thiết kế Role-playing Date (Bảng Thời Gian Sinh Học):**
   Mọi người nhìn bảng `dim_date`. Em chỉ tạo duy nhất 1 bộ lịch Date Calendar từ năm 2000 đến 2050. Bảng Fact đâm ngược 3 râu vào luôn bảng Date này cho 3 mục đích: *Ngày đặt hàng (Order_date)*, *Ngày giao hàng (Ship_date)* và *Ngày đáo hạn (Due_date)*. Tụi em bổ sung cả cột `is_weekend` trong này luôn để Sếp xem biểu đồ là biết hôm nào có sale vào ngày nghỉ.

2. **Thứ hai, Kỹ thuật SCD Type 2 ở Bảng Sản Phẩm:** 
   Trong bảng `dim_products`, hệ thống không bao giờ Ghi đè (Overwrite) khi Giá vốn của sản phẩm (product_cost) thay đổi. Mà bọn em thiết kế 2 cột: `start_date` và `end_date`. Có nghĩa là 1 sản phẩm có thể đẻ ra 10 bản clone theo các mốc thời gian để giữ lại Lịch sử Giá. Việc Fact móc bằng vòng lặp `PK product_sk` giải bài toán Bán 10 năm sau truy thu lịch sử doanh thu chuẩn xác đến từng xu.

3. **Thứ ba, Derived Measure tại Fact:** 
   Tại bảng Fact_Sales trung tâm. Tụi em nhúng thêm cột tính toán ảo `shipping_days` (Số ngày giao hàng). Đội BI không cần còng lưng viết lênh code ngầm `Ship_Date - Order_Date` nữa, chỉ việc ném file csv lên kéo cột ra biểu đồ luôn."

---

## 🛑 PHẦN 5: TỔNG KẾT (1 phút)

**🎤 Lời nói:**
"Như vậy, kiến trúc Model Kho Dữ Liệu Star Schema mà team xây dựng dựa hoàn toàn trên thực tế Dữ liệu. 
Nó không vi phạm nguyên tắc Snow-flake ảo (đã tích hợp Quốc gia vào lại chung cho với Customer), xử lý dứt điểm các Khoảng gãy của SCD Lịch sử và Đầy đủ vẹn toàn các chỉ số đo lường.

Sơ đồ ERD này nay đã ổn định 100% Core Logic để bước ngay vào quá trình Generate Script SQL chạy cho Server. 
Em xin kết thúc bài trình bày ạ, cảm ơn sự chú ý lắng nghe của hội đồng!"
