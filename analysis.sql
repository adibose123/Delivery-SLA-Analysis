/* ============================================================
   PORTER / DOORDASH-SCHEMA DELIVERY DATA — SQL ANALYSIS
   Source: Kaggle "Porter Delivery Time Estimation Dataset"
   Database: porter_delivery (see schema.sql)
   Dialect: MySQL 8.0+ / MariaDB 10.2+ (uses CTEs and window functions)
   ============================================================ */

USE porter_delivery;

-- ------------------------------------------------------------
-- 0. SCHEMA — see schema.sql for the full table definition
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- 1. DATA QUALITY CHECKS
-- ------------------------------------------------------------

-- 1a. Row count, target-variable sanity (duration should never be negative or absurd)
SELECT COUNT(*) AS total_orders,
  ROUND(MIN(duration_min),1) AS min_duration, ROUND(MAX(duration_min),1) AS max_duration,
  SUM(CASE WHEN duration_min <= 0 THEN 1 ELSE 0 END) AS non_positive_durations
FROM deliveries;

-- 1b. Known data issues, quantified (kept in the table, not silently dropped)
SELECT
  SUM(CASE WHEN valid_dasher_data = 0 THEN 1 ELSE 0 END)               AS negative_dasher_readings,
  SUM(CASE WHEN min_item_price > max_item_price THEN 1 ELSE 0 END)     AS min_gt_max_price_rows,
  SUM(CASE WHEN subtotal <= 0 THEN 1 ELSE 0 END)                       AS non_positive_subtotal_rows
FROM deliveries;

-- ------------------------------------------------------------
-- 2. HEADLINE: OVERALL DELIVERY PERFORMANCE & SLA BREACH
-- ------------------------------------------------------------

SELECT
  COUNT(*) AS total_orders,
  ROUND(AVG(duration_min), 1) AS avg_duration_min,
  SUM(CASE WHEN duration_min > 60 THEN 1 ELSE 0 END) AS orders_over_60min,
  ROUND(100.0 * SUM(CASE WHEN duration_min > 60 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_over_60min
FROM deliveries;

-- ------------------------------------------------------------
-- 3. THE MAIN DRIVER: DASHER SUPPLY vs DEMAND
-- ------------------------------------------------------------

-- 3a. Duration & SLA breach by how "busy" the dasher pool is
--     (busy_ratio = total_busy_dashers / total_onshift_dashers)
SELECT
  CASE WHEN total_onshift_dashers = 0 THEN '1. no dashers onshift'
       WHEN total_busy_dashers / total_onshift_dashers < 0.5  THEN '2. <50% busy'
       WHEN total_busy_dashers / total_onshift_dashers < 0.8  THEN '3. 50-80% busy'
       WHEN total_busy_dashers / total_onshift_dashers < 1.0  THEN '4. 80-100% busy'
       WHEN total_busy_dashers / total_onshift_dashers < 1.5  THEN '5. 100-150% busy'
       ELSE '6. 150%+ busy' END AS dasher_load,
  COUNT(*) AS orders,
  ROUND(AVG(duration_min), 1) AS avg_duration_min,
  ROUND(100.0 * SUM(CASE WHEN duration_min > 60 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_over_60min
FROM deliveries
WHERE valid_dasher_data = 1
GROUP BY dasher_load
ORDER BY dasher_load;

-- ------------------------------------------------------------
-- 4. MARKET-LEVEL PERFORMANCE (window function: RANK)
-- ------------------------------------------------------------

-- 4a. Rank markets by avg duration and SLA breach rate
--     NOTE: every derived table (subquery in FROM) needs an alias in MySQL — `AS market_stats` below.
SELECT market_id, orders, avg_duration_min, pct_over_60min,
  RANK() OVER (ORDER BY avg_duration_min DESC) AS duration_rank
FROM (
  SELECT market_id,
    COUNT(*) AS orders,
    ROUND(AVG(duration_min), 1) AS avg_duration_min,
    ROUND(100.0 * SUM(CASE WHEN duration_min > 60 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_over_60min
  FROM deliveries
  GROUP BY market_id
) AS market_stats;

-- 4b. Root-cause check for the worst market: is it dasher understaffing,
--     or driving distance? (compare busy_ratio and estimated driving time)
SELECT market_id,
  ROUND(AVG(total_busy_dashers / NULLIF(total_onshift_dashers, 0)), 2) AS avg_busy_ratio,
  ROUND(AVG(estimated_store_to_consumer_driving_duration) / 60.0, 1) AS avg_driving_min,
  ROUND(AVG(duration_min), 1) AS avg_total_min,
  ROUND(AVG(duration_min - estimated_store_to_consumer_driving_duration / 60.0), 1) AS avg_non_driving_min
FROM deliveries
WHERE valid_dasher_data = 1
GROUP BY market_id
ORDER BY avg_non_driving_min DESC;
-- NOTE: "non-driving minutes" = total time minus estimated drive time —
-- a proxy for order-prep + dispatch/assignment delay. See report §3.2.

-- ------------------------------------------------------------
-- 5. TIME PATTERNS
-- ------------------------------------------------------------

-- 5a. Duration and order volume by hour of day
SELECT HOUR(created_at) AS hr,
  COUNT(*) AS orders,
  ROUND(AVG(duration_min), 1) AS avg_duration_min
FROM deliveries
GROUP BY hr
ORDER BY hr;

-- ------------------------------------------------------------
-- 6. ORDER CHARACTERISTICS vs DURATION
-- ------------------------------------------------------------

-- 6a. Order size (item count) vs duration
SELECT
  CASE WHEN total_items = 1 THEN '1 item' WHEN total_items <= 3 THEN '2-3 items'
       WHEN total_items <= 6 THEN '4-6 items' ELSE '7+ items' END AS item_bucket,
  COUNT(*) AS orders,
  ROUND(AVG(duration_min), 1) AS avg_duration_min
FROM deliveries
GROUP BY item_bucket
ORDER BY avg_duration_min;

-- 6b. Duration by order protocol (order channel/integration code)
SELECT order_protocol, COUNT(*) AS orders, ROUND(AVG(duration_min), 1) AS avg_duration_min
FROM deliveries
GROUP BY order_protocol
ORDER BY avg_duration_min DESC;

-- ------------------------------------------------------------
-- 7. STORE-CATEGORY PERFORMANCE (window function: RANK, min-volume filter)
-- ------------------------------------------------------------

WITH cat_stats AS (
  SELECT store_primary_category,
    COUNT(*) AS orders,
    ROUND(AVG(duration_min), 1) AS avg_duration_min,
    ROUND(100.0 * SUM(CASE WHEN duration_min > 60 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_over_60min
  FROM deliveries
  GROUP BY store_primary_category
  HAVING COUNT(*) >= 1000        -- ignore categories too small to trust
)
SELECT *, RANK() OVER (ORDER BY pct_over_60min DESC) AS breach_rank
FROM cat_stats
ORDER BY breach_rank
LIMIT 10;
