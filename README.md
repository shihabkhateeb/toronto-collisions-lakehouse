# Toronto Collision Safety Lakehouse

Medallion pipeline + dashboard over **825,265** City of Toronto collision records (2014–2026, refreshed 2026-07-20).

**Decision question:** Which neighbourhoods should Vision Zero prioritize, and when are collisions concentrated?

## What's here

- `notebooks/` — bronze → silver → gold pipeline, 17 data-quality checks, Parquet export
- `app/` — Streamlit dashboard over the exported tables
- `docs/architecture.md` — pipeline and star-schema diagrams
- `docs/powerbi_spec.md` — Power BI model, measures and layout
- `docs/findings.md` — findings and limitations
- `dashboard/` — Power BI theme file

## Stack

Databricks Free Edition (serverless) · Delta Lake · PySpark · Spark SQL · Power BI Desktop · Streamlit

## Two data facts that drive the whole design

1. **`OCC_DATE` is epoch milliseconds, not a timestamp.** `1625371200000` → 2021-07-04 00:00 America/Toronto. It is date-only: the time of day lives in `OCC_HOUR`. Parsing it with `try_to_timestamp()` returns NULL for every row.
2. **Missing values are encoded, not null.** Unassigned divisions/neighbourhoods are `NSA`, and un-geocoded collisions have `LAT_WGS84 = 0`, `LONG_WGS84 = 0` — which is inside no valid bounding box but is not a null.

Everything the pipeline does follows from those two.

## Pipeline

```
CSV (CKAN datastore)
  └─ bronze.collisions_raw       all STRING + _ingested_at + _row_hash
       │                          MERGE on _id, snapshot-reconciled, null-id quarantined
       └─ silver.stg_collisions  epoch → local timestamp, typed, deduped, flagged
       ├─ silver.collisions_clean     valid rows, bad coords nulled
       ├─ silver.collisions_rejected  critical failures + reason
       └─ silver.dq_results           17 checks
            └─ gold.fact_collision + 4 dims + bridge_collision_road_user
                 └─ 05 export → Parquet → Power BI / Streamlit
```

**Grain of `fact_collision`: one collision occurrence (`_id`).**

## Run order

**1. Bootstrap (once, in the UI or a SQL cell)**

```sql
CREATE SCHEMA IF NOT EXISTS workspace.collisions_bronze;
CREATE VOLUME IF NOT EXISTS workspace.collisions_bronze.raw;
```

Download the CSV and upload it to
`/Volumes/workspace/collisions_bronze/raw/traffic-collisions-4326.csv`
([source URL](https://ckan0.cf.opendata.inter.prod-toronto.ca/dataset/ec53f7b2-769b-4914-91fe-a37ee27a90b3/resource/cb890861-ed20-4862-bb75-b1f9ec1e58dd/download/traffic-collisions-4326.csv)).

**2. Run, in this exact order**

```
notebooks/01_bronze_ingest.py     Python notebook
notebooks/02_silver_clean.sql     SQL notebook
notebooks/03_gold_star.sql        SQL notebook
notebooks/04_quality_checks.sql   SQL notebook  (reads gold — must be after 03)
notebooks/05_export_gold.py       Python notebook (refuses to export if any error check fails)
```

**3. Dashboard**

Download the six Parquet files the app reads (plus the optional
`bridge_collision_road_user` for Power BI) from
`/Volumes/workspace/collisions_gold/exports/` into `app/data/`. Power BI setup is in
`docs/powerbi_spec.md`.

**4. Deploy the Streamlit app**

1. Commit the six files in `app/data/` (`bridge_collision_road_user` is optional).
2. Push, then create an app at <https://share.streamlit.io> with **Main file path**
   `app/streamlit_app.py`.
3. Requirements come from `app/requirements.txt`; the theme from the repo-root
   `.streamlit/config.toml`.
4. Test: all years, one year, night-only, a division filter, and a filter that returns
   zero rows.

## Catalog note

The catalog name `workspace` is hardcoded in every notebook — `CATALOG = "workspace"`
in 01 and 05, plus fully-qualified `workspace.collisions_*` references in 02, 03 and
04. If your workspace uses a different catalog, change all of them (about 12
references), not just the `USE CATALOG` line.

## Why "injury or fatal", not KSI

The source separates fatalities from an injury flag but has **no serious-injury
field**, so the dashboard says "injury or fatal" throughout. It also has no street or
intersection names. The Streamlit map aggregates collisions into 3-decimal coordinate
clusters (~110 m); the gold layer's `dim_location` keeps 4 decimals (~11 m). Neither is
a named intersection.

## Limitations

- Reported collisions, not exposure. Raw counts favour high-traffic areas; the
  dashboard reports injury rate per 100 collisions, not per vehicle-kilometre.
- Coverage depends on police reporting; fail-to-remain collisions are systematically
  under-recorded.
- Figures reflect the 2026-07-20 snapshot.
