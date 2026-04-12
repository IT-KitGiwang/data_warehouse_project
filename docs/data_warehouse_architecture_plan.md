# Kế Hoạch Triển Khai Hệ Thống Data Warehouse Chuẩn Production

## 1. Đánh Giá Hiện Trạng Nguồn Dữ Liệu (Source Data Assessment)
Bộ dữ liệu gồm 2 hệ thống nguồn (CRM và ERP). Mặc dù có vẻ đơn giản, nhưng nó lại chứa **đầy đủ các "đặc sản" và vấn đề (pain points)** thực tế mà một Data Engineer sẽ gặp phải ở các doanh nghiệp lớn. Đây là một bộ dữ liệu hoàn hảo để thể hiện kỹ năng xây dựng Data Warehouse (DWH) chuyên nghiệp:

### Cốt lõi của các vấn đề (Data Quality Issues):
*   **Bất đồng bộ khóa chính (Inconsistent Business Keys):**
    *   CRM (`cst_key`): `AW00011000`
    *   ERP CUST (`CID`): `NASAW00011000` (Bị dính tiền tố `NAS`)
    *   ERP LOC (`CID`): `AW-00011000` (Bị dính ký tự đặc biệt `-`)
    *   *Kỹ thuật xử lý:* Chuẩn hóa chuỗi (String Manipulation: SUBSTRING, REPLACE), tạo Master Data Management (MDM).
*   **Dữ liệu rác và khoảng trắng (Dirty Data):**
    *   `cst_firstname` = ` Jon`, `cst_lastname` = `Yang ` (khoảng trắng dư thừa).
    *   *Kỹ thuật xử lý:* Data Cleansing, dùng hàm `TRIM()` triệt để.
*   **Thiếu đồng nhất định dạng (Inconsistent Master Data):**
    *   Giới tính ở CRM: `M`, `F`. Giới tính ở ERP: `Male`, `Female`.
    *   *Kỹ thuật xử lý:* Data Standardization (Dùng CASE WHEN / Lookup Table để đồng nhất về quy chuẩn, ví dụ: `Male`, `Female`, `N/A`).
*   **Định dạng ngày tháng hỗn loạn (Date Handling):**
    *   Ngày tháng sinh/tạo `1971-10-06` (String/Date).
    *   Ngày tháng giao dịch ở file Sale `20101229` (Integer Format/Smart Keys).
    *   *Kỹ thuật xử lý:* Type Casting, Date Parsing, kết nối với bảng Vô hướng (Dim_Date).
*   **Lịch sử thay đổi trạng thái (Historical Data):**
    *   Bảng `prd_info` có `prd_start_dt` và `prd_end_dt` -> Đây là dấu hiệu của việc giữ kịch bản dữ liệu thay đổi theo thời gian.
    *   *Kỹ thuật xử lý:* Slowly Changing Dimension (SCD) Type 2 để lưu trữ phiên bản của Product.

---

## 2. Kiến Trúc Tổng Thể (Modern DWH Architecture)
Dựa trên best practice, chúng ta sẽ áp dụng Mô hình **Medallion Architecture (Tầng Đồng - Bạc - Vàng)** trên CSDL (SQL Server/PostgreSQL/Snowflake tùy chọn), hoặc kết hợp **Hub and Spoke** (Kimball's Data Warehouse Bus Architecture).

### 🥉 Bronze Layer (Tầng Nguyên Bản - Raw / Staging)
*   **Mục tiêu:** Load dữ liệu nhanh nhất từ CSV vào Database.
*   **Tính chất:** KHÔNG thay đổi Data (As-is). Tất cả các cột string đổi thành `NVARCHAR`/`VARCHAR`.
*   **Kỹ thuật:** TRUNCATE and LOAD hoặc Bulk Insert / `COPY` command.
*   **Naming Convention:** `bronze.crm_cust_info`, `bronze.erp_cust_az12`, v.v.

### 🥈 Silver Layer (Tầng Chuẩn Hóa - Cleansed / Integration)
*   **Mục tiêu:** Làm sạch, đồng nhất kiểu dữ liệu và định dạng lại các Business Key.
*   **Kỹ thuật:**
    *   Tạo ra các Stored Procedures hoặc View.
    *   Xóa khoảng trắng (`TRIM`), loại trừ NULL không hợp lệ (gán giá trị mặc định như `'-1'` hoặc `'Unknown'`).
    *   Cast kiểu dữ liệu chuẩn (`INT`, `DATE`, `DECIMAL`).
    *   Chuẩn hóa khóa: Dọn dẹp tiền tố `NAS` và hậu tố `-` ở các cột `CID` để làm chuẩn hóa tạo khóa ghép (Business Key).
*   **Naming Convention:** `silver.crm_cust_info`, `silver.erp_loc_a101`, v.v.

### 🥇 Gold Layer (Tầng Kinh Doanh - Business / Consumption - Star Schema)
*   **Mục tiêu:** Tạo mô hình *Star Schema* phục vụ báo cáo BI (PowerBI/Tableau) với tốc độ tức thì.
*   **Kỹ thuật:** Áp dụng Surrogate Keys (Khóa tự tăng INT/BIGINT). Xây dựng Dim và Fact Table.

---

## 3. Thiết Kế Mô Hình Star Schema (Gold Layer)

Chúng ta sẽ xây dựng các bảng Dimension và Fact như sau:

### 3.1. Bảng `dim_customers` (Tích hợp CRM + ERP)
Là bảng Dimension tích hợp góc nhìn 360 độ của khách hàng (Từ cá nhân CRM và thông tin bổ sung ERP).
*   **Các trường cơ bản:** `customer_sk` (Surrogate Key), `customer_id` (Business Key nguyên bản `AW00011000`), `first_name`, `last_name`, `full_name`.
*   **Thuộc tính bổ sung:** `marital_status`, `gender` (Đã chuẩn hóa `Male`/`Female`), `birth_date`, `country` (Lấy từ `LOC_A101`), `create_date`.
*   Cách tạo: Dùng `LEFT JOIN` lấy `silver.crm_cust_info` làm gốc, JOIN với `silver.erp_cust_az12` và `silver.erp_loc_a101` qua `cst_key` đã được chuẩn hóa.

### 3.2. Bảng `dim_products` (Áp dụng SCD Type 2)
Quản lý vòng đời tồn tại thông tin của sản phẩm.
*   **Các trường cơ bản:** `product_sk` (Surrogate Key), `product_id` (BK), `product_name`, `product_cost`, `product_category`, `product_subcategory` (Lấy từ `PX_CAT_G1V2`).
*   **Trường SCD Type 2:** `start_date` (`prd_start_dt`), `end_date` (`prd_end_dt`), `is_current` (Boolean xác định row hiện tại). 

### 3.3. Bảng `dim_date` (Bảng vô hướng về Thời gian)
*   Do Fact có ngày dạng `20101229`, ta cần bảng chuẩn `dim_date` (chứa các ngày tính từ 2000 -> 2050).
*   **Các trường:** `date_key` (Int format `20101229`), `full_date`, `day`, `month`, `year`, `quarter`, `day_of_week`.

### 3.4. Các Bảng Fact (Đa dạng hóa kho dữ liệu)

Để xây dựng một DWH chuẩn chuyên nghiệp, chỉ có 1 bảng Fact Giao dịch là chưa đủ. Dựa trên dữ liệu, ta thiết kế 4 bảng Fact trải dài qua 3 loại hình phổ biến nhất (Transaction, Periodic Snapshot, Accumulating Snapshot):

#### A. `fact_sales_transactions` (Cốt lõi - Transaction Fact)
*   **Mục tiêu:** Ghi nhận từng dòng hàng xuất ra trong đơn hàng.
*   **Độ hạt (Granularity):** Mỗi dòng là một Line Item trong đơn hàng (Từ file `sales_details.csv`).
*   **Foreign Keys:** `customer_sk`, `product_sk`, `order_date_key`.
*   **Business Keys:** `order_number` (`sls_ord_num`).
*   **Measures (Chỉ số):** `quantity`, `price`, `sales_amount` (`sls_sales`).

#### B. `fact_order_fulfillment` (Theo dõi quy trình - Accumulating Snapshot Fact)
*   **Mục tiêu:** Theo dõi toàn bộ vòng đời của một Đơn hàng từ lúc Đặt, Quá trình Gói hàng, cho đến lúc Giao - Phục vụ mảng Vận hành (Operations / Supply Chain).
*   **Độ hạt:** Mỗi dòng là một Đơn Hàng tổng (Order Number), thường được gom nhóm từ các Transaction.
*   **Foreign Keys:** `customer_sk`, `order_date_key` (Ngày đặt), `ship_date_key` (Ngày giao), `due_date_key` (Ngày hạn chót).
*   **Measures (Chỉ số thời gian & KPIs):**
    *   `time_to_ship_days` (Thời gian từ lúc Order đến lúc Ship).
    *   `shipping_delay_days` (Nếu Ship Date > Due Date).
    *   `is_late_shipment_flag` (Cờ hiệu 0/1 đánh dấu đơn hàng bị trễ).
    *   `total_order_lines` (Tổng số món hàng trong đơn).

#### C. `fact_monthly_sales_snapshot` (Báo cáo định kỳ - Periodic Snapshot Fact)
*   **Mục tiêu:** Phục vụ các báo cáo Dashboard chạy siêu nhanh cho cấp C-Level, tính tổng kết theo từng tháng mà không cần quét lại hàng triệu dòng Transaction.
*   **Độ hạt:** Mỗi dòng là Tổng doanh thu của một Sản Phẩm (hoặc Khách hàng) trong một Tháng nhất định.
*   **Foreign Keys:** `product_sk`, `customer_sk`, `year_month_key` (Khóa tháng/năm, VD: 201012).
*   **Measures:** `monthly_total_revenue`, `monthly_total_quantity`, `order_count_in_month`.

#### D. `fact_customer_lifetime_metrics` (Bảng đo lường vòng đời Khách hàng)
*   **Mục tiêu:** Tính toán độ gắn kết và vòng đời của tệp Khách hàng, phục vụ bộ phận Marketing.
*   **Độ hạt:** Mỗi dòng là số liệu cộng dồn của 1 Khách hàng (Hiếm khi thay đổi, hoặc chỉ update hàng đêm).
*   **Foreign Keys:** `customer_sk`.
*   **Measures:** `first_purchase_date_key`, `last_purchase_date_key`, `lifetime_value` (Tổng tiền khách đã chi), `total_orders_placed` (Số đơn đã đặt).


## 4. Kế Hoạch Triển Khai Thực Tế (Execution Plan)

### Sprint 1: Setup Workspace & Bronze Layer (Ingestion)
1.  Khởi tạo kiến trúc Database & tạo 3 schema: `bronze`, `silver`, `gold`.
2.  Tạo các thư mục script tuân thủ quản lý mã nguồn `scripts/bronze`, `scripts/silver`, `scripts/gold`.
3.  Tạo DDL SQL cho các bảng `bronze` (Toàn bộ là NVarchar).
4.  Viết Stored Procedure `proc_load_bronze` đọc dữ liệu text file lưu vào bảng tương ứng. Xây dựng cơ chế bắt Try/Catch để log lỗi nạp.

### Sprint 2: Silver Layer & Data Cleaning (Transformation)
1.  Tạo View/Stored Procedure phục vụ transform data `proc_load_silver`.
2.  Clean data bằng các logic Transformation: `TRIM()`, `REPLACE(cid, 'NAS', '')`, `REPLACE(cid, '-', '')`.
3.  Xử lý NULLs và Datetype: `CAST(... AS INT)`, `CAST(... AS DATE)`.
4.  Test Data Quality kiểm toán tại tầng Silver (Reconcile & Data Profiling).

### Sprint 3: Gold Layer & Dimension Loading (SCD & Lookup)
1.  Sinh tự động (Gen) dữ liệu bảng thời gian `dim_date`.
2.  Xây dựng Stored Procedures nạp `dim_customers` xử lý Join 3 nguồn, kiểm soát Update-Insert (Upsert/Merge).
3.  Xây dựng quy trình chạy `dim_products` xử lý chuẩn SCD Type 2 (Cập nhật `end_date` cho dòng cũ, `INSERT` dòng mới).
4.  Load dữ liệu `fact_sales` (Cần xử lý rủi ro "Late Arriving Dimension" - Giao dịch đến nhưng chưa có Master Data Product/Customer, gán bằng mã Unknown `-1`).

### Sprint 4: Orchestration & Automation
1.  Thiết kế Master Stored Procedure gọi lần lượt (Bronze -> Silver -> Gold).
2.  Tích hợp cơ chế Ghi Log: Bảng cấu hình lưu Thời gian Tải, Số dòng ảnh hưởng, Trạng thái (Thành công/Thất bại).
3.  (Tùy chọn) Chuyển hóa toàn bộ quy trình lên Apache Airflow, dbt, hoặc ADF nếu triển khai hệ sinh thái mở rộng.
