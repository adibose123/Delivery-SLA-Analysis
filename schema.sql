-- ============================================================
-- schema.sql — MySQL schema for the Porter delivery dataset
-- ============================================================

CREATE DATABASE IF NOT EXISTS porter_delivery;
USE porter_delivery;

DROP TABLE IF EXISTS deliveries;

CREATE TABLE deliveries (
  market_id                                      INT,
  created_at                                      DATETIME,
  actual_delivery_time                            DATETIME,
  store_primary_category                          INT,
  order_protocol                                  INT,
  total_items                                     INT,
  subtotal                                        INT,          -- cents
  num_distinct_items                              INT,
  min_item_price                                  INT,
  max_item_price                                  INT,
  total_onshift_dashers                           INT,
  total_busy_dashers                              INT,
  total_outstanding_orders                        INT,
  estimated_store_to_consumer_driving_duration    INT,          -- seconds
  duration_min                                    DECIMAL(10,2),-- computed in data_prep.py
  valid_dasher_data                               TINYINT(1),   -- 0/1 flag, see data_prep.py
  INDEX idx_market (market_id),
  INDEX idx_category (store_primary_category)
);
