# Databricks notebook source
# MAGIC %md
# MAGIC # 05 — Export gold
# MAGIC
# MAGIC Runs the data-quality gate, then writes one small Parquet file per table.
# MAGIC
# MAGIC `coalesce(1)` gives each output a single `part-*.parquet`, which is what you
# MAGIC download from the volume browser.
# MAGIC Nothing queries Databricks at runtime, so the app keeps working after
# MAGIC the Free Edition quota runs out.
# MAGIC
# MAGIC Run this after 03 and 04.

# COMMAND ----------

CATALOG = "workspace"
GOLD = f"{CATALOG}.collisions_gold"
SILVER = f"{CATALOG}.collisions_silver"
EXPORT = f"/Volumes/{CATALOG}/collisions_gold/exports"

spark.sql(f"CREATE VOLUME IF NOT EXISTS {GOLD}.exports")

blocking = spark.sql(f"""
    SELECT COUNT(*) FROM {SILVER}.dq_results
    WHERE severity = 'error' AND NOT passed
""").collect()[0][0]
assert blocking == 0, f"{blocking} blocking data-quality failures — fix before exporting"

print("data-quality gate passed")

# COMMAND ----------

TABLES = [
    (GOLD, "fact_collision"),
    (GOLD, "dim_date"),
    (GOLD, "dim_division"),
    (GOLD, "dim_neighbourhood"),
    (GOLD, "dim_location"),
    (SILVER, "dq_results"),
]

for schema, name in TABLES:
    (
        spark.table(f"{schema}.{name}")
        .coalesce(1)
        .write.mode("overwrite")
        .parquet(f"{EXPORT}/{name}")
    )
    print(f"wrote {name}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Download
# MAGIC **Catalog → workspace → collisions_gold → exports** → open each folder →
# MAGIC download the single `part-*.parquet` → rename to `<table>.parquet` in
# MAGIC `app/data/`.
# MAGIC
# MAGIC If the browser upload/download stalls on a large file, use the CLI:
# MAGIC `databricks fs cp dbfs:/Volumes/... ./local/`

# COMMAND ----------

for row in dbutils.fs.ls(EXPORT):
    print(row.path, row.size)
