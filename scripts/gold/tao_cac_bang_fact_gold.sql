-- TẠO CÁC BẢNG FACT ĐA DẠNG CHO GOLD LAYER
-- MỤC ĐÍCH: Nâng cấp kho dữ liệu với 3 chuẩn Fact phổ biến nhất phục vụ báo cáo chuyên dụng.

-- ====================================================================================
-- 1. BẢNG FACT GIAO DỊCH (TRANSACTION FACT) - Thể hiện chi tiết từng line từng hóa đơn
-- ====================================================================================
IF OBJECT_ID('gold.fact_sales_transactions', 'U') IS NOT NULL
    DROP TABLE gold.fact_sales_transactions;
CREATE TABLE gold.fact_sales_transactions (
    fact_sk INT IDENTITY(1,1) PRIMARY KEY, -- Khóa chính tự sinh Surrogate Key
    order_number NVARCHAR(50) NOT NULL,    -- Business Key từ sls_ord_num
    customer_sk INT NOT NULL,              -- Liên kết tới Dim Khách hàng
    product_sk INT NOT NULL,               -- Liên kết tới Dim Sản phẩm (đã SCD Type 2)
    order_date_key INT NOT NULL,           -- Liên kết Dim Thời gian (Format YYYYMMDD)
    
    -- Measures
    quantity INT NOT NULL,                 -- Số lượng
    price DECIMAL(18,2) NOT NULL,          -- Đơn giá
    sales_amount DECIMAL(18,2) NOT NULL,   -- Tổng tiền (quantity * price)
    
    -- Metadata hệ thống
    created_at DATETIME DEFAULT GETDATE()
);

-- ====================================================================================
-- 2. BẢNG FACT TÍCH LŨY QUÁ TRÌNH (ACCUMULATING SNAPSHOT FACT) - Đo lường vòng đời đơn hàng
-- ====================================================================================
IF OBJECT_ID('gold.fact_order_fulfillment', 'U') IS NOT NULL
    DROP TABLE gold.fact_order_fulfillment;
CREATE TABLE gold.fact_order_fulfillment (
    order_number NVARCHAR(50) PRIMARY KEY, -- Một đơn hàng gom lại thành 1 dòng duy nhất
    customer_sk INT NOT NULL,              -- Người đặt
    
    -- Các mốc thời gian (Dates)
    order_date_key INT NOT NULL,
    ship_date_key INT,                     -- Có thể NULL nếu chưa ship
    due_date_key INT NOT NULL,             -- Hạn chót
    
    -- Chỉ số đo lường hiệu suất (KPI Measures)
    time_to_ship_days INT,                 -- DATEDIFF(day, order_date, ship_date)
    shipping_delay_days INT,               -- DATEDIFF(day, due_date, ship_date) (Âm là sớm, dương là trễ)
    is_late_shipment_flag BIT,             -- 1 nếu trễ, 0 nếu không
    total_order_lines INT,                 -- Số loại mặt hàng trong đơn
    total_order_amount DECIMAL(18,2),      -- Tổng giá trị đơn hàng
    
    updated_at DATETIME DEFAULT GETDATE()  -- Cập nhật mỗi lần trạng thái đơn hàng thay đổi
);

-- ====================================================================================
-- 3. BẢNG FACT TỔNG KẾT ĐỊNH KỲ (PERIODIC SNAPSHOT FACT) - Siêu tối ưu cho Dashboard
-- ====================================================================================
IF OBJECT_ID('gold.fact_monthly_sales_snapshot', 'U') IS NOT NULL
    DROP TABLE gold.fact_monthly_sales_snapshot;
CREATE TABLE gold.fact_monthly_sales_snapshot (
    year_month_key INT NOT NULL,           -- VD: 201012 (YYYYMM)
    product_sk INT NOT NULL,               -- Dòng sản phẩm
    customer_sk INT NOT NULL,              -- Tài khoản khách hàng
    
    -- Measures tổng kết tháng
    monthly_total_revenue DECIMAL(18,2) DEFAULT 0,
    monthly_total_quantity INT DEFAULT 0,
    order_count_in_month INT DEFAULT 0,
    
    PRIMARY KEY (year_month_key, product_sk, customer_sk)
);

-- ====================================================================================
-- 4. BẢNG FACT VÒNG ĐỜI KHÁCH HÀNG (FACTLESS / AGGREGATED FACT) - Phân tích Marketing LTV
-- ====================================================================================
IF OBJECT_ID('gold.fact_customer_lifetime_metrics', 'U') IS NOT NULL
    DROP TABLE gold.fact_customer_lifetime_metrics;
CREATE TABLE gold.fact_customer_lifetime_metrics (
    customer_sk INT PRIMARY KEY,
    
    first_purchase_date_key INT,           -- Lần đầu mua hàng
    last_purchase_date_key INT,            -- Lần cuối mua hàng
    
    lifetime_value DECIMAL(18,2) DEFAULT 0, -- Tổng tiền đã đốt vào hệ thống
    total_orders_placed INT DEFAULT 0,     -- Tổng số phát sinh đơn hàng
    
    -- Phân loại tier siêu khách hàng
    customer_segment NVARCHAR(50),         -- Ví dụ: VIP, Regular, Churn
    
    last_calculated_at DATETIME DEFAULT GETDATE()
);

-- PRINT 'Đã tạo thành công cấu trúc 4 Bảng Fact đa dạng tại tầng Gold!'
