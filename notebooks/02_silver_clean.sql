-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 02 — Silver: type, clean, quarantine
-- MAGIC
-- MAGIC ## The one non-obvious fact
-- MAGIC `OCC_DATE` is **epoch milliseconds at local midnight** (e.g. `1625371200000`
-- MAGIC = 2021-07-04 00:00 America/Toronto). `try_to_timestamp()` returns NULL for
-- MAGIC it, so it must go through `timestamp_millis()` and be shifted to Toronto
-- MAGIC time. The time of day lives only in `OCC_HOUR`.
-- MAGIC
-- MAGIC Outputs:
-- MAGIC * `stg_collisions` — full parsed/flagged staging (debug + audit)
-- MAGIC * `collisions_clean` — rows that pass critical checks
-- MAGIC * `collisions_rejected` — critical failures with a reason, never silently dropped
-- MAGIC
-- MAGIC A row is only rejected for something that makes it unusable (no id, no
-- MAGIC timestamp, impossible year, negative fatalities). Bad coordinates are
-- MAGIC nulled and flagged, because the incident itself is still real.

-- COMMAND ----------

USE CATALOG workspace;
USE SCHEMA collisions_silver;

CREATE TABLE IF NOT EXISTS collisions_rejected (
  _id           STRING,
  occ_date_raw  STRING,
  reason        STRING,
  _ingested_at  TIMESTAMP
) USING DELTA;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Staging: parse everything, judge nothing yet

-- COMMAND ----------

CREATE OR REPLACE TABLE stg_collisions AS
WITH deduped AS (
  SELECT
    *,
    row_number() OVER (
      PARTITION BY _id
      ORDER BY _ingested_at DESC, _row_hash DESC
    ) AS _rn
  FROM workspace.collisions_bronze.collisions_raw
),
src AS (
  -- null ids form one partition under PARTITION BY, so keep them all for quarantine
  SELECT * FROM deduped WHERE _id IS NULL OR _rn = 1
),
ts AS (
  SELECT
    *,
    CASE
      WHEN trim(OCC_DATE) RLIKE '^[0-9]{13}$'
        THEN from_utc_timestamp(timestamp_millis(try_cast(trim(OCC_DATE) AS BIGINT)), 'America/Toronto')
      WHEN trim(OCC_DATE) RLIKE '^[0-9]{10}$'
        THEN from_utc_timestamp(timestamp_millis(try_cast(trim(OCC_DATE) AS BIGINT) * 1000), 'America/Toronto')
      ELSE coalesce(
        try_to_timestamp(OCC_DATE),
        try_to_timestamp(OCC_DATE, 'yyyy-MM-dd HH:mm:ss'),
        try_to_timestamp(OCC_DATE, 'yyyy-MM-dd''T''HH:mm:ss'),
        try_to_timestamp(OCC_DATE, 'M/d/yyyy H:mm:ss'),
        try_to_timestamp(OCC_DATE, 'M/d/yyyy h:mm:ss a')
      )
    END AS occ_ts
  FROM src
),
typed AS (
  SELECT
    _id,
    _ingested_at,
    occ_ts,
    OCC_DATE                        AS occ_date_raw,
    upper(trim(OCC_DOW))            AS source_dow,
    try_cast(OCC_YEAR AS INT)       AS source_year,
    OCC_MONTH                       AS source_month,
    to_date(occ_ts)                 AS occ_date,
    year(occ_ts)                    AS year,
    month(occ_ts)                   AS month,
    date_format(occ_ts, 'MMMM')     AS month_name,
    dayofweek(occ_ts)               AS day_of_week,   -- 1 = Sunday .. 7 = Saturday
    date_format(occ_ts, 'EEEE')     AS day_name,
    -- OCC_DATE carries no time of day, so an invalid OCC_HOUR is unknown, not repairable
    CASE
      WHEN try_cast(OCC_HOUR AS INT) BETWEEN 0 AND 23
        THEN try_cast(OCC_HOUR AS INT)
    END                             AS hour,
    -- 'NSA' = no set address; '' is an empty cell, not a real division/neighbourhood
    CASE WHEN upper(trim(DIVISION)) IN ('', 'NSA') THEN NULL
         ELSE upper(trim(DIVISION)) END                    AS division,
    CASE WHEN upper(trim(HOOD_158)) IN ('', 'NSA') THEN NULL
         ELSE trim(HOOD_158) END                           AS neighbourhood_code,
    CASE WHEN upper(trim(HOOD_158)) IN ('', 'NSA') THEN NULL
         ELSE trim(NEIGHBOURHOOD_158) END                  AS neighbourhood,
    greatest(coalesce(try_cast(FATALITIES AS INT), 0), 0)  AS fatalities,
    CASE
      WHEN upper(trim(INJURY_COLLISIONS)) IN ('Y','YES','TRUE','1') THEN true
      WHEN upper(trim(INJURY_COLLISIONS)) IN ('N','NO','FALSE','0') THEN false
    END                             AS is_injury,
    CASE
      WHEN upper(trim(FTR_COLLISIONS)) IN ('Y','YES','TRUE','1') THEN true
      WHEN upper(trim(FTR_COLLISIONS)) IN ('N','NO','FALSE','0') THEN false
    END                             AS is_ftr,
    CASE
      WHEN upper(trim(PD_COLLISIONS)) IN ('Y','YES','TRUE','1') THEN true
      WHEN upper(trim(PD_COLLISIONS)) IN ('N','NO','FALSE','0') THEN false
    END                             AS is_pd,
    try_cast(LAT_WGS84  AS DOUBLE)  AS lat_raw,
    try_cast(LONG_WGS84 AS DOUBLE)  AS long_raw,
    coalesce(upper(trim(AUTOMOBILE)) IN ('Y','YES','TRUE','1'), false) AS involved_automobile,
    coalesce(upper(trim(MOTORCYCLE)) IN ('Y','YES','TRUE','1'), false) AS involved_motorcycle,
    coalesce(upper(trim(PASSENGER))  IN ('Y','YES','TRUE','1'), false) AS involved_passenger,
    coalesce(upper(trim(BICYCLE))    IN ('Y','YES','TRUE','1'), false) AS involved_bicycle,
    coalesce(upper(trim(PEDESTRIAN)) IN ('Y','YES','TRUE','1'), false) AS involved_pedestrian,
    try_cast(FATALITIES AS INT)     AS fatalities_raw,
    try_cast(OCC_HOUR AS INT)       AS hour_raw
  FROM ts
),
flags AS (
  SELECT
    *,
    -- 0/0 is how this dataset encodes "not geocoded", so the bbox test is essential
    CASE
      WHEN lat_raw IS NOT NULL AND long_raw IS NOT NULL
       AND lat_raw  BETWEEN 43.58 AND 43.86
       AND long_raw BETWEEN -79.64 AND -79.12
      THEN lat_raw
    END AS lat,
    CASE
      WHEN lat_raw IS NOT NULL AND long_raw IS NOT NULL
       AND lat_raw  BETWEEN 43.58 AND 43.86
       AND long_raw BETWEEN -79.64 AND -79.12
      THEN long_raw
    END AS long
  FROM typed
),
judged AS (
  SELECT
    *,
    CASE
      WHEN _id IS NULL                    THEN 'missing_id'
      WHEN occ_ts IS NULL                 THEN 'unparseable_timestamp'
      WHEN year NOT BETWEEN 2014 AND 2026 THEN 'year_out_of_range'
      WHEN fatalities_raw < 0             THEN 'negative_fatalities'
      ELSE NULL
    END AS reject_reason
  FROM flags
)
SELECT
  _id, occ_date_raw, occ_ts, occ_date, year, month, month_name,
  day_of_week, day_name, hour, division,
  neighbourhood_code, neighbourhood, fatalities,
  is_injury, is_ftr, is_pd,
  lat, long, (lat IS NOT NULL) AS is_geocoded,
  involved_automobile, involved_motorcycle, involved_passenger,
  involved_bicycle, involved_pedestrian,
  source_dow, source_year, source_month, hour_raw,
  reject_reason,
  concat_ws(';',
    CASE WHEN lat_raw <> 0 AND lat IS NULL THEN 'invalid_coords' END,
    CASE WHEN lat_raw = 0 OR lat_raw IS NULL THEN 'missing_coords' END,
    CASE WHEN (lat_raw IS NULL) <> (long_raw IS NULL) THEN 'unpaired_coords' END,
    CASE WHEN hour_raw IS NULL OR hour_raw NOT BETWEEN 0 AND 23 THEN 'hour_missing' END,
    CASE WHEN NOT (coalesce(is_injury,false) OR coalesce(is_ftr,false) OR coalesce(is_pd,false))
         THEN 'no_collision_type' END
  ) AS dq_flags,
  _ingested_at
FROM judged;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Clean layer

-- COMMAND ----------

CREATE OR REPLACE TABLE collisions_clean AS
SELECT
  _id, occ_date_raw, occ_date, year, month, month_name,
  day_of_week, day_name, hour, division,
  neighbourhood_code, neighbourhood, fatalities,
  is_injury, is_ftr, is_pd,
  lat, long, is_geocoded,
  involved_automobile, involved_motorcycle, involved_passenger,
  involved_bicycle, involved_pedestrian,
  source_dow, source_year, source_month, hour_raw, dq_flags, _ingested_at
FROM stg_collisions
WHERE reject_reason IS NULL;

-- COMMAND ----------

INSERT OVERWRITE collisions_rejected
SELECT _id, occ_date_raw, reject_reason, _ingested_at
FROM stg_collisions
WHERE reject_reason IS NOT NULL;

-- COMMAND ----------

SELECT
  (SELECT COUNT(*) FROM stg_collisions)      AS staged,
  (SELECT COUNT(*) FROM collisions_clean)    AS clean,
  (SELECT COUNT(*) FROM collisions_rejected) AS rejected,
  round(100 * (SELECT COUNT(*) FROM collisions_rejected)
        / nullif((SELECT COUNT(*) FROM stg_collisions), 0), 2) AS reject_pct,
  round(100 * (SELECT COUNT(*) FROM collisions_clean WHERE is_geocoded)
        / nullif((SELECT COUNT(*) FROM collisions_clean), 0), 2) AS geocoded_pct;
