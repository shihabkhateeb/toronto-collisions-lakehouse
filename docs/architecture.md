# Architecture

## Pipeline

```mermaid
flowchart LR
    A["City of Toronto<br/>open data CSV<br/>825,265 rows"] --> B["bronze.collisions_raw<br/>all columns as text<br/>+ _ingested_at, _row_hash"]
    B -->|"MERGE on _id<br/>snapshot reconciled"| C["silver.stg_collisions<br/>epoch → local time<br/>typed, deduped, flagged"]
    C --> D["silver.collisions_clean<br/>valid rows"]
    C --> E["silver.collisions_rejected<br/>reason recorded"]
    D --> F["silver.dq_results<br/>17 checks"]
    D --> G["gold.fact_collision<br/>+ 4 dimensions"]
    G --> H["bridge_collision_road_user"]
    F --> I[("Parquet export<br/>one file per table")]
    G --> I
    H --> I
    I --> K["Streamlit app<br/>public link"]
```

## Star schema

```mermaid
erDiagram
    dim_date ||--o{ fact_collision : date_key
    dim_division ||--o{ fact_collision : division_key
    dim_neighbourhood ||--o{ fact_collision : neighbourhood_key
    dim_location ||--o{ fact_collision : location_key
    fact_collision ||--o{ bridge_collision_road_user : collision_id
```

## Rules the model follows

| Rule | Why |
|---|---|
| Grain of `fact_collision` = one occurrence (`_id`) | Every measure is additive at that level |
| Unknown members use key `0` | Unknowns stay countable instead of becoming blanks |
| A collision is rejected only if unusable (no id, no timestamp, impossible year, negative fatalities) | Bad coordinates do not make the incident fake — they are nulled and flagged |
| `OCC_DATE` is epoch ms at local midnight | `try_to_timestamp()` returns NULL for it; the time of day lives in `OCC_HOUR` |
| `NSA` and `0/0` coordinates are mapped to NULL | They are "unassigned", not real neighbourhoods or places |
| Export is blocked while any `error` check fails | Bad data cannot reach the dashboard |
