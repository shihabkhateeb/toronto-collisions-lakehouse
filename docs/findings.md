# Findings and limitations

## What the analysis shows

The dashboard ranks neighbourhoods by **injury or fatal rate per 100 collisions**, not
by collision count. Raw counts mostly rank traffic volume: the busiest corridor wins
regardless of severity. The rate view answers the question Vision Zero actually asks —
where a collision is more likely to hurt someone.

Time-of-day and day-of-week are shown together as a heatmap because either one alone is
misleading: late-night weekend collisions and weekday rush-hour collisions are different
problems with different interventions.

Road-user involvement is counted separately for vehicles, passengers, motorcycles,
bicycles and pedestrians. A collision can involve more than one group, so those shares
do not add up to 100%.

## Limitations

- **Reported collisions, not exposure.** The dataset has no traffic volume, so it cannot
  produce risk per vehicle-kilometre. Rates are per 100 collisions, which measures
  severity given a collision, not the chance of being in one.
- **Reporting bias.** Fail-to-remain collisions are under-recorded, and minor
  property-damage collisions are inconsistently reported across years.
- **No street or intersection names.** Hotspots are coordinate clusters rounded to four
  decimal places (~11 m), plus neighbourhoods. They are not named intersections.
- **No serious-injury field.** The source separates fatalities from an injury flag, so
  every measure is labelled "injury or fatal" rather than KSI.
- **Unassigned records.** Collisions with `NSA` division or neighbourhood, and
  un-geocoded collisions, are mapped to an `UNKNOWN` member rather than dropped. They are
  visible in totals but excluded from neighbourhood rankings.
- **Snapshot.** Figures reflect the 2026-07-20 refresh.
