# Station Operations Intelligence
**SQL Portfolio Project | Orleans Otoo | May 2025**

---

## Project Overview

As an Operations Manager at an Amazon Delivery Station, I led a team of 2 managers and 50+ associates across a high-volume last-mile logistics operation. This project translates that operational experience into a structured data analysis — using SQL to answer five business questions that directly impact station efficiency, cost, and delivery performance.

The goal: demonstrate that operational knowledge combined with analytical skills can drive strategic decisions — not just describe what happened, but diagnose why and recommend what to change.

---

## Tools & Technologies

- **PostgreSQL 18** — database and all analytical queries
- **PgAdmin 4** — query development and database management
- **Python** — synthetic data generation
- **Power BI** — dashboard visualisation *(in progress)*

---

## Database Schema

Five tables across two layers:

**Dimension tables** (reference data)
- `dim_shifts` — 310 shifts across 6 months (Nov 2024 – Apr 2025), Mon–Sat, Early and Late shifts
- `dim_associates` — 50 workers across 5 positions with tenure and contract type

**Fact tables** (operational data)
- `fact_position_throughput` — packages handled per associate per shift (7,896 rows)
- `fact_packages` — package-level delivery outcomes including PNOV flags (24,475 rows, 2-week sample)
- `fact_scan_events` — individual scan events with timestamps and error flags (73,425 rows)

> Package and scan data covers a representative 2-week sample period (3–15 March 2025) to balance analytical depth with data manageability.

---

## The Five Business Questions

### Q1 — Staffing vs Volume
*Are we staffing to actual volume or planned volume — and what does the gap cost us?*

- Calculated volume gap (planned vs actual) per shift
- Segmented by day of week and shift type
- Estimated labour waste using actual throughput benchmarks derived from the data

**Key finding:** Monday Early shifts average 611 packages more than forecast — the largest understaffing gap. Total estimated labour waste from overstaffing across 6 months: **€8,530**. Tuesday is the only day where forecast and actual volume align reliably.

---

### Q2 — Throughput Bottleneck
*Which position caps station output — and does it get worse under pressure?*

- Calculated average packages per person per shift across all 5 positions
- Compared throughput across Early vs Late shifts and by day of week

**Key finding:** Stowing is the station's consistent throughput ceiling at **1,056 packages/person/shift** versus Docking at 1,745. The gap is structural — driven by task complexity (sorting individual packages into route-specific bags across multiple lanes) rather than staffing levels. The bottleneck worsens on Monday Early shifts, dropping to 1,050 — confirming volume pressure disproportionately impacts the weakest node in the pipeline.

---

### Q3 — PNOV Root Cause Analysis
*Is a missing parcel a warehouse failure or a driver failure?*

- Calculated overall PNOV rate across the 2-week sample
- Split PNOVs by root cause using the package scan journey
- Identified worst-performing OTR routes

**Key finding:** Overall PNOV rate is **2.80%** (roughly 1 in 36 packages). Of all missing parcels, **76.93% are UTR failures** — originating inside the warehouse before the van departs. Only 23.07% are OTR failures attributable to drivers. Routes RT-022 and RT-004 recorded the highest driver-side failures (9 each). Next investigative step: cross-reference driver IDs to distinguish people problems from route problems.

---

### Q4 — Scan Error Analysis
*Which associates have the highest scan error rate — and does fatigue drive errors late in the shift?*

- Profiled error rate by associate, contract type, and tenure
- Segmented error rate into 90-minute buckets across the full shift

**Key finding:** Scan error rate increases **4.5x across the shift** — from 1.83% in the first 90 minutes to 8.31% in the final 90 minutes. The four highest individual error rates belong exclusively to Agency workers with under 9 months tenure. Recommended interventions: rotate associates away from scanning positions after 270 minutes; prioritise experienced Full-time workers for high-scan positions during peak volume periods.

---

### Q5 — Shift Capacity Model
*What is the station's throughput ceiling — and which shifts are at risk of volume overload?*

- Built a multi-stage capacity model using a 4-CTE chain
- Calculated station ceiling per shift as the minimum capacity across all positions
- Classified shifts as Within Capacity, At Risk, or Over Capacity

**Key finding:** Of 310 shifts analysed, **3 were classified as At Risk** — 2 Monday Early shifts and 1 Friday Early shift. Early shifts carry the highest operational risk due to their 65% volume allocation combined with the structural stowing bottleneck identified in Q2. No shifts breached full capacity, but at-risk shifts represent priority periods for proactive staffing decisions.

---

## Key Analytical Techniques Used

- Common Table Expressions (CTEs) — including chained multi-step CTEs
- Window functions (`SUM() OVER()`) for percentage calculations without collapsing rows
- `CASE WHEN` for derived classifications and conditional aggregations
- Multi-table JOINs across fact and dimension tables
- Aggregate functions: `COUNT`, `SUM`, `AVG`, `MIN`, `ROUND`
- Integer division casting (`::DECIMAL`) for accurate percentage results
- Custom `ORDER BY` with `CASE WHEN` for non-alphabetical sorting

---

## Strategic Recommendations

Based on the combined findings across all five questions:

1. **Improve volume forecasting** — Monday and Thursday Early shifts consistently exceed forecast by 400–600 packages. A simple 7-day rolling average forecast would reduce staffing gaps and recover an estimated €8,500+ annually in labour waste.

2. **Optimise stowing lane design** — The stowing bottleneck is structural. Bag pre-positioning and reduced lateral movement per stower could increase throughput rate by an estimated 10–15% without adding headcount.

3. **Shift UTR accountability for PNOVs** — 77% of missing parcels are warehouse-originated. Current escalation processes treat all PNOVs equally. Separating UTR and OTR failure tracking enables targeted intervention and accurate accountability.

4. **Introduce associate rotation at the 270-minute mark** — Scan error rates triple in the final 90 minutes of a shift. Rotating scan-intensive roles at 4.5 hours could reduce end-of-shift errors by an estimated 20%, directly lowering PNOV rates.

5. **Flag at-risk shifts proactively** — Monday and Friday Early shifts should trigger automatic staffing reviews when forecast volume exceeds 85% of the modelled capacity ceiling.

---

## About This Project

The dataset used in this project is synthetic, generated using Python based on operational benchmarks from real delivery station experience. All associate names are anonymised. Volume figures, throughput rates, PNOV rates, and error rates are modelled to reflect realistic operational patterns.

---

*Orleans Otoo | Operations Manager → Strategy | May 2025*
