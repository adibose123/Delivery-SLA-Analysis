"""
data_prep.py
------------
Loads the raw Porter/DoorDash-schema delivery CSV, does minimal documented
cleaning, and loads it into a MySQL database (see schema.sql for the table
definition) for SQL analysis in analysis.sql.

Usage:
    1. Create the schema first:  mysql -u root -p < schema.sql
    2. Set connection details via environment variables (or edit the
       defaults below), then run:  python data_prep.py

Env vars (all optional, defaults shown):
    MYSQL_HOST=localhost
    MYSQL_PORT=3306
    MYSQL_USER=root
    MYSQL_PASSWORD=
    MYSQL_DB=porter_delivery

Cleaning decisions (all kept, not silently dropped, so the analysis stays
transparent about data quality):
  - 21 rows have negative total_onshift_dashers (sensor/logging error,
    impossible in reality). Flagged via a `valid_dasher_data` column rather
    than deleted, so SQL queries about dasher supply can filter them out
    while everything else about the order stays usable.
  - 701 rows have min_item_price > max_item_price and 161 rows have
    subtotal <= 0 — left as-is (not corrupting the delivery-duration
    target variable), but noted in analysis.sql's data-quality section.
  - actual delivery duration (minutes) is computed here since it needs a
    timestamp subtraction; everything else (hour, day-of-week, buckets)
    is done in SQL (HOUR(), DATE_FORMAT(), etc.) in analysis.sql.
"""
import os
import pandas as pd
from pathlib import Path
from sqlalchemy import create_engine

SRC_CSV = Path(__file__).parent / "data" / "porter_data.csv"

MYSQL_HOST = os.environ.get("MYSQL_HOST", "localhost")
MYSQL_PORT = os.environ.get("MYSQL_PORT", "3306")
MYSQL_USER = os.environ.get("MYSQL_USER", "root")
MYSQL_PASSWORD = os.environ.get("MYSQL_PASSWORD", "")
MYSQL_DB = os.environ.get("MYSQL_DB", "porter_delivery")

df = pd.read_csv(SRC_CSV)

df["created_at"] = pd.to_datetime(df["created_at"])
df["actual_delivery_time"] = pd.to_datetime(df["actual_delivery_time"])
df["duration_min"] = (df["actual_delivery_time"] - df["created_at"]).dt.total_seconds() / 60

df["valid_dasher_data"] = ((df["total_onshift_dashers"] >= 0) & (df["total_busy_dashers"] >= 0)).astype(int)

engine = create_engine(
    f"mysql+pymysql://{MYSQL_USER}:{MYSQL_PASSWORD}@{MYSQL_HOST}:{MYSQL_PORT}/{MYSQL_DB}"
)

# schema.sql already created the table with proper types/indexes;
# append the data into it rather than letting pandas guess types.
df.to_sql("deliveries", engine, if_exists="append", index=False, chunksize=5000)

print(f"Loaded {len(df):,} rows into MySQL database '{MYSQL_DB}'.deliveries")
