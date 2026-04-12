import pandas as pd
import numpy as np
import os

def xu_ly_xay_dung_cac_fact():
    print("Bắt đầu tiến trình tạo các bảng Fact Đa Dạng (Gold Layer DWH)...")
    
    # 1. Đọc dữ liệu Transaction gốc cực lớn từ CRM Sales Details
    duong_dan_goc = r"e:\JOURNEY DATA ENGINEERING\Kho dữ liệu cuối kỳ\sql-data-warehouse-project\datasets\source_crm\sales_details.csv"
    if not os.path.exists(duong_dan_goc):
        print(f"Lỗi: Không tìm thấy file gốc tại {duong_dan_goc}")
        return
        
    df_sales = pd.read_csv(duong_dan_goc)
    print(f"-> Đã đọc {len(df_sales)} dòng từ bảng sales_details.")
    
    # Ở một hệ thống thực tế ta sẽ thay thế sls_cust_id và sls_prd_key bằng surrogate keys. 
    # Nhưng ở đây để Data Warehouse dễ hiểu ta sẽ giả lập bước Map Key.
    
    # =========================================================================================
    # A. TẠO FACT SALES TRANSACTIONS (Cốt lõi)
    # =========================================================================================
    print("-> Đang tạo bảng fact_sales_transactions...")
    fact_sales_transactions = df_sales[[
        'sls_ord_num', 'sls_cust_id', 'sls_prd_key', 'sls_order_dt', 
        'sls_quantity', 'sls_price', 'sls_sales'
    ]].copy()
    
    # Rename lại cho đúng chuẩn DWH
    fact_sales_transactions.rename(columns={
        'sls_ord_num': 'order_number',
        'sls_cust_id': 'customer_sk',
        'sls_prd_key': 'product_sk', # Thông thường sẽ lookup ra Surrogate key INT
        'sls_order_dt': 'order_date_key',
        'sls_quantity': 'quantity',
        'sls_price': 'price',
        'sls_sales': 'sales_amount'
    }, inplace=True)
    
    # =========================================================================================
    # B. TẠO FACT ORDER FULFILLMENT (Bảng Vận Hành - Accumulating Snapshot)
    # =========================================================================================
    print("-> Đang tạo bảng fact_order_fulfillment...")
    
    # Nhóm theo từng đơn hàng (1 Đơn hàng có thể mua nhiều món)
    fact_order_fulfillment = df_sales.groupby(['sls_ord_num', 'sls_cust_id', 'sls_order_dt', 'sls_ship_dt', 'sls_due_dt']).agg(
        total_order_lines=('sls_prd_key', 'count'),
        total_order_amount=('sls_sales', 'sum')
    ).reset_index()
    
    fact_order_fulfillment.rename(columns={
        'sls_ord_num': 'order_number',
        'sls_cust_id': 'customer_sk',
        'sls_order_dt': 'order_date_key',
        'sls_ship_dt': 'ship_date_key',
        'sls_due_dt': 'due_date_key'
    }, inplace=True)
    
    # Parse mốc thời gian để tính toán KPI (Lưu ý Format đang là YYYYMMDD dạng Integer hoặc chuỗi)
    try:
        fact_order_fulfillment['order_date_dt'] = pd.to_datetime(fact_order_fulfillment['order_date_key'].astype(str), format='%Y%m%d', errors='coerce')
        fact_order_fulfillment['ship_date_dt'] = pd.to_datetime(fact_order_fulfillment['ship_date_key'].astype(str), format='%Y%m%d', errors='coerce')
        fact_order_fulfillment['due_date_dt'] = pd.to_datetime(fact_order_fulfillment['due_date_key'].astype(str), format='%Y%m%d', errors='coerce')
        
        # Chỉ số 1: Số ngày từ lúc đặt tới lúc giao
        fact_order_fulfillment['time_to_ship_days'] = (fact_order_fulfillment['ship_date_dt'] - fact_order_fulfillment['order_date_dt']).dt.days
        
        # Chỉ số 2: Trễ hẹn
        fact_order_fulfillment['shipping_delay_days'] = (fact_order_fulfillment['ship_date_dt'] - fact_order_fulfillment['due_date_dt']).dt.days
        fact_order_fulfillment['is_late_shipment_flag'] = fact_order_fulfillment['shipping_delay_days'].apply(lambda x: 1 if x > 0 else 0)
        
        # Xoá cột tạm
        fact_order_fulfillment.drop(columns=['order_date_dt', 'ship_date_dt', 'due_date_dt'], inplace=True)
    except Exception as e:
        print(f"Cảnh báo: Không thể parse Date. Chi tiết: {e}")
        
    # =========================================================================================
    # C. TẠO FACT MONTHLY SALES SNAPSHOT (Bảng Dashboards Định Kỳ)
    # =========================================================================================
    print("-> Đang tạo bảng fact_monthly_sales_snapshot...")
    # Tạo year_month_key từ order_date_dt (VD: 20101229 -> 201012)
    df_sales_tmp = df_sales.copy()
    df_sales_tmp['year_month_key'] = (df_sales_tmp['sls_order_dt'] // 100).astype(int) # Chặt mất ngày
    
    fact_monthly_sales_snapshot = df_sales_tmp.groupby(['year_month_key', 'sls_prd_key', 'sls_cust_id']).agg(
        monthly_total_revenue=('sls_sales', 'sum'),
        monthly_total_quantity=('sls_quantity', 'sum'),
        order_count_in_month=('sls_ord_num', 'nunique')
    ).reset_index()
    
    fact_monthly_sales_snapshot.rename(columns={
        'sls_prd_key': 'product_sk',
        'sls_cust_id': 'customer_sk'
    }, inplace=True)
    
    # =========================================================================================
    # D. TẠO FACT CUSTOMER LIFETIME METRICS (Bảng Marketing / CRM)
    # =========================================================================================
    print("-> Đang tạo bảng fact_customer_lifetime_metrics...")
    # Nhóm mọi thứ dựa vào khách hàng để tính Vòng Đời
    fact_customer_lifetime_metrics = df_sales.groupby('sls_cust_id').agg(
        first_purchase_date_key=('sls_order_dt', 'min'),
        last_purchase_date_key=('sls_order_dt', 'max'),
        lifetime_value=('sls_sales', 'sum'),
        total_orders_placed=('sls_ord_num', 'nunique')
    ).reset_index()
    
    fact_customer_lifetime_metrics.rename(columns={
        'sls_cust_id': 'customer_sk'
    }, inplace=True)
    
    # Chia Tier Đơn giản
    def phan_loai_khach_hang(tien):
        if tien > 5000:
            return 'VIP'
        elif tien > 1000:
            return 'Regular'
        else:
            return 'Casual'
            
    fact_customer_lifetime_metrics['customer_segment'] = fact_customer_lifetime_metrics['lifetime_value'].apply(phan_loai_khach_hang)
    
    # =========================================================================================
    # 5. XUẤT RA DỮ LIỆU ĐỂ KIỂM TRA (LƯU RA THƯ MỤC SILVER/GOLD HOẶC IN MÀN HÌNH)
    # =========================================================================================
    thu_muc_luu = r"e:\JOURNEY DATA ENGINEERING\Kho dữ liệu cuối kỳ\sql-data-warehouse-project\datasets\gold_layer_output"
    os.makedirs(thu_muc_luu, exist_ok=True)
    
    print("-> Đang lưu các Fact files ra ổ đĩa...")
    fact_sales_transactions.to_csv(os.path.join(thu_muc_luu, 'fact_sales_transactions.csv'), index=False)
    fact_order_fulfillment.to_csv(os.path.join(thu_muc_luu, 'fact_order_fulfillment.csv'), index=False)
    fact_monthly_sales_snapshot.to_csv(os.path.join(thu_muc_luu, 'fact_monthly_sales_snapshot.csv'), index=False)
    fact_customer_lifetime_metrics.to_csv(os.path.join(thu_muc_luu, 'fact_customer_lifetime_metrics.csv'), index=False)
    
    print("\n[THÀNH CÔNG] Đã tạo và tính toán hoàn chỉnh 4 loại Fact đa dạng cho kho dữ liệu!")
    print(f"Fact Transactions: {len(fact_sales_transactions)} record")
    print(f"Fact Fulfillment: {len(fact_order_fulfillment)} record")
    print(f"Fact Monthly: {len(fact_monthly_sales_snapshot)} record")
    print(f"Fact LTV: {len(fact_customer_lifetime_metrics)} record")

if __name__ == "__main__":
    xu_ly_xay_dung_cac_fact()
