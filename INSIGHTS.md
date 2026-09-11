# Porter Delivery Time — SQL Analytics Project

**Dataset:** Kaggle — Porter Delivery Time Estimation Dataset (175,777 orders, ~4 weeks, Jan–Feb 2015)
**Tools:** Python (light ETL) → MySQL (all analysis) → matplotlib (charts)
**Files:** `data_prep.py`, `schema.sql`, `analysis.sql`, this report

*Note on provenance: this dataset's schema is an exact match for the well-known DoorDash delivery-duration take-home dataset, republished on Kaggle under the Porter name. The data itself is real operational data — the analysis below treats it as such.*

---

## Executive Summary

- **175,777 deliveries**, averaging **46.2 minutes**, with **8.14% breaching a 60-minute mark** (14,316 orders).
- **Dasher understaffing is the clearest driver of slow deliveries found in the data**: SLA breach rate climbs from **1.1%** when the dasher pool is under 50% busy to **12.6%** when there are zero dashers on shift — an 11x spread.
- **Market 1 is the worst-performing market (49.1 min avg, 12.1% breach)** — and the cause isn't distance (it has the *shortest* average drives of any market) or dasher-pool busyness (similar ratio to two better-performing markets). The extra ~5 minutes is happening before the driver even starts moving — a prep/dispatch delay, not a logistics one.
- Demand is heavily **late-night skewed** — order volume is near zero from 9am–1pm and peaks around 2–3am, where durations are also at their slowest.
- Order size predictably slows delivery: **43.0 min for single-item orders vs 52.0 min for 7+ items.**

---

## 1. Business Problem

For a delivery platform, average delivery time isn't the number that matters most — the tail is. Customers churn over late deliveries, not slightly-slow-on-average ones. This project uses SQL to quantify how often deliveries breach a reasonable time threshold, find what's actually driving the breaches, and separate what's fixable (staffing, dispatch) from what isn't (order size, geography).

## 2. Dataset & Methodology

Raw CSV: 175,777 rows — order timestamps, market/store/category codes, order size and price, live dasher supply/demand counts, and estimated driving duration.

- **`data_prep.py`** — computes `duration_min` (the target variable) from the two timestamp columns, and flags 41 rows with physically-impossible negative dasher counts (`valid_dasher_data`) rather than deleting them, so they can be excluded only from supply-side analysis without losing the rest of the row.
- **`analysis.sql`** — all business logic: data-quality checks, SLA-breach calculation, dasher-load bucketing, a market root-cause breakdown (driving vs non-driving time), hour-of-day patterns, and two `RANK() OVER (...)` window-function queries (market ranking, store-category ranking with a minimum-volume filter to avoid small-sample noise).

## 3. Key Findings

### 3.1 Dasher understaffing is the strongest lever in the data

![SLA breach by dasher load](charts/chart_sla_by_dasher_load.png)

| Dasher pool load | Orders | Avg duration | % over 60 min |
|---|---|---|---|
| No dashers on shift | 3,538 | 51.1 min | **12.6%** |
| 100–150% busy | 65,148 | 48.0 min | 10.3% |
| 80–100% busy | 64,819 | 46.8 min | 9.8% |
| 150%+ busy | 5,436 | 41.8 min | 2.9% |
| 50–80% busy | 31,434 | 42.2 min | 1.8% |
| <50% busy | 5,361 | 41.6 min | **1.1%** |

The breach rate is roughly flat and low (~1–2%) while the dasher pool has slack (under 80% busy), then jumps to 9.8–10.3% once the pool is fully or over-utilized (80–150% busy), and is worst of all (12.6%) when there are literally zero dashers on shift. One caveat worth flagging rather than smoothing over: the 150%+ bucket (5,436 orders, ~3% of the data) breaks the pattern, dropping back down to a 2.9% breach rate. That's most likely because an extreme ratio like 200% busy usually comes from a market with only 1–2 dashers on shift in the first place — a noisy small-sample reading rather than a real capacity signal. So the actionable threshold is the 80–150% band plus zero-dasher shifts; the 150%+ segment isn't reliable enough to draw a conclusion from either way.

### 3.2 Market 1's problem isn't distance or dasher ratio — it's something upstream of the drive

![Market breakdown: driving vs non-driving time](charts/chart_market_breakdown.png)

| Market | Avg busy ratio | Avg driving time | Avg total time | Avg non-driving time* |
|---|---|---|---|---|
| **1** | 0.97 | **8.7 min (shortest)** | **49.1 min (slowest)** | **40.5 min** |
| 6 | 0.95 | 9.3 min | 47.0 min | 37.8 min |
| 4 | 0.97 | 9.1 min | 46.8 min | 37.7 min |
| 5 | 0.86 | 9.1 min | 45.0 min | 35.9 min |
| 2 | 0.97 | 9.4 min | 44.9 min | 35.4 min |
| 3 | 0.90 | 9.0 min | 44.1 min | 35.1 min |

*\*total time minus estimated driving time — a proxy for order prep + dispatch/assignment delay.*

Market 1 has the **shortest** average drive of any market, and a dasher busy-ratio (0.97) that's no worse than Markets 2 and 4 — yet it's the slowest market overall by nearly 5 minutes. Since neither distance nor dasher-pool utilization explains it, the delay is concentrated in the part of the process before the driver starts moving: order prep at the store, or the time between order placed and a dasher being assigned. This dataset can't isolate which one — that's the right next question to take to Market 1's ops team, not something to guess at from here.

### 3.3 Demand — and slowness — both cluster overnight

![Hourly pattern](charts/chart_hourly_pattern.png)

Order volume is negligible from 9am–1pm (a handful of orders total) and peaks between 1–3am. Durations track the same shape — slowest overnight (~50 min around 2–3am), fastest in the early evening (~40 min around 9pm). This reads as a market genuinely built around late-night demand (bars, campuses, night-shift workers) rather than a typical lunch/dinner delivery business — worth keeping in mind before applying any "add staff at dinner rush" assumption from a more typical food-delivery context.

### 3.4 Order size and category both add predictable, real variation

- **Order size:** 43.0 min (1 item) → 45.4 min (2–3) → 48.7 min (4–6) → 52.0 min (7+) — a clean, monotonic relationship. Reasonable to build size-adjusted SLA targets rather than one flat number.
- **Store category:** among categories with enough volume to trust (1,000+ orders), the 10 worst-performing categories range from **10.0% to 17.8%** breach — see the ranked list in `analysis.sql` §7, useful for category-specific ops attention rather than a blanket policy.

### 3.5 Data quality, documented not hidden

- 41 rows have negative dasher counts (sensor/logging error, in either `total_onshift_dashers` or `total_busy_dashers`) — flagged, excluded only from dasher-supply analysis.
- 701 rows have `min_item_price > max_item_price` and 161 have `subtotal <= 0` — likely promo/refund pricing artifacts; left in place since they don't affect the duration target, but worth a source-system check before this data feeds anything financial.

## 4. Recommendations

1. **Set a dasher-utilization alert threshold, not just a headcount target.** The breach-rate jump happens specifically once the pool crosses ~80% busy — that's a clean trigger point for surge staffing or dasher incentives, more precise than a flat "add more dashers" instruction.
2. **Investigate Market 1's pre-drive delay specifically.** Since the data rules out distance and dasher-ratio as causes, the fix is operational (store prep time, dispatch/assignment logic) — worth a targeted ops audit rather than a market-wide staffing increase, which wouldn't address a bottleneck that isn't about driver supply.
3. **Build size-adjusted SLA targets.** A flat "60 minutes" target penalizes large orders unfairly and under-challenges small ones — use the four-bucket breakdown in §3.4 as a starting point.
4. **Confirm the late-night-skewed markets are being staffed for their actual demand curve**, not a generic dinner-rush assumption — the data suggests this platform's peak isn't 6–8pm, it's after midnight.
5. **Flag the pricing/subtotal anomalies (§3.5) to the source system owner** — 862 affected rows is small relative to 175,777, but worth confirming before this data is used for anything revenue-related.

## 5. Limitations

- ~4 weeks of data (Jan 21 – Feb 18, 2015) — enough for hour-of-day and category patterns, not enough for a real week-over-week or seasonal trend.
- `order_protocol` is an uninterpreted numeric code — real variation exists across it (41.9–47.8 min), but without a lookup table for what each code means (app vs phone vs partner API, etc.), that finding is descriptive, not yet actionable.
- The "non-driving time" figure in §3.2 is a derived proxy (total time minus estimated driving time), not a directly measured prep/dispatch field — good for pointing at the right question, not a substitute for real prep-time instrumentation.

## 6. Files in This Project

| File | Purpose |
|---|---|
| `data_prep.py` | Loads raw CSV, computes delivery duration, flags bad dasher-count rows, loads into MySQL |
| `analysis.sql` | All SQL: data quality, SLA-breach analysis, dasher-load buckets, market root-cause breakdown, hourly patterns, window-function rankings |
| `schema.sql` | MySQL `CREATE DATABASE` / `CREATE TABLE` definition |
| `chart_*.png` | Supporting charts referenced above |
