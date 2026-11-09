# Power BI build spec — one page, six visuals

Match the Streamlit app so the two artifacts tell the same story.
Canvas: **1280 × 720**. Theme file: `dashboard/theme.json`.

## 1. Get the data

Export first (`notebooks/05_export_gold.py`), then in Power BI Desktop:

**Home → Get Data → Parquet** → point at each folder, or **Get Data → Folder** and point at the
export directory. Import these tables:

- `fact_collision`
- `dim_date`, `dim_division`, `dim_neighbourhood`, `dim_location`
- `dq_results`

Then **Transform Data**:

1. In `fact_collision`, change `is_injury`, `is_ftr`, `is_pd`, `is_fatal`, `is_geocoded`,
   `involved_*` to **True/False** if they arrive as text.
2. In `dim_date`, set `date` to **Date** type.
3. Confirm `hour`, `fatalities`, `date_key`, `*_key` are whole numbers.

## 2. Model

Disable **File → Options → Data load → Auto date/time** first.

| From | To | Cardinality | Direction |
|---|---|---|---|
| `dim_date[date_key]` | `fact_collision[date_key]` | 1 → * | Single |
| `dim_division[division_key]` | `fact_collision[division_key]` | 1 → * | Single |
| `dim_neighbourhood[neighbourhood_key]` | `fact_collision[neighbourhood_key]` | 1 → * | Single |
| `dim_location[location_key]` | `fact_collision[location_key]` | 1 → * | Single |

Also set **Mark as date table** → `dim_date[date]`.
In `dim_date`, select `day_name` → **Sort by column → `day_of_week`** (so Monday–Sunday order holds).

## 3. Measures

```dax
Total Collisions = COUNTROWS ( fact_collision )

Injury or Fatal Collisions =
CALCULATE (
    [Total Collisions],
    FILTER ( fact_collision, fact_collision[is_injury] = TRUE () || fact_collision[is_fatal] = TRUE () )
)

Injury or Fatal % = DIVIDE ( [Injury or Fatal Collisions], [Total Collisions] )

Fatalities = SUM ( fact_collision[fatalities] )

Fail to Remain % =
DIVIDE ( CALCULATE ( [Total Collisions], fact_collision[is_ftr] = TRUE () ), [Total Collisions] )

Night Collisions =
CALCULATE ( [Total Collisions], fact_collision[hour] >= 22 || fact_collision[hour] < 6 )

Night Share % = DIVIDE ( [Night Collisions], [Total Collisions] )

Geocoded % =
DIVIDE ( CALCULATE ( [Total Collisions], fact_collision[is_geocoded] = TRUE () ), [Total Collisions] )

Collisions 12M Avg =
AVERAGEX (
    DATESINPERIOD ( dim_date[date], MAX ( dim_date[date] ), -12, MONTH ),
    [Total Collisions]
)

Neighbourhood Injury % =
DIVIDE ( [Injury or Fatal Collisions], [Total Collisions] )
```

Do **not** call this KSI. The source splits fatality from injury but has no
"serious injury" flag, so "injury or fatal" is the honest label.

## 4. Layout

| Zone | Position (x, y, w, h) | Visual | Fields |
|---|---|---|---|
| KPI | 0,0 → 6 cards across the top, h=80 | Card ×5 | `Total Collisions`, `Injury or Fatal %`, `Fatalities`, `Fail to Remain %`, `Geocoded %` |
| Trend | 0,100,620,320 | Line | Axis `dim_date[date]` (month), Values `Total Collisions`; add a 12-month moving average measure |
| Heatmap | 640,100,620,320 | Matrix with conditional formatting, or a Python/R-free row-per-hour matrix | Rows `dim_date[day_name]`, Columns `fact_collision[hour]`, Values `Total Collisions`, background colour scale red |
| Neighbourhoods | 0,440,620,260 | Clustered bar (horizontal), top 10 | Axis `dim_neighbourhood[neighbourhood]`, Values `Neighbourhood Injury %`; filter `Total Collisions >= 500` |
| Road users | 640,440,620,260 | Clustered column | One column per `involved_*` flag counted as % of injury-or-fatal; use a field parameter or a small unpivot |
| DQ panel | second page | Table | `dq_results[check_name, severity, failures, status]` |

Slicers (top-right on the row above the KPIs): `dim_date[year]` (between), `dim_division[division]`, and a
Night toggle via a disconnected table or a bookmark pair.

**Formatting:** data labels on, gridlines off, `Collisions` as `#,0`, percentages as `0.0%`,
red (`#C0392B`) reserved for injury/fatal only, everything else neutral grey or the accent green.

## 5. Export

**File → Export → Export to PDF**, save as `dashboard/collisions.pdf`, commit it.
Also keep the `.pbix` in `dashboard/` so reviewers can open the model.

"Publish to web" needs tenant admin rights, so the exported PDF is the shareable
snapshot and the Streamlit app carries the interactive version.

## 6. Checks before you call it done

- [ ] Year slicer changes every visual (no visual bound to a table outside the model)
- [ ] Neighbourhood filter shows `(Blank)` nowhere — unknowns map to key 0 / `UNKNOWN`
- [ ] Day names run Monday → Sunday
- [ ] KPI totals match `SELECT COUNT(*) FROM fact_collision`
- [ ] PDF is one page, readable at 100% zoom
