-- ============================================================
-- PROJECT:  Station Operations Intelligence
-- AUTHOR:   Orleans Otoo
-- TOOL:     PostgreSQL 18 / PgAdmin 4
-- DATE:     May 2025
-- 
-- DESCRIPTION:
--   A SQL portfolio project analysing operational performance
--   at an Amazon Delivery Station. Built on synthetic data
--   modelled on real UTR (Under The Roof) operations.
--   Covers staffing efficiency, throughput bottlenecks,
--   missing parcel root causes, scan compliance, and
--   shift capacity modelling.
--
-- DATABASE:  UTR_bottlenecks
-- TABLES:    dim_shifts, dim_associates,
--            fact_position_throughput,
--            fact_packages, fact_scan_events
-- ============================================================


-- ============================================================
-- SCHEMA SETUP
-- ============================================================

-- Dimension table: one row per shift (6 months of data)
CREATE TABLE dim_shifts (
    shift_id          VARCHAR(10) PRIMARY KEY,
    shift_date        DATE,
    shift_type        VARCHAR(20),
    day_of_week       VARCHAR(15),
    belt_runtime_hrs  DECIMAL,
    break_hrs         DECIMAL,
    total_headcount   INT,
    planned_volume    INT,
    actual_volume     INT
);

-- Dimension table: one row per associate (50 workers)
CREATE TABLE dim_associates (
    associate_id      VARCHAR(10) PRIMARY KEY,
    associate_name    VARCHAR(50),
    tenure_months     INT,
    primary_position  VARCHAR(20),
    contract_type     VARCHAR(20)
);

-- Fact table: one row per associate per shift
CREATE TABLE fact_position_throughput (
    throughput_id     VARCHAR(12) PRIMARY KEY,
    shift_id          VARCHAR(10) REFERENCES dim_shifts(shift_id),
    associate_id      VARCHAR(10) REFERENCES dim_associates(associate_id),
    position_worked   VARCHAR(20),
    packages_handled  INT,
    hours_worked      DECIMAL
);

-- Fact table: one row per package (2-week sample: 3–15 Mar 2025)
CREATE TABLE fact_packages (
    package_id        VARCHAR(20) PRIMARY KEY,
    shift_id          VARCHAR(10) REFERENCES dim_shifts(shift_id),
    route_id          VARCHAR(10),
    stow_confirmed    BOOLEAN,
    van_loaded        BOOLEAN,
    delivered         BOOLEAN,
    pnov_flag         BOOLEAN,
    pnov_cause        VARCHAR(30)
);

-- Fact table: one row per scan event (~3 scans per package)
CREATE TABLE fact_scan_events (
    scan_id           VARCHAR(20) PRIMARY KEY,
    package_id        VARCHAR(20) REFERENCES fact_packages(package_id),
    associate_id      VARCHAR(10) REFERENCES dim_associates(associate_id),
    shift_id          VARCHAR(10) REFERENCES dim_shifts(shift_id),
    scan_type         VARCHAR(15),
    scan_timestamp    TIMESTAMP,
    mins_into_shift   INT,
    error_flag        BOOLEAN,
    error_type        VARCHAR(30)
);


-- ============================================================
-- Q1: STAFFING VS VOLUME
-- Are we staffing to actual volume or planned volume?
-- What does the gap cost us in labour?
-- ============================================================

-- 1a. Raw volume gap per shift
WITH shift_gaps AS (
    SELECT
        shift_id,
        shift_date,
        planned_volume,
        actual_volume,
        planned_volume - actual_volume AS volume_gap
    FROM dim_shifts
)
SELECT
    shift_id,
    shift_date,
    planned_volume,
    actual_volume,
    volume_gap
FROM shift_gaps;


-- 1b. Average volume gap by day of week
--     Negative = understaffed (more volume than planned)
--     Positive = overstaffed (less volume than planned)
SELECT
    day_of_week,
    ROUND(AVG(planned_volume - actual_volume), 3) AS avg_volume_gap
FROM dim_shifts
GROUP BY day_of_week
ORDER BY avg_volume_gap ASC;


-- 1c. Average volume gap by day of week AND shift type
SELECT
    day_of_week,
    shift_type,
    ROUND(AVG(planned_volume - actual_volume), 3) AS avg_volume_gap
FROM dim_shifts
GROUP BY day_of_week, shift_type
ORDER BY shift_type, day_of_week ASC;


-- 1d. Estimated labour waste per shift
--     Based on actual average throughput of 1,431 packages/worker/shift
--     (derived from fact_position_throughput in Q2)
--     Each worker costs approximately €90 per shift (€12/hr x 7.5hrs)
--     Waste only applies when planned_volume > actual_volume (overstaffed)
WITH shift_gaps AS (
    SELECT
        shift_id,
        shift_date,
        planned_volume,
        actual_volume,
        planned_volume - actual_volume AS volume_gap
    FROM dim_shifts
),
total_waste AS (
    SELECT
        shift_id,
        shift_date,
        volume_gap,
        CASE
            WHEN planned_volume > actual_volume
            THEN ROUND((volume_gap / 1431.0) * 90, 2)
            ELSE 0
        END AS estimated_labour_waste
    FROM shift_gaps
)
SELECT
    shift_id,
    shift_date,
    volume_gap,
    estimated_labour_waste
FROM total_waste
ORDER BY estimated_labour_waste DESC;


-- 1e. Total estimated labour waste across all 6 months
WITH shift_gaps AS (
    SELECT
        shift_id,
        shift_date,
        planned_volume,
        actual_volume,
        planned_volume - actual_volume AS volume_gap
    FROM dim_shifts
),
total_waste AS (
    SELECT
        shift_id,
        shift_date,
        volume_gap,
        CASE
            WHEN planned_volume > actual_volume
            THEN ROUND((volume_gap / 1431.0) * 90, 2)
            ELSE 0
        END AS estimated_labour_waste
    FROM shift_gaps
)
SELECT SUM(estimated_labour_waste) AS total_labour_waste_eur
FROM total_waste;
-- FINDING: €8,530.51 in estimated labour waste over 6 months


-- ============================================================
-- Q2: THROUGHPUT BOTTLENECK
-- Which position caps station output?
-- ============================================================

-- 2a. Average packages per person per shift by position
SELECT
    position_worked,
    ROUND(AVG(packages_handled), 0) AS avg_packages,
    SUM(packages_handled)           AS total_packages,
    COUNT(associate_id)             AS worker_count
FROM fact_position_throughput
GROUP BY position_worked
ORDER BY avg_packages ASC;
-- FINDING: Stowing is slowest at 1,056 pkgs/person vs Docking at 1,745


-- 2b. Throughput by position and shift type
--     Tests whether the bottleneck varies Early vs Late
SELECT
    dim_shifts.shift_type,
    position_worked,
    ROUND(AVG(packages_handled), 0) AS avg_packages
FROM fact_position_throughput
JOIN dim_shifts ON fact_position_throughput.shift_id = dim_shifts.shift_id
GROUP BY shift_type, position_worked
ORDER BY shift_type, avg_packages ASC;
-- FINDING: Bottleneck is consistent across both shift types — structural not scheduling


-- 2c. Throughput by position and day of week
--     Tests whether high volume days worsen the bottleneck
SELECT
    dim_shifts.shift_type,
    dim_shifts.day_of_week,
    position_worked,
    ROUND(AVG(packages_handled), 0) AS avg_packages
FROM fact_position_throughput
JOIN dim_shifts ON fact_position_throughput.shift_id = dim_shifts.shift_id
GROUP BY shift_type, day_of_week, position_worked
ORDER BY shift_type, day_of_week ASC, avg_packages ASC;
-- FINDING: Stowing drops to 1,050 on Monday Early — worst bottleneck under peak volume


-- ============================================================
-- Q3: PNOV ROOT CAUSE ANALYSIS
-- Is a missing parcel a warehouse failure or a driver failure?
-- ============================================================

-- 3a. Overall PNOV rate
WITH pnov_totals AS (
    SELECT
        COUNT(package_id) AS total_packages,
        SUM(CASE WHEN pnov_flag = TRUE THEN 1 ELSE 0 END) AS total_pnovs
    FROM fact_packages
)
SELECT
    total_packages,
    total_pnovs,
    ROUND((total_pnovs::DECIMAL / total_packages) * 100, 2) AS pnov_rate_pct
FROM pnov_totals;
-- FINDING: 2.80% PNOV rate — roughly 1 in every 36 packages


-- 3b. PNOV split by root cause (UTR vs OTR)
--     UTR failure = package never stowed or missed van load (warehouse fault)
--     OTR failure = driver had package but did not deliver (driver fault)
WITH pnov_counts AS (
    SELECT
        pnov_cause,
        COUNT(pnov_cause) AS cause_count
    FROM fact_packages
    WHERE pnov_flag = TRUE
    GROUP BY pnov_cause
)
SELECT
    pnov_cause,
    cause_count,
    ROUND((cause_count::DECIMAL / SUM(cause_count) OVER()) * 100, 2) AS pct_of_pnovs
FROM pnov_counts;
-- FINDING: 76.93% UTR failures vs 23.07% OTR failures
-- Most missing parcels originate inside the warehouse before the van leaves


-- 3c. Worst OTR routes — which routes have most driver-caused failures?
SELECT
    route_id,
    SUM(CASE WHEN van_loaded = TRUE AND delivered = FALSE THEN 1 ELSE 0 END) AS otr_failures
FROM fact_packages
GROUP BY route_id
ORDER BY otr_failures DESC;
-- FINDING: RT-022 and RT-004 worst with 9 OTR failures each over 2 weeks
-- Next step: cross-reference driver IDs to distinguish people vs route problems


-- ============================================================
-- Q4: SCAN ERROR ANALYSIS
-- Which associates have the highest error rate?
-- Does error rate spike at end of shift?
-- ============================================================

-- 4a. Error rate by associate (joined with contract type and tenure)
WITH sa_errors AS (
    SELECT
        associate_id,
        COUNT(scan_id)                                               AS total_scans,
        SUM(CASE WHEN error_flag = TRUE THEN 1 ELSE 0 END)          AS total_errors
    FROM fact_scan_events
    GROUP BY associate_id
)
SELECT
    sa_errors.associate_id,
    total_scans,
    total_errors,
    ROUND((total_errors::DECIMAL / total_scans) * 100, 2)           AS error_rate_pct,
    dim_associates.contract_type,
    dim_associates.tenure_months
FROM sa_errors
JOIN dim_associates ON dim_associates.associate_id = sa_errors.associate_id
ORDER BY error_rate_pct DESC;
-- FINDING: Top 4 highest error rate associates are all Agency workers under 9 months tenure
-- A-049 worst at 7.34% — nearly 4x the station average


-- 4b. Error rate by time of shift (fatigue analysis)
--     Buckets: every 90 minutes across the 7.5hr shift
WITH error_events AS (
    SELECT
        scan_id,
        error_flag,
        mins_into_shift,
        CASE
            WHEN mins_into_shift <= 90  THEN '0-90 mins'
            WHEN mins_into_shift <= 180 THEN '90-180 mins'
            WHEN mins_into_shift <= 270 THEN '180-270 mins'
            WHEN mins_into_shift <= 360 THEN '270-360 mins'
            WHEN mins_into_shift <= 450 THEN '360-450 mins'
        END AS time_bucket
    FROM fact_scan_events
),
error_scan_events AS (
    SELECT
        time_bucket,
        COUNT(scan_id)                                              AS scans_per_bucket,
        SUM(CASE WHEN error_flag = TRUE THEN 1 ELSE 0 END)         AS errors_per_bucket
    FROM error_events
    GROUP BY time_bucket
)
SELECT
    time_bucket,
    scans_per_bucket,
    errors_per_bucket,
    ROUND((errors_per_bucket::DECIMAL / scans_per_bucket) * 100, 2) AS error_rate_pct
FROM error_scan_events
ORDER BY
    CASE time_bucket
        WHEN '0-90 mins'   THEN 1
        WHEN '90-180 mins' THEN 2
        WHEN '180-270 mins'THEN 3
        WHEN '270-360 mins'THEN 4
        WHEN '360-450 mins'THEN 5
    END;
-- FINDING: Error rate climbs from 1.83% (start) to 8.31% (final 90 mins)
-- 4.5x increase across the shift — clear fatigue effect


-- ============================================================
-- Q5: SHIFT CAPACITY MODEL
-- What is the station ceiling per shift?
-- Which shifts are at risk of volume overload?
-- ============================================================

-- 5a. Full capacity model with shift status classification
WITH shift_capacities AS (
    -- Step 1: Calculate workers, throughput rate and hours per position per shift
    SELECT
        fact_position_throughput.shift_id,
        position_worked,
        COUNT(associate_id)              AS no_of_workers,
        ROUND(AVG(packages_handled), 0)  AS throughput_rate,
        ROUND(AVG(hours_worked), 0)      AS avg_hours_worked
    FROM fact_position_throughput
    GROUP BY shift_id, position_worked
),
position_capacity AS (
    -- Step 2: Calculate total capacity per position per shift
    SELECT
        shift_id,
        position_worked,
        (no_of_workers * throughput_rate * avg_hours_worked) AS total_capacity_per_position
    FROM shift_capacities
),
shift_vol_cap AS (
    -- Step 3: Find the station ceiling (minimum capacity position = bottleneck)
    --         Join to dim_shifts for volume and day context
    SELECT
        position_capacity.shift_id,
        planned_volume,
        actual_volume,
        day_of_week,
        shift_type,
        MIN(total_capacity_per_position) AS station_ceiling
    FROM position_capacity
    JOIN dim_shifts ON position_capacity.shift_id = dim_shifts.shift_id
    GROUP BY position_capacity.shift_id, planned_volume, actual_volume, day_of_week, shift_type
),
status_of_shifts AS (
    -- Step 4: Classify each shift by capacity status
    SELECT
        shift_id,
        planned_volume,
        actual_volume,
        station_ceiling,
        day_of_week,
        shift_type,
        CASE
            WHEN actual_volume > station_ceiling        THEN 'Over capacity'
            WHEN actual_volume > station_ceiling * 0.65 THEN 'At risk'
            ELSE                                             'Within capacity'
        END AS shift_status
    FROM shift_vol_cap
)
SELECT
    shift_status,
    day_of_week,
    shift_type,
    COUNT(*) AS number_of_shifts
FROM status_of_shifts
GROUP BY shift_status, day_of_week, shift_type
ORDER BY shift_status, day_of_week;
-- FINDING: 3 at-risk shifts identified
--          2 x Monday Early, 1 x Friday Early
--          Early shifts carry highest risk due to 65% volume allocation
--          combined with structural stowing bottleneck (Q2)


-- ============================================================
-- END OF PROJECT — Station Operations Intelligence
-- Orleans Otoo | May 2025
-- ============================================================
