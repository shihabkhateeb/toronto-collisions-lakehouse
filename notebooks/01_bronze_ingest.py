# Databricks notebook source
# MAGIC %md
# MAGIC # 01 — Bronze: land raw collisions
# MAGIC
# MAGIC Loads the CKAN CSV as-is: every column cast to STRING, plus `_ingested_at`,
# MAGIC `_source_file` and a `_row_hash` used for change detection.
# MAGIC
# MAGIC Idempotent: first run creates the table, later runs MERGE on `_id` and only
# MAGIC update rows whose content actually changed. Because the source is a full
# MAGIC snapshot, `WHEN NOT MATCHED BY SOURCE THEN DELETE` reconciles removals —
# MAGIC guarded by a row-count check so a truncated read can't wipe bronze.

# COMMAND ----------

from pyspark.sql import Window
from pyspark.sql import functions as F
from pyspark.sql.types import StringType

CATALOG = "workspace"
BRONZE = f"{CATALOG}.collisions_bronze"
SILVER = f"{CATALOG}.collisions_silver"
GOLD = f"{CATALOG}.collisions_gold"

dbutils.widgets.text(
    "source_path",
    "/Volumes/workspace/collisions_bronze/raw/traffic-collisions-4326.csv",
    "Raw CSV path",
)
SOURCE_PATH = dbutils.widgets.get("source_path")
TARGET = f"{BRONZE}.collisions_raw"

MIN_ROWS = 800_000  # floor for a full snapshot; the file has ~825k rows

spark.sql(f"CREATE SCHEMA IF NOT EXISTS {BRONZE}")
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {SILVER}")
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {GOLD}")
# the source volume must exist before the CSV can be uploaded into it
spark.sql(f"CREATE VOLUME IF NOT EXISTS {BRONZE}.raw")

# COMMAND ----------

REQUIRED_COLUMNS = {
    "_id", "OCC_DATE", "OCC_MONTH", "OCC_DOW", "OCC_YEAR", "OCC_HOUR",
    "DIVISION", "FATALITIES", "INJURY_COLLISIONS", "FTR_COLLISIONS",
    "PD_COLLISIONS", "HOOD_158", "NEIGHBOURHOOD_158", "LONG_WGS84",
    "LAT_WGS84", "AUTOMOBILE", "MOTORCYCLE", "PASSENGER", "BICYCLE",
    "PEDESTRIAN",
}

raw = (
    spark.read.option("header", True)
    .option("inferSchema", False)   # keep everything as text on purpose
    .option("multiLine", False)     # this snapshot has no embedded newlines
    .option("escape", '"')          # geometry uses RFC4180-doubled quotes
    .option("encoding", "UTF-8")
    .csv(SOURCE_PATH)
)

# Header cleanup: strip BOM and whitespace
columns = [c.strip().lstrip("\ufeff") for c in raw.columns]
raw = raw.toDF(*columns)

missing = REQUIRED_COLUMNS - set(columns)
if missing:
    raise ValueError(f"Source is missing expected columns: {sorted(missing)}")

# Force all source columns to string so nothing is silently coerced
raw = raw.select([F.col(c).cast(StringType()).alias(c) for c in columns])

row_count = raw.count()
print(f"read {row_count:,} rows from {SOURCE_PATH}")
assert row_count >= MIN_ROWS, f"Read only {row_count:,} rows — truncated or malformed CSV"

if spark.catalog.tableExists(TARGET):
    previous = spark.table(TARGET).count()
    assert 0.98 * previous <= row_count <= 1.5 * previous, (
        f"Row count moved from {previous:,} to {row_count:,} — refusing to reconcile"
    )

# COMMAND ----------

SEP = "\u241F"
NULL_TOKEN = "\u2400"

# geometry is excluded: its coordinate precision can drift between refreshes
# without any fact changing, which would trigger pointless updates.
HASH_COLUMNS = [c for c in columns if c != "geometry"]

row_hash = F.sha2(
    F.concat_ws(SEP, *[F.coalesce(F.col(c), F.lit(NULL_TOKEN)) for c in HASH_COLUMNS]),
    256,
)

staged = (
    raw.withColumn("_ingested_at", F.current_timestamp())
    .withColumn("_source_file", F.lit(SOURCE_PATH))
    .withColumn("_row_hash", row_hash)
)

# COMMAND ----------

# Rows without an id cannot be merged; keep them in a quarantine table instead of
# letting them pile up in bronze on every run.
null_id = staged.filter(F.col("_id").isNull())
null_count = null_id.count()
if null_count > 0:
    null_id.write.format("delta").mode("overwrite").saveAsTable(f"{BRONZE}.collisions_null_id")
    print(f"quarantined {null_count:,} rows with a null _id")

candidates = staged.filter(F.col("_id").isNotNull())

window = Window.partitionBy("_id").orderBy(
    F.col("_ingested_at").desc(), F.col("_row_hash").desc()
)
deduped = (
    candidates.withColumn("_rn", F.row_number().over(window))
    .filter("_rn = 1")
    .drop("_rn")
)
deduped.createOrReplaceTempView("_bronze_staged")

if not spark.catalog.tableExists(TARGET):
    deduped.write.format("delta").mode("overwrite").saveAsTable(TARGET)
    print(f"Created {TARGET}")
else:
    spark.sql(f"""
        MERGE INTO {TARGET} AS t
        USING _bronze_staged AS s
        ON t._id = s._id
        WHEN MATCHED AND t._row_hash IS DISTINCT FROM s._row_hash THEN UPDATE SET *
        WHEN NOT MATCHED THEN INSERT *
        WHEN NOT MATCHED BY SOURCE THEN DELETE
    """)
    print(f"Merged into {TARGET}")

# COMMAND ----------

display(spark.sql(f"""
    SELECT
        COUNT(*)                        AS rows_total,
        COUNT(DISTINCT _id)             AS rows_distinct_id,
        COUNT(*) - COUNT(DISTINCT _id)  AS duplicate_ids,
        MIN(_ingested_at)               AS first_ingested,
        MAX(_ingested_at)               AS last_ingested
    FROM {TARGET}
"""))
