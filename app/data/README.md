# Drop the exports here.

Run `notebooks/05_export_gold.py`, download the single `part-*.parquet` from each
folder under `/Volumes/workspace/collisions_gold/exports/`, and rename them to:

```
fact_collision.parquet
dim_date.parquet
dim_division.parquet
dim_neighbourhood.parquet
dim_location.parquet
dq_results.parquet
```

The app also accepts `.csv` if you prefer.
