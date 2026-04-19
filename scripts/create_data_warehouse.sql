/*
===============================================================================
  DATA WAREHOUSE - CREATE TABLES & RELATIONSHIPS
  Project : SQL Data Warehouse - Kho dữ liệu cuối kỳ
  Model   : Snowflake Schema
  Tables  : 2 Fact Tables + 5 Dimension Tables
  Created : 2026-04-19
===============================================================================

  ARCHITECTURE:
  
  DIM_CATEGORY ←── DIM_PRODUCT ←── FACT_SALES ──→ DIM_CUSTOMER
                        ↑              │  │  │
                        │              │  │  │
               FACT_PRODUCT_PRICE      │  │  └──→ DIM_LOCATION
                   │       │           │  │
                   ↓       ↓           ↓  ↓
                  DIM_TIME (Role-Playing: order_date, ship_date, due_date,
                            start_date, end_date)
===============================================================================
*/

-- ============================================================
-- STEP 0: CREATE DATABASE & SCHEMA
-- ============================================================
USE master;
GO

-- Create database if not exists
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'DataWarehouse')
BEGIN
    CREATE DATABASE DataWarehouse;
END
GO

USE DataWarehouse;
GO

-- Create schema
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'gold')
BEGIN
    EXEC('CREATE SCHEMA gold');
END
GO

-- ============================================================
-- STEP 1: DROP TABLES (if exist) — order matters for FK
-- ============================================================
-- Drop Fact tables first (they reference Dimensions)
IF OBJECT_ID('gold.FACT_SALES', 'U') IS NOT NULL
    DROP TABLE gold.FACT_SALES;
GO

IF OBJECT_ID('gold.FACT_PRODUCT_PRICE', 'U') IS NOT NULL
    DROP TABLE gold.FACT_PRODUCT_PRICE;
GO

-- Drop Dimensions (child before parent)
IF OBJECT_ID('gold.DIM_PRODUCT', 'U') IS NOT NULL
    DROP TABLE gold.DIM_PRODUCT;
GO

IF OBJECT_ID('gold.DIM_CUSTOMER', 'U') IS NOT NULL
    DROP TABLE gold.DIM_CUSTOMER;
GO

IF OBJECT_ID('gold.DIM_LOCATION', 'U') IS NOT NULL
    DROP TABLE gold.DIM_LOCATION;
GO

IF OBJECT_ID('gold.DIM_TIME', 'U') IS NOT NULL
    DROP TABLE gold.DIM_TIME;
GO

IF OBJECT_ID('gold.DIM_CATEGORY', 'U') IS NOT NULL
    DROP TABLE gold.DIM_CATEGORY;
GO


-- ============================================================
-- STEP 2: CREATE DIMENSION TABLES
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- DIM_TIME (Date Dimension — Role-Playing)
-- Used by: FACT_SALES (order_date, ship_date, due_date)
--          FACT_PRODUCT_PRICE (start_date, end_date)
-- ────────────────────────────────────────────────────────────
CREATE TABLE gold.DIM_TIME (
    date_id         INT             NOT NULL,       -- PK: format YYYYMMDD
    full_date       DATE            NOT NULL,       -- Full date value
    day             INT             NOT NULL,       -- DAY(full_date)
    month           INT             NOT NULL,       -- MONTH(full_date)
    year            INT             NOT NULL,       -- YEAR(full_date)
    quarter         INT             NOT NULL,       -- DATEPART(QUARTER, full_date)
    day_of_week     INT             NOT NULL,       -- DATEPART(WEEKDAY, full_date)
    day_name        NVARCHAR(20)    NOT NULL,       -- DATENAME(WEEKDAY, full_date)
    month_name      NVARCHAR(20)    NOT NULL,       -- DATENAME(MONTH, full_date)
    week_of_year    INT             NOT NULL,       -- DATEPART(WEEK, full_date)
    CONSTRAINT PK_DIM_TIME PRIMARY KEY (date_id)
);
GO


-- ────────────────────────────────────────────────────────────
-- DIM_CATEGORY
-- Source: ERP PX_CAT_G1V2.csv
-- Referenced by: DIM_PRODUCT.category_id
-- ────────────────────────────────────────────────────────────
CREATE TABLE gold.DIM_CATEGORY (
    category_id         INT             NOT NULL IDENTITY(1,1),
    category            NVARCHAR(100)   NOT NULL,       -- Accessories, Bikes, Clothing, Components
    subcategory         NVARCHAR(100)   NOT NULL,       -- Helmets, Mountain Bikes, Jerseys, etc.
    maintenance_flag    NVARCHAR(3)     NOT NULL,       -- Yes / No
    CONSTRAINT PK_DIM_CATEGORY PRIMARY KEY (category_id)
);
GO


-- ────────────────────────────────────────────────────────────
-- DIM_CUSTOMER
-- Source: CRM cust_info.csv + ERP CUST_AZ12.csv
-- Referenced by: FACT_SALES.customer_id
-- SCD Type: 1 (overwrite)
-- ────────────────────────────────────────────────────────────
CREATE TABLE gold.DIM_CUSTOMER (
    customer_id         INT             NOT NULL IDENTITY(1,1),
    customer_key        NVARCHAR(50)    NOT NULL,       -- Business key (CRM cst_key)
    first_name          NVARCHAR(100)   NULL,           -- CRM cst_firstname (TRIMMED)
    last_name           NVARCHAR(100)   NULL,           -- CRM cst_lastname (TRIMMED)
    gender              NVARCHAR(10)    NULL,           -- Male / Female / Unknown
    marital_status      NVARCHAR(10)    NULL,           -- Single / Married
    birth_date          DATE            NULL,           -- ERP BDATE
    CONSTRAINT PK_DIM_CUSTOMER PRIMARY KEY (customer_id)
);
GO


-- ────────────────────────────────────────────────────────────
-- DIM_LOCATION
-- Source: ERP LOC_A101.csv
-- Referenced by: FACT_SALES.location_id
-- ────────────────────────────────────────────────────────────
CREATE TABLE gold.DIM_LOCATION (
    location_id         INT             NOT NULL IDENTITY(1,1),
    country             NVARCHAR(100)   NOT NULL,       -- Standardized country name
    region              NVARCHAR(50)    NOT NULL,       -- Derived: North America, Europe, Pacific
    CONSTRAINT PK_DIM_LOCATION PRIMARY KEY (location_id)
);
GO


-- ────────────────────────────────────────────────────────────
-- DIM_PRODUCT
-- Source: CRM prd_info.csv (latest version per product_key)
-- Referenced by: FACT_SALES.product_id
--                FACT_PRODUCT_PRICE.product_id
-- FK: category_id → DIM_CATEGORY
-- SCD Type: 1 (overwrite)
-- ────────────────────────────────────────────────────────────
CREATE TABLE gold.DIM_PRODUCT (
    product_id          INT             NOT NULL IDENTITY(1,1),
    product_key         NVARCHAR(50)    NOT NULL,       -- Business key (CRM prd_key)
    product_name        NVARCHAR(200)   NOT NULL,       -- CRM prd_nm
    product_line        NVARCHAR(50)    NULL,           -- R / M / S / T (NULL for some components)
    category_id         INT             NOT NULL,       -- FK → DIM_CATEGORY
    CONSTRAINT PK_DIM_PRODUCT PRIMARY KEY (product_id),
    CONSTRAINT FK_PRODUCT_CATEGORY FOREIGN KEY (category_id)
        REFERENCES gold.DIM_CATEGORY (category_id)
);
GO


-- ============================================================
-- STEP 3: CREATE FACT TABLES
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- FACT_SALES (Transaction Fact Table)
-- Source: CRM sales_details.csv
-- Grain: 1 row = 1 line-item sale transaction
-- ────────────────────────────────────────────────────────────
CREATE TABLE gold.FACT_SALES (
    order_id            NVARCHAR(20)    NOT NULL,       -- Degenerate Dimension (sls_ord_num)
    customer_id         INT             NOT NULL,       -- FK → DIM_CUSTOMER
    product_id          INT             NOT NULL,       -- FK → DIM_PRODUCT
    order_date_id       INT             NOT NULL,       -- FK → DIM_TIME (Role-Playing)
    ship_date_id        INT             NOT NULL,       -- FK → DIM_TIME (Role-Playing)
    due_date_id         INT             NOT NULL,       -- FK → DIM_TIME (Role-Playing)
    location_id         INT             NOT NULL,       -- FK → DIM_LOCATION
    quantity            INT             NOT NULL,       -- Measure (additive)
    sales_amount        DECIMAL(18,2)   NOT NULL,       -- Measure (additive)
    unit_price          DECIMAL(18,2)   NOT NULL,       -- Measure (non-additive)

    CONSTRAINT FK_SALES_CUSTOMER FOREIGN KEY (customer_id)
        REFERENCES gold.DIM_CUSTOMER (customer_id),

    CONSTRAINT FK_SALES_PRODUCT FOREIGN KEY (product_id)
        REFERENCES gold.DIM_PRODUCT (product_id),

    CONSTRAINT FK_SALES_ORDER_DATE FOREIGN KEY (order_date_id)
        REFERENCES gold.DIM_TIME (date_id),

    CONSTRAINT FK_SALES_SHIP_DATE FOREIGN KEY (ship_date_id)
        REFERENCES gold.DIM_TIME (date_id),

    CONSTRAINT FK_SALES_DUE_DATE FOREIGN KEY (due_date_id)
        REFERENCES gold.DIM_TIME (date_id),

    CONSTRAINT FK_SALES_LOCATION FOREIGN KEY (location_id)
        REFERENCES gold.DIM_LOCATION (location_id)
);
GO


-- ────────────────────────────────────────────────────────────
-- FACT_PRODUCT_PRICE (Periodic Snapshot Fact Table)
-- Source: CRM prd_info.csv (cost history)
-- Grain: 1 row = 1 product cost for 1 time period
-- ────────────────────────────────────────────────────────────
CREATE TABLE gold.FACT_PRODUCT_PRICE (
    product_price_id    INT             NOT NULL IDENTITY(1,1),
    product_id          INT             NOT NULL,       -- FK → DIM_PRODUCT
    start_date_id       INT             NOT NULL,       -- FK → DIM_TIME
    end_date_id         INT             NULL,           -- FK → DIM_TIME (NULL = current)
    cost                DECIMAL(18,2)   NULL,           -- Measure (some old records have NULL cost)
    is_current          BIT             NOT NULL DEFAULT 0,  -- 1 = current, 0 = history

    CONSTRAINT PK_FACT_PRODUCT_PRICE PRIMARY KEY (product_price_id),

    CONSTRAINT FK_PRICE_PRODUCT FOREIGN KEY (product_id)
        REFERENCES gold.DIM_PRODUCT (product_id),

    CONSTRAINT FK_PRICE_START_DATE FOREIGN KEY (start_date_id)
        REFERENCES gold.DIM_TIME (date_id),

    CONSTRAINT FK_PRICE_END_DATE FOREIGN KEY (end_date_id)
        REFERENCES gold.DIM_TIME (date_id)
);
GO


-- ============================================================
-- STEP 4: POPULATE DIM_TIME (Pre-generate date dimension)
-- Range: 2003-01-01 → 2025-12-31
-- ============================================================
DECLARE @StartDate DATE = '2003-01-01';
DECLARE @EndDate   DATE = '2025-12-31';

;WITH DateSequence AS (
    SELECT @StartDate AS dt
    UNION ALL
    SELECT DATEADD(DAY, 1, dt)
    FROM DateSequence
    WHERE dt < @EndDate
)
INSERT INTO gold.DIM_TIME (
    date_id, full_date, day, month, year,
    quarter, day_of_week, day_name, month_name, week_of_year
)
SELECT
    CONVERT(INT, FORMAT(dt, 'yyyyMMdd'))    AS date_id,
    dt                                       AS full_date,
    DAY(dt)                                  AS day,
    MONTH(dt)                                AS month,
    YEAR(dt)                                 AS year,
    DATEPART(QUARTER, dt)                    AS quarter,
    DATEPART(WEEKDAY, dt)                    AS day_of_week,
    DATENAME(WEEKDAY, dt)                    AS day_name,
    DATENAME(MONTH, dt)                      AS month_name,
    DATEPART(WEEK, dt)                       AS week_of_year
FROM DateSequence
OPTION (MAXRECURSION 0);
GO

PRINT '>>> DIM_TIME populated: ' + CAST((SELECT COUNT(*) FROM gold.DIM_TIME) AS VARCHAR) + ' rows';
GO


-- ============================================================
-- STEP 5: CREATE INDEXES (Performance)
-- ============================================================

-- FACT_SALES indexes
CREATE NONCLUSTERED INDEX IX_FACT_SALES_customer
    ON gold.FACT_SALES (customer_id);

CREATE NONCLUSTERED INDEX IX_FACT_SALES_product
    ON gold.FACT_SALES (product_id);

CREATE NONCLUSTERED INDEX IX_FACT_SALES_order_date
    ON gold.FACT_SALES (order_date_id);

CREATE NONCLUSTERED INDEX IX_FACT_SALES_location
    ON gold.FACT_SALES (location_id);

CREATE NONCLUSTERED INDEX IX_FACT_SALES_order_id
    ON gold.FACT_SALES (order_id);
GO

-- FACT_PRODUCT_PRICE indexes
CREATE NONCLUSTERED INDEX IX_FACT_PRICE_product
    ON gold.FACT_PRODUCT_PRICE (product_id);

CREATE NONCLUSTERED INDEX IX_FACT_PRICE_current
    ON gold.FACT_PRODUCT_PRICE (is_current)
    WHERE is_current = 1;
GO

-- DIM_PRODUCT index
CREATE NONCLUSTERED INDEX IX_DIM_PRODUCT_key
    ON gold.DIM_PRODUCT (product_key);
GO

-- DIM_CUSTOMER index
CREATE NONCLUSTERED INDEX IX_DIM_CUSTOMER_key
    ON gold.DIM_CUSTOMER (customer_key);
GO

PRINT '>>> All indexes created.';
GO


-- ============================================================
-- STEP 6: SAMPLE QUERIES — JOIN ALL TABLES
-- Demonstrates referential integrity across all relationships
-- ============================================================

/*
-- ─────────────────────────────────────────────────────────────
-- QUERY 1: Full Star Join — Sales with all Dimensions
-- Joins: FACT_SALES → DIM_CUSTOMER
--                    → DIM_PRODUCT → DIM_CATEGORY
--                    → DIM_TIME (order_date)
--                    → DIM_TIME (ship_date)
--                    → DIM_TIME (due_date)
--                    → DIM_LOCATION
-- ─────────────────────────────────────────────────────────────
*/
SELECT
    -- Order info
    fs.order_id,

    -- Customer
    dc.customer_key,
    dc.first_name,
    dc.last_name,
    dc.gender,
    dc.marital_status,
    dc.birth_date,

    -- Product
    dp.product_key,
    dp.product_name,
    dp.product_line,

    -- Category (Snowflake join)
    dcat.category,
    dcat.subcategory,
    dcat.maintenance_flag,

    -- Time: Order Date
    dt_order.full_date      AS order_date,
    dt_order.year           AS order_year,
    dt_order.quarter        AS order_quarter,
    dt_order.month_name     AS order_month,
    dt_order.day_name       AS order_day_name,

    -- Time: Ship Date
    dt_ship.full_date       AS ship_date,

    -- Time: Due Date
    dt_due.full_date        AS due_date,

    -- Location
    dl.country,
    dl.region,

    -- Measures
    fs.quantity,
    fs.sales_amount,
    fs.unit_price

FROM gold.FACT_SALES fs

-- Dimension joins
INNER JOIN gold.DIM_CUSTOMER dc
    ON fs.customer_id = dc.customer_id

INNER JOIN gold.DIM_PRODUCT dp
    ON fs.product_id = dp.product_id

-- Snowflake join: Product → Category
INNER JOIN gold.DIM_CATEGORY dcat
    ON dp.category_id = dcat.category_id

-- Role-Playing Dimension: 3x DIM_TIME
INNER JOIN gold.DIM_TIME dt_order
    ON fs.order_date_id = dt_order.date_id

INNER JOIN gold.DIM_TIME dt_ship
    ON fs.ship_date_id = dt_ship.date_id

INNER JOIN gold.DIM_TIME dt_due
    ON fs.due_date_id = dt_due.date_id

-- Location
INNER JOIN gold.DIM_LOCATION dl
    ON fs.location_id = dl.location_id;
GO


/*
-- ─────────────────────────────────────────────────────────────
-- QUERY 2: Product Price History Join
-- Joins: FACT_PRODUCT_PRICE → DIM_PRODUCT → DIM_CATEGORY
--                            → DIM_TIME (start_date)
--                            → DIM_TIME (end_date)
-- ─────────────────────────────────────────────────────────────
*/
SELECT
    -- Product
    dp.product_key,
    dp.product_name,
    dp.product_line,
    dcat.category,
    dcat.subcategory,

    -- Price history
    fpp.cost,
    fpp.is_current,

    -- Time range
    dt_start.full_date      AS price_start_date,
    dt_end.full_date        AS price_end_date

FROM gold.FACT_PRODUCT_PRICE fpp

INNER JOIN gold.DIM_PRODUCT dp
    ON fpp.product_id = dp.product_id

INNER JOIN gold.DIM_CATEGORY dcat
    ON dp.category_id = dcat.category_id

INNER JOIN gold.DIM_TIME dt_start
    ON fpp.start_date_id = dt_start.date_id

LEFT JOIN gold.DIM_TIME dt_end
    ON fpp.end_date_id = dt_end.date_id     -- LEFT JOIN: end_date NULL = current
GO


/*
-- ─────────────────────────────────────────────────────────────
-- QUERY 3: Sales with Current Product Cost (Profit Analysis)
-- Combines FACT_SALES + FACT_PRODUCT_PRICE for margin calc
-- ─────────────────────────────────────────────────────────────
*/
SELECT
    fs.order_id,
    dp.product_name,
    dcat.category,
    dt_order.full_date          AS order_date,
    dc.first_name + ' ' + dc.last_name AS customer_name,
    dl.country,
    dl.region,

    -- Measures
    fs.quantity,
    fs.unit_price,
    fs.sales_amount,
    fpp.cost                    AS product_cost,

    -- Calculated: Gross Margin
    fs.sales_amount - (fpp.cost * fs.quantity) AS gross_margin

FROM gold.FACT_SALES fs

INNER JOIN gold.DIM_PRODUCT dp
    ON fs.product_id = dp.product_id

INNER JOIN gold.DIM_CATEGORY dcat
    ON dp.category_id = dcat.category_id

INNER JOIN gold.DIM_CUSTOMER dc
    ON fs.customer_id = dc.customer_id

INNER JOIN gold.DIM_TIME dt_order
    ON fs.order_date_id = dt_order.date_id

INNER JOIN gold.DIM_LOCATION dl
    ON fs.location_id = dl.location_id

-- Join current price
LEFT JOIN gold.FACT_PRODUCT_PRICE fpp
    ON dp.product_id = fpp.product_id
    AND fpp.is_current = 1;
GO


-- ============================================================
-- STEP 7: VERIFICATION — Confirm all objects created
-- ============================================================
SELECT
    t.TABLE_SCHEMA  AS [Schema],
    t.TABLE_NAME    AS [Table],
    t.TABLE_TYPE    AS [Type],
    (
        SELECT COUNT(*)
        FROM INFORMATION_SCHEMA.COLUMNS c
        WHERE c.TABLE_SCHEMA = t.TABLE_SCHEMA
          AND c.TABLE_NAME = t.TABLE_NAME
    ) AS [Columns]
FROM INFORMATION_SCHEMA.TABLES t
WHERE t.TABLE_SCHEMA = 'gold'
ORDER BY
    CASE
        WHEN t.TABLE_NAME LIKE 'DIM%' THEN 0
        ELSE 1
    END,
    t.TABLE_NAME;
GO

-- Show all FK relationships
SELECT
    fk.name                         AS [FK Name],
    OBJECT_NAME(fk.parent_object_id)    AS [From Table],
    COL_NAME(fkc.parent_object_id, fkc.parent_column_id)   AS [From Column],
    OBJECT_NAME(fk.referenced_object_id) AS [To Table],
    COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id) AS [To Column]
FROM sys.foreign_keys fk
INNER JOIN sys.foreign_key_columns fkc
    ON fk.object_id = fkc.constraint_object_id
WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id) = 'gold'
ORDER BY [From Table], [FK Name];
GO

PRINT '===============================================';
PRINT '  DATA WAREHOUSE SETUP COMPLETE';
PRINT '  Tables  : 7 (5 Dimensions + 2 Facts)';
PRINT '  Schema  : gold';
PRINT '  DIM_TIME: Pre-populated (2003-2025)';
PRINT '  Indexes : Created for all FK columns';
PRINT '===============================================';
GO
