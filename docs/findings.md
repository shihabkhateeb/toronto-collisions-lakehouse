# Findings and limitations

Snapshot 2026-07-20. **825,265** reported collisions, 2014–2026.

## Headline numbers

| Measure | Value |
|---|---|
| Collisions | 825,265 |
| Injury or fatal | 112,974 (13.7%) |
| Fatalities | 698 |
| Fail to remain | 17.3% |
| Geocoded | 83.7% |
| Neighbourhood unassigned (`NSA` or no coordinates) | 134,405 (16.3%) |

## Finding 1 — Pedestrians are the most over-represented group

Pedestrians are involved in **2.5%** of collisions but **14.9%** of injury-or-fatal
collisions — roughly **six times** their share of exposure. Bicycles show the same
pattern at a smaller scale: 1.6% of collisions, 8.7% of injuries.

**Action:** pedestrian crossings, leading pedestrian intervals and speed reduction at
the corridors where pedestrian involvement concentrates. Vehicle-occupant safety
measures do not address this group.

## Finding 2 — Injury risk is concentrated in a small set of neighbourhoods

**Mount Dennis (115)** has the highest injury-or-fatal rate among neighbourhoods with at
least 500 collisions: **21.2%** (438 of 2,068), against **13.7%** city-wide. Eglinton
East (138) follows at 19.6% (872 of 4,458), Humber Heights-Westmount (8) at 19.3%.

**Action:** these are the first candidates for corridor review. Neighbourhoods with high
collision counts but average injury rates are volume problems, not severity problems,
and need a different intervention.

## Finding 3 — Night collisions are more severe, but not the bulk of the problem

Collisions between 22:00 and 05:59 are **9.7%** of all collisions, and their
injury-or-fatal rate is **14.9%** versus **13.6%** during the day. Volume peaks in the
weekday afternoon (Friday 15:00–17:00 is the busiest window).

**Action:** night-time lighting and enforcement have a better severity return per
collision than daytime measures, but the afternoon peak matters more for total harm
because of volume.

## Limitations

- **Reported collisions, not exposure.** No traffic volume in the source, so rates are
  per 100 collisions — severity given a collision, not the chance of being in one.
- **16.3% of collisions cannot be placed.** `NSA` neighbourhoods and `0/0` coordinates
  are kept in totals but excluded from neighbourhood rankings, so rankings describe the
  geocoded subset, not the whole city.
- **Reporting bias.** Fail-to-remain collisions are under-recorded, and minor
  property-damage collisions are inconsistently reported across years.
- **No named intersections.** The map uses 3-decimal coordinate clusters (~110 m);
  `dim_location` keeps 4 decimals (~11 m). Neither is a street intersection.
- **No serious-injury field.** The source splits fatalities from an injury flag, so
  every measure says "injury or fatal" rather than KSI.
- **Correlation, not causation.** These are co-occurrences in administrative data, not
  the effect of any intervention.
