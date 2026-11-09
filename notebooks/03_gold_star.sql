-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 03 — Gold: star schema
-- MAGIC
-- MAGIC `fact_collision` grain = one collision occurrence (`_id`).
-- MAGIC Unknown members use key `0` so referential-integrity checks are meaningful.

-- COMMAND ----------

USE CATALOG workspace;
USE SCHEMA collisions_gold;

-- COMMAND ----------

CREATE OR REPLACE TABLE dim_date AS
WITH bounds AS (
  SELECT min(occ_date) AS min_d, max(occ_date) AS max_d
  FROM workspace.collisions_silver.collisions_clean
),
spine AS (
  SELECT explode(sequence(min_d, max_d, interval 1 day)) AS d FROM bounds
)
SELECT
  cast(date_format(d, 'yyyyMMdd') AS INT) AS date_key,
  d                                       AS date,
  year(d)                                 AS year,
  month(d)                                AS month,
  date_format(d, 'MMMM')                  AS month_name,
  dayofweek(d)                            AS day_of_week,   -- 1 = Sunday
  date_format(d, 'EEEE')                  AS day_name,
  dayofweek(d) IN (1, 7)                  AS is_weekend,
  CASE
    WHEN month(d) IN (12, 1, 2) THEN 'Winter'
    WHEN month(d) IN (3, 4, 5)  THEN 'Spring'
    WHEN month(d) IN (6, 7, 8)  THEN 'Summer'
    ELSE 'Fall'
  END                                     AS season
FROM spine;

-- COMMAND ----------

CREATE OR REPLACE TABLE dim_division AS
SELECT 0 AS division_key, 'UNKNOWN' AS division
UNION ALL
SELECT abs(xxhash64(division)) AS division_key, division
FROM (
  SELECT DISTINCT division
  FROM workspace.collisions_silver.collisions_clean
  WHERE division IS NOT NULL
);

-- COMMAND ----------

CREATE OR REPLACE TABLE dim_neighbourhood AS
SELECT 0 AS neighbourhood_key, 'UNKNOWN' AS neighbourhood_code, 'UNKNOWN' AS neighbourhood
UNION ALL
SELECT
  abs(xxhash64(neighbourhood_code)) AS neighbourhood_key,
  neighbourhood_code,
  neighbourhood
FROM (
  -- one row per code so the fact join cannot fan out on name variants
  SELECT neighbourhood_code, max(neighbourhood) AS neighbourhood
  FROM workspace.collisions_silver.collisions_clean
  WHERE neighbourhood_code IS NOT NULL
  GROUP BY neighbourhood_code
);

-- COMMAND ----------

CREATE OR REPLACE TABLE dim_location AS
SELECT 0 AS location_key, cast(NULL AS DOUBLE) AS lat, cast(NULL AS DOUBLE) AS long, 'UNKNOWN' AS location_label
UNION ALL
SELECT
  abs(xxhash64(concat(cast(lat AS STRING), ',', cast(long AS STRING)))) AS location_key,
  lat,
  long,
  concat(cast(lat AS STRING), ', ', cast(long AS STRING)) AS location_label
FROM (
  SELECT DISTINCT round(lat, 4) AS lat, round(long, 4) AS long
  FROM workspace.collisions_silver.collisions_clean
  WHERE lat IS NOT NULL AND long IS NOT NULL
);

-- COMMAND ----------

CREATE OR REPLACE TABLE fact_collision AS
SELECT
  s._id                                     AS collision_id,
  cast(date_format(s.occ_date, 'yyyyMMdd') AS INT) AS date_key,
  coalesce(d.division_key, 0)               AS division_key,
  coalesce(n.neighbourhood_key, 0)          AS neighbourhood_key,
  coalesce(l.location_key, 0)               AS location_key,
  s.hour,
  s.fatalities,
  s.fatalities > 0                          AS is_fatal,
  coalesce(s.is_injury, false)              AS is_injury,
  coalesce(s.is_ftr, false)                 AS is_ftr,
  coalesce(s.is_pd, false)                  AS is_pd,
  cast(coalesce(s.is_injury, false) AS INT)
    + cast(coalesce(s.is_ftr, false) AS INT)
    + cast(coalesce(s.is_pd, false) AS INT) AS collision_type_count,
  s.is_geocoded,
  s.involved_automobile,
  s.involved_motorcycle,
  s.involved_passenger,
  s.involved_bicycle,
  s.involved_pedestrian
FROM workspace.collisions_silver.collisions_clean s
LEFT JOIN dim_division d      ON s.division = d.division AND d.division_key <> 0
LEFT JOIN dim_neighbourhood n ON s.neighbourhood_code = n.neighbourhood_code AND n.neighbourhood_key <> 0
LEFT JOIN dim_location l      ON round(s.lat, 4) = l.lat AND round(s.long, 4) = l.long AND l.location_key <> 0;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Long format for road-user analysis (pedestrian / cyclist share of KSI).

CREATE OR REPLACE TABLE bridge_collision_road_user AS
SELECT collision_id, 'Automobile' AS road_user FROM fact_collision WHERE involved_automobile
UNION ALL
SELECT collision_id, 'Motorcycle' FROM fact_collision WHERE involved_motorcycle
UNION ALL
SELECT collision_id, 'Passenger'  FROM fact_collision WHERE involved_passenger
UNION ALL
SELECT collision_id, 'Bicycle'    FROM fact_collision WHERE involved_bicycle
UNION ALL
SELECT collision_id, 'Pedestrian' FROM fact_collision WHERE involved_pedestrian;

-- COMMAND ----------

SELECT
  (SELECT COUNT(*) FROM fact_collision) AS fact_rows,
  (SELECT COUNT(*) FROM dim_date)       AS dates,
  (SELECT COUNT(*) FROM dim_division)   AS divisions,
  (SELECT COUNT(*) FROM dim_neighbourhood) AS neighbourhoods,
  (SELECT COUNT(*) FROM dim_location)   AS locations,
  (SELECT COUNT(*) FROM bridge_collision_road_user) AS road_user_rows;
