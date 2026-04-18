/*
=============================================================================
DDL SCRIPT - CREATE DATA WAREHOUSE STAR SCHEMA (GOLD LAYER)
=============================================================================
Methodology: Kimball Dimensional Modeling
Type: Star Schema (Galaxy Schema)
Scope: 3 Dimensions (Customers, Products, Date) + 4 Fact Tables + 1 View
=============================================================================
*/

-- ==========================================================================
-- 1. DIMENSION TABLES
-- ==========================================================================

-- 1.1 DIM_CUSTOMERS (SCD Type 1 & Type 2)
IF OBJECT_ID('gold.dim_customers', 'U') IS NOT NULL
    DROP TABLE gold.dim_customers;
GO
CREATE TABLE gold.dim_customers (
    customer_sk INT IDENTITY(1,1) PRIMARY KEY, -- Surrogate Key
    customer_id INT NOT NULL,                  -- Natural Key (CRM)
    customer_key NVARCHAR(20) NOT NULL,        -- Business Key
    first_name NVARCHAR(50),                   -- SCD Type 1
    last_name NVARCHAR(50),                    -- SCD Type 1
    full_name NVARCHAR(100),                   -- SCD Type 1
    marital_status NVARCHAR(20),               -- SCD Type 2
    gender NVARCHAR(10),                       -- SCD Type 1
    birth_date DATE,                           -- SCD Type 1
    country NVARCHAR(50),                      -- SCD Type 2
    customer_create_date DATE,                 -- Original Create Date
    
    -- SCD Type 2 Metadata
    scd_start_date DATE NOT NULL,
    scd_end_date DATE,                         -- NULL means current active record
    is_current NVARCHAR(1) DEFAULT 'Y',
    dw_load_timestamp DATETIME DEFAULT GETDATE()
);
GO

-- 1.1.1 GOLD VIEW FOR AGE_BAND (Runtime Calculation - Plan B)
IF OBJECT_ID('gold.vw_dim_customers_with_age', 'V') IS NOT NULL
    DROP VIEW gold.vw_dim_customers_with_age;
GO
CREATE VIEW gold.vw_dim_customers_with_age AS
SELECT 
    *,
    CASE 
        WHEN birth_date IS NULL THEN 'Unknown'
        WHEN DATEDIFF(YEAR, birth_date, GETDATE()) < 18  THEN 'Under 18'
        WHEN DATEDIFF(YEAR, birth_date, GETDATE()) <= 25 THEN '18-25'
        WHEN DATEDIFF(YEAR, birth_date, GETDATE()) <= 35 THEN '26-35'
        WHEN DATEDIFF(YEAR, birth_date, GETDATE()) <= 45 THEN '36-45'
        WHEN DATEDIFF(YEAR, birth_date, GETDATE()) <= 55 THEN '46-55'
        ELSE '56+' 
    END AS age_band
FROM gold.dim_customers;
GO

-- 1.2 DIM_PRODUCTS (SCD Type 1 & Type 2)
IF OBJECT_ID('gold.dim_products', 'U') IS NOT NULL
    DROP TABLE gold.dim_products;
GO
CREATE TABLE gold.dim_products (
    product_sk INT IDENTITY(1,1) PRIMARY KEY,  -- Surrogate Key
    product_id INT NOT NULL,                   -- Natural Key (CRM)
    product_key NVARCHAR(30) NOT NULL,         -- Business Key
    product_name NVARCHAR(100),                -- SCD Type 1
    product_line NVARCHAR(20),                 -- SCD Type 1 (Road/Mountain/...)
    product_cost DECIMAL(10,2),                -- SCD Type 2 (Historical Price)
    category NVARCHAR(50),                     -- SCD Type 1
    subcategory NVARCHAR(50),                  -- SCD Type 1
    maintenance_flag NVARCHAR(5),              -- SCD Type 1
    
    -- SCD Type 2 Metadata
    scd_start_date DATE NOT NULL,
    scd_end_date DATE,
    is_current NVARCHAR(1) DEFAULT 'Y',
    dw_load_timestamp DATETIME DEFAULT GETDATE()
);
GO

-- 1.3 DIM_DATE (Conformed Dimension)
IF OBJECT_ID('gold.dim_date', 'U') IS NOT NULL
    DROP TABLE gold.dim_date;
GO
CREATE TABLE gold.dim_date (
    date_key INT PRIMARY KEY,                  -- Smart Key (YYYYMMDD)
    full_date DATE NOT NULL,
    year INT NOT NULL,
    quarter INT NOT NULL,
    quarter_label NVARCHAR(5) NOT NULL,        -- 'Q1', 'Q2'...
    month INT NOT NULL,
    month_name NVARCHAR(15) NOT NULL,          -- 'January'...
    year_month NVARCHAR(7) NOT NULL,           -- '2011-01'
    day INT NOT NULL,
    day_of_week INT NOT NULL,                  -- 1-7
    day_name NVARCHAR(10) NOT NULL,            -- 'Monday'...
    is_weekend BIT NOT NULL,
    fiscal_year INT,
    fiscal_quarter INT
);
GO

-- ==========================================================================
-- 2. FACT TABLES
-- ==========================================================================

-- 2.1 FACT_SALES_TRANSACTIONS (Transaction Fact - Line Item Grain)
IF OBJECT_ID('gold.fact_sales_transactions', 'U') IS NOT NULL
    DROP TABLE gold.fact_sales_transactions;
GO
CREATE TABLE gold.fact_sales_transactions (
    sales_fact_sk INT IDENTITY(1,1) PRIMARY KEY,
    order_number NVARCHAR(20) NOT NULL,        -- Degenerate Dimension
    
    -- Foreign Keys to Dimensions
    customer_sk INT NOT NULL,                  -- -> dim_customers
    product_sk INT NOT NULL,                   -- -> dim_products
    order_date_key INT NOT NULL,               -- -> dim_date
    ship_date_key INT,                         -- -> dim_date
    due_date_key INT,                          -- -> dim_date
    
    -- Measures
    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    unit_cost DECIMAL(10,2),                   -- Retrieved from dim_products at order time
    
    -- Derived Measures (Additive)
    sales_amount DECIMAL(12,2) NOT NULL,       -- quantity * unit_price
    cost_amount DECIMAL(12,2),                 -- quantity * unit_cost
    profit_amount DECIMAL(12,2),               -- sales_amount - cost_amount
    
    dw_load_timestamp DATETIME DEFAULT GETDATE(),
    
    CONSTRAINT FK_FactSales_Customer FOREIGN KEY (customer_sk) REFERENCES gold.dim_customers(customer_sk),
    CONSTRAINT FK_FactSales_Product FOREIGN KEY (product_sk) REFERENCES gold.dim_products(product_sk),
    CONSTRAINT FK_FactSales_OrderDate FOREIGN KEY (order_date_key) REFERENCES gold.dim_date(date_key)
);
GO

-- 2.2 FACT_ORDER_FULFILLMENT (Accumulating Snapshot Fact - Order Grain)
IF OBJECT_ID('gold.fact_order_fulfillment', 'U') IS NOT NULL
    DROP TABLE gold.fact_order_fulfillment;
GO
CREATE TABLE gold.fact_order_fulfillment (
    order_number NVARCHAR(20) PRIMARY KEY,     -- Header level
    customer_sk INT NOT NULL,
    
    -- Milestones
    order_date_key INT NOT NULL,
    ship_date_key INT,
    due_date_key INT,
    
    -- KPIs / Derived Measures
    days_to_ship INT,                          -- ship - order
    days_shipping_delay INT,                   -- ship - due (positive = late)
    is_late_shipment BIT,                      -- 1 if late
    
    -- Aggregated Measures from lines
    total_line_items INT NOT NULL,
    total_quantity INT NOT NULL,
    total_order_amount DECIMAL(12,2) NOT NULL,
    
    dw_load_timestamp DATETIME DEFAULT GETDATE(),
    
    CONSTRAINT FK_FactFulfill_Customer FOREIGN KEY (customer_sk) REFERENCES gold.dim_customers(customer_sk)
);
GO

-- 2.3 FACT_MONTHLY_SALES_SNAPSHOT (Periodic Snapshot Fact)
IF OBJECT_ID('gold.fact_monthly_sales_snapshot', 'U') IS NOT NULL
    DROP TABLE gold.fact_monthly_sales_snapshot;
GO
CREATE TABLE gold.fact_monthly_sales_snapshot (
    snapshot_month_key INT NOT NULL,           -- Last day of month (from dim_date)
    product_sk INT NOT NULL,
    customer_sk INT NOT NULL,
    
    -- Monthly aggregates
    monthly_revenue DECIMAL(12,2) NOT NULL DEFAULT 0,
    monthly_quantity INT NOT NULL DEFAULT 0,
    monthly_order_count INT NOT NULL DEFAULT 0,
    
    -- Derived measure
    monthly_avg_order_value DECIMAL(10,2),     -- revenue / order_count
    
    PRIMARY KEY (snapshot_month_key, product_sk, customer_sk),
    CONSTRAINT FK_FactSnapshot_Month FOREIGN KEY (snapshot_month_key) REFERENCES gold.dim_date(date_key),
    CONSTRAINT FK_FactSnapshot_Product FOREIGN KEY (product_sk) REFERENCES gold.dim_products(product_sk),
    CONSTRAINT FK_FactSnapshot_Customer FOREIGN KEY (customer_sk) REFERENCES gold.dim_customers(customer_sk)
);
GO

-- 2.4 FACT_CUSTOMER_LIFETIME (Factless/Aggregate Fact)
IF OBJECT_ID('gold.fact_customer_lifetime', 'U') IS NOT NULL
    DROP TABLE gold.fact_customer_lifetime;
GO
CREATE TABLE gold.fact_customer_lifetime (
    customer_sk INT PRIMARY KEY,               -- One row per customer version
    
    -- Life cycle milestones
    first_order_date_key INT,
    last_order_date_key INT,
    
    -- Metrics
    customer_lifetime_days INT,                -- last_order_date - first_order_date
    total_orders INT DEFAULT 0,
    total_products_bought INT DEFAULT 0,
    lifetime_revenue DECIMAL(12,2) DEFAULT 0,
    avg_order_value DECIMAL(10,2),
    
    -- Analytical attributes
    customer_segment NVARCHAR(20),             -- E.g. 'VIP', 'Regular', 'Churned' based on logic
    recency_days INT,                          -- Days since last_order_date
    
    last_calculated_at DATETIME DEFAULT GETDATE(),
    
    CONSTRAINT FK_FactLifetime_Customer FOREIGN KEY (customer_sk) REFERENCES gold.dim_customers(customer_sk)
);
GO
