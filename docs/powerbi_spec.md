# Power BI build spec

One report, two pages: **Overview** (the story) and **Data quality**. Canvas 1280 × 720.
Theme: `dashboard/theme.json`.

## 1. Get the data

Export first (`notebooks/05_export_gold.py`), download the seven Parquet files from
`/Volumes/workspace/collisions_gold/exports/`, and rename them into `app/data/`.

Then in Power BI Desktop:

**Home → Get Data → Parquet** → select `app/data/<table>.parquet`, one table per query.
Repeat for the six tables you need (`fact_collision`, `dim_date`, `dim_division`,
`dim_neighbourhood`, `dim_location`, `dq_results`).

Do **not** point the **Folder** connector at the exports root: it recurses into all
seven table folders and merges different schemas. If you must use Folder, point it at
one table folder, filter `Extension = ".parquet"`, then combine.

In **Transform Data**:

1. `fact_collision.hour` must be a whole number and may be null.
2. `dim_date.date` → Date.
3. Turn off **File → Options → Data load → Auto date/time**.

## 2. Model

| From | To | Cardinality | Direction |
|---|---|---|---|
| `dim_date[date_key]` | `fact_collision[date_key]` | 1 → * | Single |
| `dim_division[division_key]` | `fact_collision[division_key]` | 1 → * | Single |
| `dim_neighbourhood[neighbourhood_key]` | `fact_collision[neighbourhood_key]` | 1 → * | Single |
| `dim_location[location_key]` | `fact_collision[location_key]` | 1 → * | Single |

Mark `dim_date[date]` as the date table.

Calculated columns:

```dax
Day Sort = WEEKDAY ( dim_date[date], 2 )
```

Sort `dim_date[day_name]` by `Day Sort` so the week runs Monday → Sunday.
(`day_of_week` in gold starts at Sunday, so sorting by it gives Sunday first.)

```dax
Is Night =
IF (
    NOT ISBLANK ( fact_collision[hour] )
        && ( fact_collision[hour] >= 22 || fact_collision[hour] < 6 ),
    "Night",
    "Day"
)
```

Use `fact_collision[Is Night]` as the night slicer. Do not filter on `hour` directly:
BLANK is treated as 0 in DAX, so `hour < 6` would count unknown hours as night.

```dax
Status = IF ( dq_results[passed], "PASS", "FAIL" )
```

## 3. Measures

```dax
Total Collisions = COUNTROWS ( fact_collision )

Injury or Fatal Collisions =
CALCULATE (
    [Total Collisions],
    FILTER (
        fact_collision,
        fact_collision[is_injury] = TRUE () || fact_collision[is_fatal] = TRUE ()
    )
)

Injury or Fatal % = DIVIDE ( [Injury or Fatal Collisions], [Total Collisions], 0 )

Total Fatalities = SUM ( fact_collision[fatalities] ) + 0

Fail to Remain % =
DIVIDE ( CALCULATE ( [Total Collisions], fact_collision[is_ftr] = TRUE () ), [Total Collisions], 0 )

Night Collisions =
CALCULATE (
    [Total Collisions],
    NOT ISBLANK ( fact_collision[hour] )
        && ( fact_collision[hour] >= 22 || fact_collision[hour] < 6 )
)

Night Share % = DIVIDE ( [Night Collisions], [Total Collisions], 0 )

Geocoded % =
DIVIDE ( CALCULATE ( [Total Collisions], fact_collision[is_geocoded] = TRUE () ), [Total Collisions], 0 )

Collisions 12M Avg =
VAR CurrentMonth = MAX ( dim_date[date] )
VAR WindowStart = EDATE ( CurrentMonth, -11 )
RETURN
    AVERAGEX (
        CALCULATETABLE (
            SUMMARIZE ( dim_date, dim_date[year], dim_date[month] ),
            dim_date[date] >= DATE ( YEAR ( WindowStart ), MONTH ( WindowStart ), 1 ),
            dim_date[date] <= CurrentMonth
        ),
        CALCULATE ( [Total Collisions] )
    )
```

`Collisions 12M Avg` averages **monthly totals**, not daily rows. Filter the trend
visual to complete months, otherwise the partial final snapshot month pulls it down.

There is no KSI measure: the source has no serious-injury field, only a fatality count
and an injury flag. Use "Injury or fatal" everywhere.

## 4. Layout — Overview page

| Zone | Position (x, y, w, h) | Visual | Fields |
|---|---|---|---|
| Slicers | 0,0 → one row, h=64 | Slicer ×3 | `dim_date[year]` (between), `dim_division[division]`, `fact_collision[Is Night]` |
| KPI | 0,80 → 5 cards across, h=80 | Card ×5 | `Total Collisions`, `Injury or Fatal %`, `Total Fatalities`, `Fail to Remain %`, `Geocoded %` |
| Trend | 0,180,620,320 | Line | Axis `dim_date[date]` (month), Values `Total Collisions` + `Collisions 12M Avg` |
| Heatmap | 640,180,620,320 | Matrix with conditional formatting | Rows `dim_date[day_name]`, Columns `fact_collision[hour]`, Values `Total Collisions`, blue scale |
| Neighbourhoods | 0,520,620,180 | Clustered bar (horizontal) | Axis `dim_neighbourhood[neighbourhood]`, Values `Injury or Fatal %` |
| Road users | 640,520,620,180 | Clustered column | Axis `bridge_collision_road_user[road_user]`, Values below |

Neighbourhood bar — three visual-level filters:

1. `dim_neighbourhood[neighbourhood]` is not `UNKNOWN`
2. `[Total Collisions] >= 500`
3. **Top N** → Show items: 10 → By value: `[Injury or Fatal %]`

Road users need the bridge table (`bridge_collision_road_user`, relationships:
`fact_collision[collision_id]` 1 → * `bridge_collision_road_user[collision_id]`).
Import it even though the Streamlit app does not use it.

```dax
Share of Collisions =
DIVIDE (
    [Total Collisions],
    CALCULATE ( [Total Collisions], REMOVEFILTERS ( bridge_collision_road_user ) ),
    0
)

Share of Injury or Fatal =
DIVIDE (
    [Injury or Fatal Collisions],
    CALCULATE ( [Injury or Fatal Collisions], REMOVEFILTERS ( bridge_collision_road_user ) ),
    0
)
```

Caption the visual: a collision can involve more than one road user, so the shares do
not sum to 100%.

## 5. Layout — Data quality page

Table with `dq_results[check_name]`, `[severity]`, `[failures]`, `[unit]`, `[Status]`,
`[checked_at]`, sorted by severity then status. Keep `unit`: `failures = 1` means
something different for `rows`, `groups` and `flag`.

## 6. Formatting

- Data labels on, gridlines off.
- Numbers `#,0`; percentages `0.0%`.
- Red (`#C0392B`) only for injury/fatal series. The heatmap uses a blue scale, because
  red there would mean "density", not "severity".
- Set red explicitly on the injury measure; it is not the second entry in the theme's
  colour list.

## 7. Export

**File → Export → Export to PDF** → `dashboard/collisions.pdf` (two pages).
Save the `.pbix` next to it. "Publish to web" needs tenant admin rights, so the PDF is
the static artifact and the Streamlit app carries the interactive version.

## 8. Checks before you call it done

- [ ] Year slicer changes every visual
- [ ] Neighbourhood bar shows exactly 10 rows and no `UNKNOWN`
- [ ] Day names run Monday → Sunday
- [ ] Night KPI matches the app for the same filter
- [ ] KPI totals match `SELECT COUNT(*) FROM fact_collision`
- [ ] DQ page shows 0 blocking failures
- [ ] PDF pages are readable at 100% zoom
