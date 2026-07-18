# Porter Delivery Time — SQL Analytics Project

SQL analysis of 175,777 food-delivery orders to find out why deliveries run late, and what's actually driving it.

> **Dataset provenance note:** this dataset's schema is an exact match for the well-known DoorDash delivery-duration dataset, republished on Kaggle under the "Porter" name. The data is real operational data — treated as such throughout this analysis.

## The headline findings

- **8.14% of deliveries breach a 60-minute mark** (14,316 of 175,777 orders).
- **Dasher (driver) understaffing is the strongest lever found**: the SLA breach rate is roughly flat and low (~1–2%) as long as the driver pool has slack, then jumps to **12.6%** once zero dashers are on shift — an **11x spread**, with a clean threshold around 80% utilization.
- **One market (Market 1) is the slowest overall — and it isn't because of distance or driver shortage.** It has the *shortest* average drives of any market and a driver-utilization ratio no worse than two better-performing markets. The extra ~5 minutes happens before the driver even starts moving — pointing at prep/dispatch delay, not logistics.
- Order size and hour-of-day both add real, predictable variation — see [`INSIGHTS.md`](./INSIGHTS.md) for the full breakdown.

| SLA breach by driver utilization | Market 1 root-cause breakdown |
|---|---|
| ![SLA breach by dasher load](charts/chart_sla_by_dasher_load.png) | ![Market breakdown](charts/chart_market_breakdown.png) |

**Full write-up with all findings, business recommendations, and limitations: [`INSIGHTS.md`](./INSIGHTS.md)**

## Repo structure

```
.
├── README.md              <- you are here
├── INSIGHTS.md             <- full findings + business recommendations
├── schema.sql               <- MySQL CREATE DATABASE / CREATE TABLE
├── data_prep.py             <- loads raw CSV into MySQL, minimal cleaning
├── analysis.sql              <- all analysis: CTEs, window functions, joins
├── requirements.txt
├── charts/                   <- supporting charts (referenced in INSIGHTS.md)
└── data/                      <- place the raw CSV here (not committed, see below)
```

## Reproducing this analysis

Requires a running MySQL 8.0+ (or MariaDB 10.2+) server.

1. Download the dataset from Kaggle: [Porter Delivery Time Estimation Dataset](https://www.kaggle.com/datasets/ranitsarkar01/porter-delivery-time-estimation-dataset), and place `porter_data.csv` in `data/`.
   *(The raw CSV isn't committed to this repo — it's third-party data, ~15MB, and easy to re-download.)*
2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
3. Create the database and table:
   ```bash
   mysql -u root -p < schema.sql
   ```
4. Load the data (reads connection details from environment variables — defaults to `root`/no password on `localhost:3306`; override as needed):
   ```bash
   MYSQL_USER=root MYSQL_PASSWORD=yourpassword python data_prep.py
   ```
5. Run the analysis:
   ```bash
   mysql -u root -p porter_delivery < analysis.sql
   ```
   Or open it in any MySQL client (MySQL Workbench, DBeaver, TablePlus, etc.) and run it section by section — it's organized with numbered comment headers for exactly that.

Every query in `analysis.sql` was validated end-to-end against a real MySQL-compatible server (MariaDB 10.11) before being committed here — not just syntax-checked.

## What the SQL demonstrates

- Data-quality auditing (negative values, price-integrity violations, flagged not silently dropped)
- CTEs and subqueries for multi-step aggregation
- `RANK() OVER (ORDER BY ...)` window functions for market and store-category ranking
- A derived-metric root-cause query (isolating "non-driving time" to separate a distance problem from a dispatch problem)
- Threshold/bucket analysis (SLA breach rates by driver-utilization band, order-size band)

## Tech stack

Python (pandas, SQLAlchemy) for lightweight ETL → MySQL for all analysis → matplotlib for charts.

## Limitations

- ~4 weeks of data — enough for hour-of-day and category patterns, not real week-over-week trend analysis.
- `order_protocol` is an uninterpreted numeric code (no lookup table), so that finding is descriptive, not yet actionable.
- The "non-driving time" root-cause metric is a derived proxy (total time minus estimated driving time), not a directly measured prep/dispatch field.

Full details in [`INSIGHTS.md`](./INSIGHTS.md#5-limitations).

## License

Code in this repo (`data_prep.py`, `analysis.sql`) is MIT licensed — see [`LICENSE`](./LICENSE). The dataset itself is third-party (Kaggle/DoorDash-origin data) and not covered by this license; see the dataset's Kaggle page for its terms.
