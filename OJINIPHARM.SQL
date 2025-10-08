-- =====================================================
-- MATERIALIZED VIEWS FOR PHARMACEUTICAL ANALYTICS
-- =====================================================

-- =====================================================
-- 1. SALES ANALYTICS MATERIALIZED VIEWS
-- =====================================================

-- Daily Sales Summary by Product
CREATE MATERIALIZED VIEW mv_daily_sales_by_product AS
SELECT 
    DATE_TRUNC('day', sale_date) AS sale_day,
    product_id,
    product_name,
    therapeutic_category,
    COUNT(DISTINCT transaction_id) AS transaction_count,
    SUM(quantity) AS total_quantity_sold,
    SUM(unit_price * quantity) AS total_revenue,
    AVG(unit_price) AS avg_unit_price,
    SUM(discount_amount) AS total_discounts,
    COUNT(DISTINCT customer_id) AS unique_customers,
    COUNT(DISTINCT pharmacy_id) AS unique_pharmacies
FROM sales_transactions st
JOIN products p ON st.product_id = p.product_id
WHERE sale_date >= CURRENT_DATE - INTERVAL '2 years'
GROUP BY 
    DATE_TRUNC('day', sale_date),
    product_id,
    product_name,
    therapeutic_category;

CREATE INDEX idx_mv_daily_sales_date ON mv_daily_sales_by_product(sale_day);
CREATE INDEX idx_mv_daily_sales_product ON mv_daily_sales_by_product(product_id);
CREATE INDEX idx_mv_daily_sales_category ON mv_daily_sales_by_product(therapeutic_category);

-- Monthly Sales Summary by Region
CREATE MATERIALIZED VIEW mv_monthly_sales_by_region AS
SELECT 
    DATE_TRUNC('month', sale_date) AS sale_month,
    r.region_id,
    r.region_name,
    r.country,
    p.therapeutic_category,
    COUNT(DISTINCT st.transaction_id) AS transaction_count,
    SUM(st.quantity) AS total_quantity,
    SUM(st.unit_price * st.quantity) AS total_revenue,
    SUM(st.discount_amount) AS total_discounts,
    SUM(st.unit_price * st.quantity - st.discount_amount) AS net_revenue,
    COUNT(DISTINCT st.customer_id) AS unique_customers,
    AVG(st.unit_price * st.quantity) AS avg_transaction_value
FROM sales_transactions st
JOIN products p ON st.product_id = p.product_id
JOIN pharmacies ph ON st.pharmacy_id = ph.pharmacy_id
JOIN regions r ON ph.region_id = r.region_id
WHERE sale_date >= CURRENT_DATE - INTERVAL '3 years'
GROUP BY 
    DATE_TRUNC('month', sale_date),
    r.region_id,
    r.region_name,
    r.country,
    p.therapeutic_category;

CREATE INDEX idx_mv_monthly_sales_month ON mv_monthly_sales_by_region(sale_month);
CREATE INDEX idx_mv_monthly_sales_region ON mv_monthly_sales_by_region(region_id);

-- Top Performing Products (Rolling 90 Days)
CREATE MATERIALIZED VIEW mv_top_products_90d AS
SELECT 
    p.product_id,
    p.product_name,
    p.therapeutic_category,
    p.manufacturer,
    COUNT(DISTINCT st.transaction_id) AS transaction_count,
    SUM(st.quantity) AS total_quantity_sold,
    SUM(st.unit_price * st.quantity) AS total_revenue,
    AVG(st.unit_price * st.quantity) AS avg_transaction_value,
    COUNT(DISTINCT st.customer_id) AS unique_customers,
    RANK() OVER (ORDER BY SUM(st.unit_price * st.quantity) DESC) AS revenue_rank,
    RANK() OVER (ORDER BY SUM(st.quantity) DESC) AS volume_rank
FROM sales_transactions st
JOIN products p ON st.product_id = p.product_id
WHERE st.sale_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY 
    p.product_id,
    p.product_name,
    p.therapeutic_category,
    p.manufacturer;

CREATE INDEX idx_mv_top_products_rank ON mv_top_products_90d(revenue_rank);

-- =====================================================
-- 2. PRESCRIPTION ANALYTICS MATERIALIZED VIEWS
-- =====================================================

-- Daily Prescription Counts by Drug and Prescriber Type
CREATE MATERIALIZED VIEW mv_daily_prescriptions AS
SELECT 
    DATE_TRUNC('day', rx.prescription_date) AS prescription_day,
    rx.drug_id,
    d.drug_name,
    d.generic_name,
    d.drug_class,
    pr.specialty AS prescriber_specialty,
    COUNT(DISTINCT rx.prescription_id) AS prescription_count,
    COUNT(DISTINCT rx.patient_id) AS unique_patients,
    COUNT(DISTINCT rx.prescriber_id) AS unique_prescribers,
    SUM(rx.quantity_prescribed) AS total_quantity,
    AVG(rx.days_supply) AS avg_days_supply,
    COUNT(CASE WHEN rx.is_refill = TRUE THEN 1 END) AS refill_count,
    COUNT(CASE WHEN rx.is_refill = FALSE THEN 1 END) AS new_prescription_count
FROM prescriptions rx
JOIN drugs d ON rx.drug_id = d.drug_id
JOIN prescribers pr ON rx.prescriber_id = pr.prescriber_id
WHERE rx.prescription_date >= CURRENT_DATE - INTERVAL '2 years'
GROUP BY 
    DATE_TRUNC('day', rx.prescription_date),
    rx.drug_id,
    d.drug_name,
    d.generic_name,
    d.drug_class,
    pr.specialty;

CREATE INDEX idx_mv_daily_rx_date ON mv_daily_prescriptions(prescription_day);
CREATE INDEX idx_mv_daily_rx_drug ON mv_daily_prescriptions(drug_id);
CREATE INDEX idx_mv_daily_rx_class ON mv_daily_prescriptions(drug_class);

-- Monthly Prescriber Analytics
CREATE MATERIALIZED VIEW mv_monthly_prescriber_stats AS
SELECT 
    DATE_TRUNC('month', rx.prescription_date) AS prescription_month,
    pr.prescriber_id,
    pr.prescriber_name,
    pr.specialty,
    pr.facility_name,
    COUNT(DISTINCT rx.prescription_id) AS total_prescriptions,
    COUNT(DISTINCT rx.patient_id) AS unique_patients,
    COUNT(DISTINCT rx.drug_id) AS unique_drugs_prescribed,
    AVG(rx.quantity_prescribed) AS avg_quantity_per_rx,
    COUNT(CASE WHEN d.is_controlled_substance = TRUE THEN 1 END) AS controlled_substance_count,
    COUNT(CASE WHEN d.requires_prior_auth = TRUE THEN 1 END) AS prior_auth_required_count
FROM prescriptions rx
JOIN prescribers pr ON rx.prescriber_id = pr.prescriber_id
JOIN drugs d ON rx.drug_id = d.drug_id
WHERE rx.prescription_date >= CURRENT_DATE - INTERVAL '2 years'
GROUP BY 
    DATE_TRUNC('month', rx.prescription_date),
    pr.prescriber_id,
    pr.prescriber_name,
    pr.specialty,
    pr.facility_name;

CREATE INDEX idx_mv_monthly_prescriber_month ON mv_monthly_prescriber_stats(prescription_month);
CREATE INDEX idx_mv_monthly_prescriber_id ON mv_monthly_prescriber_stats(prescriber_id);

-- Drug Utilization Patterns
CREATE MATERIALIZED VIEW mv_drug_utilization_patterns AS
SELECT 
    d.drug_id,
    d.drug_name,
    d.generic_name,
    d.drug_class,
    d.therapeutic_category,
    COUNT(DISTINCT rx.prescription_id) AS total_prescriptions,
    COUNT(DISTINCT rx.patient_id) AS unique_patients,
    COUNT(DISTINCT rx.prescriber_id) AS unique_prescribers,
    AVG(rx.quantity_prescribed) AS avg_quantity,
    AVG(rx.days_supply) AS avg_days_supply,
    STDDEV(rx.quantity_prescribed) AS stddev_quantity,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rx.quantity_prescribed) AS median_quantity,
    COUNT(CASE WHEN rx.is_refill = TRUE THEN 1 END) AS refill_count,
    ROUND(100.0 * COUNT(CASE WHEN rx.is_refill = TRUE THEN 1 END) / COUNT(*), 2) AS refill_rate_pct
FROM prescriptions rx
JOIN drugs d ON rx.drug_id = d.drug_id
WHERE rx.prescription_date >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY 
    d.drug_id,
    d.drug_name,
    d.generic_name,
    d.drug_class,
    d.therapeutic_category
HAVING COUNT(DISTINCT rx.prescription_id) >= 10;

CREATE INDEX idx_mv_drug_util_drug ON mv_drug_utilization_patterns(drug_id);
CREATE INDEX idx_mv_drug_util_class ON mv_drug_utilization_patterns(drug_class);

-- =====================================================
-- 3. REGULATORY APPROVAL ANALYTICS MATERIALIZED VIEWS
-- =====================================================

-- Regulatory Approval Timeline Summary
CREATE MATERIALIZED VIEW mv_regulatory_approval_summary AS
SELECT 
    ra.approval_id,
    ra.drug_id,
    d.drug_name,
    d.generic_name,
    d.manufacturer,
    ra.regulatory_body,
    ra.country,
    ra.approval_type,
    ra.submission_date,
    ra.approval_date,
    ra.approval_date - ra.submission_date AS days_to_approval,
    ra.status,
    ra.indication,
    ra.priority_review,
    ra.orphan_designation,
    ra.fast_track_designation,
    EXTRACT(YEAR FROM ra.approval_date) AS approval_year,
    EXTRACT(QUARTER FROM ra.approval_date) AS approval_quarter
FROM regulatory_approvals ra
JOIN drugs d ON ra.drug_id = d.drug_id
WHERE ra.submission_date >= '2015-01-01';

CREATE INDEX idx_mv_reg_approval_drug ON mv_regulatory_approval_summary(drug_id);
CREATE INDEX idx_mv_reg_approval_body ON mv_regulatory_approval_summary(regulatory_body);
CREATE INDEX idx_mv_reg_approval_country ON mv_regulatory_approval_summary(country);
CREATE INDEX idx_mv_reg_approval_year ON mv_regulatory_approval_summary(approval_year);

-- Quarterly Approval Metrics by Regulatory Body
CREATE MATERIALIZED VIEW mv_quarterly_approval_metrics AS
SELECT 
    DATE_TRUNC('quarter', approval_date) AS approval_quarter,
    regulatory_body,
    country,
    approval_type,
    COUNT(DISTINCT approval_id) AS total_approvals,
    COUNT(DISTINCT drug_id) AS unique_drugs_approved,
    AVG(approval_date - submission_date) AS avg_days_to_approval,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY approval_date - submission_date) AS median_days_to_approval,
    COUNT(CASE WHEN priority_review = TRUE THEN 1 END) AS priority_review_count,
    COUNT(CASE WHEN orphan_designation = TRUE THEN 1 END) AS orphan_designation_count,
    COUNT(CASE WHEN fast_track_designation = TRUE THEN 1 END) AS fast_track_count,
    COUNT(CASE WHEN status = 'Approved' THEN 1 END) AS approved_count,
    COUNT(CASE WHEN status = 'Pending' THEN 1 END) AS pending_count,
    COUNT(CASE WHEN status = 'Rejected' THEN 1 END) AS rejected_count
FROM regulatory_approvals
WHERE approval_date IS NOT NULL
GROUP BY 
    DATE_TRUNC('quarter', approval_date),
    regulatory_body,
    country,
    approval_type;

CREATE INDEX idx_mv_quarterly_approval_quarter ON mv_quarterly_approval_metrics(approval_quarter);
CREATE INDEX idx_mv_quarterly_approval_body ON mv_quarterly_approval_metrics(regulatory_body);

-- Drug Pipeline Status
CREATE MATERIALIZED VIEW mv_drug_pipeline_status AS
SELECT 
    d.drug_id,
    d.drug_name,
    d.generic_name,
    d.manufacturer,
    d.therapeutic_category,
    d.development_phase,
    COUNT(DISTINCT ra.approval_id) AS total_submissions,
    COUNT(DISTINCT ra.country) AS countries_submitted,
    COUNT(CASE WHEN ra.status = 'Approved' THEN 1 END) AS approved_count,
    COUNT(CASE WHEN ra.status = 'Pending' THEN 1 END) AS pending_count,
    COUNT(CASE WHEN ra.status = 'Rejected' THEN 1 END) AS rejected_count,
    MIN(ra.submission_date) AS first_submission_date,
    MAX(ra.approval_date) AS latest_approval_date,
    BOOL_OR(ra.priority_review) AS has_priority_review,
    BOOL_OR(ra.orphan_designation) AS has_orphan_designation,
    STRING_AGG(DISTINCT ra.regulatory_body, ', ' ORDER BY ra.regulatory_body) AS regulatory_bodies
FROM drugs d
LEFT JOIN regulatory_approvals ra ON d.drug_id = ra.drug_id
WHERE d.development_phase IN ('Clinical Trial', 'Under Review', 'Approved')
GROUP BY 
    d.drug_id,
    d.drug_name,
    d.generic_name,
    d.manufacturer,
    d.therapeutic_category,
    d.development_phase;

CREATE INDEX idx_mv_pipeline_drug ON mv_drug_pipeline_status(drug_id);
CREATE INDEX idx_mv_pipeline_phase ON mv_drug_pipeline_status(development_phase);
CREATE INDEX idx_mv_pipeline_manufacturer ON mv_drug_pipeline_status(manufacturer);

-- =====================================================
-- 4. CROSS-FUNCTIONAL ANALYTICS MATERIALIZED VIEWS
-- =====================================================

-- Integrated Product Performance Dashboard
CREATE MATERIALIZED VIEW mv_product_performance_dashboard AS
SELECT 
    p.product_id,
    p.product_name,
    p.therapeutic_category,
    p.manufacturer,
    
    -- Sales Metrics (Last 90 Days)
    COALESCE(s90.total_revenue, 0) AS revenue_90d,
    COALESCE(s90.total_quantity, 0) AS quantity_sold_90d,
    COALESCE(s90.unique_customers, 0) AS customers_90d,
    
    -- Prescription Metrics (Last 90 Days)
    COALESCE(rx90.prescription_count, 0) AS prescriptions_90d,
    COALESCE(rx90.unique_patients, 0) AS patients_90d,
    COALESCE(rx90.unique_prescribers, 0) AS prescribers_90d,
    
    -- Regulatory Status
    COALESCE(reg.approved_markets, 0) AS approved_markets_count,
    reg.latest_approval_date,
    reg.regulatory_status,
    
    -- Trend Indicators
    CASE 
        WHEN s90.total_revenue > s90_prev.total_revenue THEN 'Growing'
        WHEN s90.total_revenue < s90_prev.total_revenue THEN 'Declining'
        ELSE 'Stable'
    END AS revenue_trend
    
FROM products p

LEFT JOIN (
    SELECT product_id, 
           SUM(total_revenue) AS total_revenue,
           SUM(total_quantity) AS total_quantity,
           COUNT(DISTINCT customer_id) AS unique_customers
    FROM sales_transactions
    WHERE sale_date >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY product_id
) s90 ON p.product_id = s90.product_id

LEFT JOIN (
    SELECT product_id,
           SUM(total_revenue) AS total_revenue
    FROM sales_transactions
    WHERE sale_date >= CURRENT_DATE - INTERVAL '180 days'
      AND sale_date < CURRENT_DATE - INTERVAL '90 days'
    GROUP BY product_id
) s90_prev ON p.product_id = s90_prev.product_id

LEFT JOIN (
    SELECT d.product_id,
           COUNT(DISTINCT rx.prescription_id) AS prescription_count,
           COUNT(DISTINCT rx.patient_id) AS unique_patients,
           COUNT(DISTINCT rx.prescriber_id) AS unique_prescribers
    FROM prescriptions rx
    JOIN drugs d ON rx.drug_id = d.drug_id
    WHERE rx.prescription_date >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY d.product_id
) rx90 ON p.product_id = rx90.product_id

LEFT JOIN (
    SELECT d.product_id,
           COUNT(DISTINCT ra.country) AS approved_markets,
           MAX(ra.approval_date) AS latest_approval_date,
           STRING_AGG(DISTINCT ra.status, ', ') AS regulatory_status
    FROM regulatory_approvals ra
    JOIN drugs d ON ra.drug_id = d.drug_id
    GROUP BY d.product_id
) reg ON p.product_id = reg.product_id;

CREATE INDEX idx_mv_dashboard_product ON mv_product_performance_dashboard(product_id);
CREATE INDEX idx_mv_dashboard_category ON mv_product_performance_dashboard(therapeutic_category);
CREATE INDEX idx_mv_dashboard_trend ON mv_product_performance_dashboard(revenue_trend);

-- =====================================================
-- 5. REFRESH PROCEDURES
-- =====================================================

-- Incremental Refresh Procedure (for daily updates)
CREATE OR REPLACE PROCEDURE refresh_daily_materialized_views()
LANGUAGE plpgsql
AS $$
BEGIN
    -- Refresh sales materialized views
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_sales_by_product;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_top_products_90d;
    
    -- Refresh prescription materialized views
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_prescriptions;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_drug_utilization_patterns;
    
    -- Refresh integrated dashboard
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_product_performance_dashboard;
    
    RAISE NOTICE 'Daily materialized views refreshed at %', NOW();
END;
$$;

-- Monthly Refresh Procedure (for less frequent updates)
CREATE OR REPLACE PROCEDURE refresh_monthly_materialized_views()
LANGUAGE plpgsql
AS $$
BEGIN
    -- Refresh monthly aggregates
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_sales_by_region;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_prescriber_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_quarterly_approval_metrics;
    
    -- Refresh regulatory views
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_regulatory_approval_summary;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_drug_pipeline_status;
    
    RAISE NOTICE 'Monthly materialized views refreshed at %', NOW();
END;
$$;

-- Schedule automated refreshes (using pg_cron extension)
-- Daily refresh at 2 AM
SELECT cron.schedule('daily-mv-refresh', '0 2 * * *', 'CALL refresh_daily_materialized_views();');

-- Monthly refresh on 1st day of month at 3 AM
SELECT cron.schedule('monthly-mv-refresh', '0 3 1 * *', 'CALL refresh_monthly_materialized_views();');

-- =====================================================
-- 6. MONITORING QUERIES
-- =====================================================

-- Check materialized view freshness
CREATE VIEW v_materialized_view_status AS
SELECT 
    schemaname,
    matviewname,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||matviewname)) AS size,
    last_refresh,
    CASE 
        WHEN last_refresh > NOW() - INTERVAL '1 day' THEN 'Current'
        WHEN last_refresh > NOW() - INTERVAL '7 days' THEN 'Slightly Stale'
        ELSE 'Stale'
    END AS freshness_status
FROM pg_matviews
WHERE schemaname = 'public'
ORDER BY last_refresh DESC;

-- Example usage query
-- SELECT * FROM v_materialized_view_status;
