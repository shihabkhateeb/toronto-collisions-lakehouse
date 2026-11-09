-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 04 — Data quality checks
-- MAGIC
-- MAGIC Run **after 03**, because two checks read the gold tables.
-- MAGIC
-- MAGIC Two kinds of check, deliberately:
-- MAGIC * `error` — the data is wrong or empty; the pipeline must not publish.
-- MAGIC * `warn` — a metric about messy input that is expected to be non-zero.
-- MAGIC
-- MAGIC Always-zero structural checks (unique id, month range, …) were removed: they
-- MAGIC test the code, not the data.

-- COMMAND ----------

USE CATALOG workspace;
USE SCHEMA collisions_silver;

CREATE OR REPLACE TABLE dq_results AS
WITH checks AS (
  -- Input quality: how much of the file was unusable
  SELECT 'timestamp_parsed' AS check_name, 'warn' AS severity,
         (SELECT COUNT(*) FROM stg_collisions WHERE occ_ts IS NULL) AS failures, 'rows' AS unit
  UNION ALL
  SELECT 'reject_rate_under_5pct', 'warn',
         CASE WHEN (SELECT COUNT(*) FROM stg_collisions) = 0 THEN 0
              WHEN (SELECT COUNT(*) FROM collisions_rejected) * 100.0
                   / (SELECT COUNT(*) FROM stg_collisions) >= 5 THEN 1
              ELSE 0 END, 'flag'
  UNION ALL
  SELECT 'coordinates_in_bbox', 'warn',
         (SELECT COUNT(*) FROM collisions_clean WHERE dq_flags LIKE '%invalid_coords%'), 'rows'
  UNION ALL
  SELECT 'hour_missing', 'warn',
         (SELECT COUNT(*) FROM collisions_clean WHERE dq_flags LIKE '%hour_missing%'), 'rows'
  UNION ALL
  SELECT 'duplicate_occurrence', 'warn',
         (SELECT COUNT(*) FROM (
            SELECT occ_date, hour, lat, long, division
            FROM collisions_clean
            WHERE lat IS NOT NULL AND long IS NOT NULL
            GROUP BY occ_date, hour, lat, long, division
            HAVING COUNT(*) > 1)), 'groups'
  UNION ALL
  SELECT 'at_least_one_collision_type', 'warn',
         (SELECT COUNT(*) FROM collisions_clean
          WHERE NOT (coalesce(is_injury,false) OR coalesce(is_ftr,false) OR coalesce(is_pd,false))), 'rows'

  -- Source-consistency: these are the checks that would have caught the epoch-date bug
  UNION ALL
  SELECT 'source_year_matches_date', 'warn',
         (SELECT COUNT(*) FROM stg_collisions
          WHERE occ_date IS NOT NULL AND source_year IS NOT NULL AND source_year <> year), 'rows'
  UNION ALL
  SELECT 'source_dow_matches_date', 'warn',
         (SELECT COUNT(*) FROM stg_collisions
          WHERE occ_date IS NOT NULL AND source_dow IS NOT NULL AND source_dow <> upper(day_name)), 'rows'
  UNION ALL
  SELECT 'source_month_matches_date', 'warn',
         (SELECT COUNT(*) FROM stg_collisions
          WHERE occ_date IS NOT NULL AND source_month IS NOT NULL
            AND upper(trim(source_month)) <> upper(month_name)), 'rows'

  -- Correctness: these must be zero
  UNION ALL
  SELECT 'clean_rows_positive', 'error',
         CASE WHEN (SELECT COUNT(*) FROM collisions_clean) = 0 THEN 1 ELSE 0 END, 'flag'
  UNION ALL
  SELECT 'clean_date_not_null', 'error',
         (SELECT COUNT(*) FROM collisions_clean WHERE occ_date IS NULL), 'rows'
  UNION ALL
  SELECT 'year_in_range', 'error',
         (SELECT COUNT(*) FROM collisions_clean WHERE year NOT BETWEEN 2014 AND 2026), 'rows'
  UNION ALL
  SELECT 'hour_in_range', 'error',
         (SELECT COUNT(*) FROM collisions_clean WHERE hour IS NOT NULL AND hour NOT BETWEEN 0 AND 23), 'rows'
  UNION ALL
  SELECT 'fatalities_non_negative', 'error',
         (SELECT COUNT(*) FROM collisions_clean WHERE fatalities < 0), 'rows'
  UNION ALL
  SELECT 'no_future_dates', 'error',
         (SELECT COUNT(*) FROM collisions_clean WHERE occ_date > current_date()), 'rows'
  UNION ALL
  SELECT 'fact_row_count_matches_clean', 'error',
         (SELECT abs(
            (SELECT COUNT(*) FROM workspace.collisions_gold.fact_collision)
          - (SELECT COUNT(*) FROM collisions_clean))), 'rows'
  UNION ALL
  SELECT 'dim_membership_resolved', 'error',
         (SELECT COUNT(*)
          FROM collisions_clean c
          JOIN workspace.collisions_gold.fact_collision f ON f.collision_id = c._id
          WHERE (c.division IS NOT NULL AND f.division_key = 0)
             OR (c.neighbourhood_code IS NOT NULL AND f.neighbourhood_key = 0)
             OR (c.is_geocoded AND f.location_key = 0)), 'rows'
)
SELECT
  check_name,
  severity,
  failures,
  unit,
  (failures = 0) AS passed,
  current_timestamp() AS checked_at
FROM checks;

-- COMMAND ----------

SELECT
  SUM(CASE WHEN severity = 'error' AND NOT passed THEN 1 ELSE 0 END) AS blocking_failures,
  SUM(CASE WHEN severity = 'warn'  AND NOT passed THEN 1 ELSE 0 END) AS warnings,
  COUNT(*) AS checks_total
FROM dq_results;

-- COMMAND ----------

SELECT * FROM dq_results ORDER BY severity, passed, check_name;
