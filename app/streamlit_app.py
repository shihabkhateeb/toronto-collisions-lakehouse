"""Toronto Collision Safety Lakehouse — Streamlit demo.

Reads the exports produced by notebooks/05_export_gold.py (drop them in ./data).

Run locally:  pip install -r requirements.txt && streamlit run streamlit_app.py
"""

from pathlib import Path

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

DATA_DIR = Path(__file__).resolve().parent / "data"

ACCENT = "#0B6E4F"
ALERT = "#C0392B"
NEUTRAL = "#94A3B8"
DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

TABLES = [
    "fact_collision",
    "dim_date",
    "dim_division",
    "dim_neighbourhood",
    "dim_location",
    "dq_results",
]

st.set_page_config(
    page_title="Toronto Collision Safety",
    page_icon="🚦",
    layout="wide",
    initial_sidebar_state="expanded",
)


def _read(name: str) -> pd.DataFrame:
    """Parquet preferred; CSV accepted so the export step stays flexible."""
    parquet = DATA_DIR / f"{name}.parquet"
    if parquet.exists():
        return pd.read_parquet(parquet)
    csv = DATA_DIR / f"{name}.csv"
    if csv.exists():
        return pd.read_csv(csv)
    raise FileNotFoundError(name)


@st.cache_data(show_spinner="Loading collision data…")
def load_data():
    missing = [t for t in TABLES if not any((DATA_DIR / f"{t}{e}").exists() for e in (".parquet", ".csv"))]
    if missing:
        raise FileNotFoundError(", ".join(missing))

    fact = _read("fact_collision")
    d_date = _read("dim_date")
    d_div = _read("dim_division")
    d_nbhd = _read("dim_neighbourhood")
    d_loc = _read("dim_location")
    dq = _read("dq_results")

    df = fact.merge(d_date, on="date_key", how="left")
    df = df.merge(d_div, on="division_key", how="left")
    df = df.merge(d_nbhd, on="neighbourhood_key", how="left")
    df = df.merge(
        d_loc.rename(columns={"lat": "loc_lat", "long": "loc_long"})[
            ["location_key", "loc_lat", "loc_long"]
        ],
        on="location_key",
        how="left",
    )

    df["date"] = pd.to_datetime(df["date"], errors="coerce")
    df["injury_or_fatal"] = df["is_injury"].fillna(False) | df["is_fatal"].fillna(False)
    df["month_start"] = df["date"].dt.to_period("M").dt.to_timestamp()
    df["is_night"] = (df["hour"] >= 22) | (df["hour"] < 6)
    return df, dq


def kpi_row(frame: pd.DataFrame) -> None:
    total = len(frame)
    injured = int(frame["injury_or_fatal"].sum())
    fatalities = int(frame["fatalities"].sum())
    ftr = frame["is_ftr"].fillna(False).mean() * 100 if total else 0
    geocoded = frame["is_geocoded"].fillna(False).mean() * 100 if total else 0

    c1, c2, c3, c4, c5 = st.columns(5)
    c1.metric("Collisions", f"{total:,.0f}")
    c2.metric("Injury or fatal", f"{injured:,.0f}", f"{injured / total * 100:.1f}% of total" if total else None)
    c3.metric("Fatalities", f"{fatalities:,.0f}")
    c4.metric("Fail to remain", f"{ftr:.1f}%")
    c5.metric("Geocoded", f"{geocoded:.1f}%")


def trend_chart(frame: pd.DataFrame) -> None:
    trend = frame.groupby("month_start").size().reset_index(name="collisions")
    trend["rolling_12m"] = trend["collisions"].rolling(12, min_periods=3).mean()

    fig = go.Figure()
    fig.add_trace(
        go.Scatter(
            x=trend["month_start"],
            y=trend["collisions"],
            mode="lines",
            name="Monthly",
            line=dict(color=NEUTRAL, width=1),
        )
    )
    fig.add_trace(
        go.Scatter(
            x=trend["month_start"],
            y=trend["rolling_12m"],
            mode="lines",
            name="12-month average",
            line=dict(color=ACCENT, width=3),
        )
    )
    fig.update_layout(
        height=340,
        margin=dict(l=10, r=10, t=30, b=10),
        legend=dict(orientation="h", yanchor="bottom", y=1.02, x=0),
        yaxis_title="Collisions",
        xaxis_title=None,
        plot_bgcolor="white",
    )
    st.plotly_chart(fig, width="stretch")


def heatmap_chart(frame: pd.DataFrame) -> None:
    pivot = (
        frame.pivot_table(index="day_name", columns="hour", values="collision_id", aggfunc="count")
        .reindex(DAYS)
        .reindex(columns=range(24))
        .fillna(0)
    )
    fig = go.Figure(
        go.Heatmap(
            z=pivot.values,
            x=list(range(24)),
            y=DAYS,
            colorscale="Reds",
            hovertemplate="%{y} %{x}:00<br>%{z:,} collisions<extra></extra>",
            colorbar=dict(title="Collisions", thickness=10),
        )
    )
    fig.update_layout(
        height=340,
        margin=dict(l=10, r=10, t=30, b=10),
        xaxis_title="Hour of day",
        yaxis_title=None,
        plot_bgcolor="white",
    )
    st.plotly_chart(fig, width="stretch")


def neighbourhood_chart(frame: pd.DataFrame, min_volume: int) -> None:
    g = (
        frame.groupby("neighbourhood")
        .agg(collisions=("collision_id", "count"), injured=("injury_or_fatal", "sum"))
        .reset_index()
    )
    g = g[g["neighbourhood"].notna() & (g["collisions"] >= min_volume)]
    if g.empty:
        st.info(f"No neighbourhood has at least {min_volume:,} collisions in this selection.")
        return

    g["injury_rate"] = g["injured"] / g["collisions"] * 100
    g = g.nlargest(10, "injury_rate").sort_values("injury_rate")

    fig = px.bar(
        g,
        x="injury_rate",
        y="neighbourhood",
        orientation="h",
        text=g["injury_rate"].map(lambda v: f"{v:.1f}%"),
        hover_data={"collisions": ":,", "injured": ":,", "injury_rate": ":.1f"},
        color_discrete_sequence=[ALERT],
    )
    fig.update_traces(textposition="outside", cliponaxis=False)
    fig.update_layout(
        height=400,
        margin=dict(l=10, r=40, t=10, b=10),
        xaxis_title="Injury or fatal per 100 collisions",
        yaxis_title=None,
        plot_bgcolor="white",
        showlegend=False,
    )
    st.plotly_chart(fig, width="stretch")
    st.caption(f"Neighbourhoods with at least {min_volume:,} collisions in the current selection.")


def road_user_chart(frame: pd.DataFrame) -> None:
    mapping = {
        "involved_automobile": "Automobile",
        "involved_motorcycle": "Motorcycle",
        "involved_passenger": "Passenger",
        "involved_bicycle": "Bicycle",
        "involved_pedestrian": "Pedestrian",
    }
    rows = []
    total = len(frame)
    injured_total = int(frame["injury_or_fatal"].sum()) or 1
    for col, label in mapping.items():
        mask = frame[col].fillna(False)
        rows.append(
            {
                "Road user": label,
                "Share of collisions": mask.sum() / total * 100 if total else 0,
                "Share of injury or fatal": frame.loc[mask, "injury_or_fatal"].sum() / injured_total * 100,
            }
        )
    ru = pd.DataFrame(rows).melt(id_vars="Road user", var_name="Measure", value_name="Percent")

    fig = px.bar(
        ru,
        x="Road user",
        y="Percent",
        color="Measure",
        barmode="group",
        text=ru["Percent"].map(lambda v: f"{v:.1f}%"),
        color_discrete_sequence=[NEUTRAL, ALERT],
    )
    fig.update_traces(textposition="outside", cliponaxis=False)
    fig.update_layout(
        height=380,
        margin=dict(l=10, r=10, t=30, b=10),
        yaxis_title="Percent",
        xaxis_title=None,
        plot_bgcolor="white",
        legend=dict(orientation="h", yanchor="bottom", y=1.02, x=0, title=None),
    )
    st.plotly_chart(fig, width="stretch")
    st.caption("A collision can involve more than one road user, so shares do not sum to 100%.")


def hotspot_map(frame: pd.DataFrame) -> None:
    pts = frame.dropna(subset=["loc_lat", "loc_long"]).copy()
    if pts.empty:
        st.info("No geocoded collisions in this selection.")
        return

    pts["grid_lat"] = pts["loc_lat"].round(3)
    pts["grid_long"] = pts["loc_long"].round(3)
    hot = (
        pts.groupby(["grid_lat", "grid_long"])
        .agg(collisions=("collision_id", "count"), injured=("injury_or_fatal", "sum"))
        .reset_index()
        .nlargest(50, "collisions")
    )

    common = dict(
        lat="grid_lat",
        lon="grid_long",
        size="collisions",
        color="injured",
        color_continuous_scale="Reds",
        size_max=28,
        zoom=10,
        center={"lat": 43.70, "lon": -79.40},
        hover_data={"collisions": ":,", "injured": ":,", "grid_lat": False, "grid_long": False},
        labels={"collisions": "Collisions", "injured": "Injury or fatal"},
    )
    # plotly>=6 renamed scatter_mapbox -> scatter_map
    if hasattr(px, "scatter_map"):
        fig = px.scatter_map(hot, map_style="open-street-map", **common)
    else:
        fig = px.scatter_mapbox(hot, mapbox_style="open-street-map", **common)
    fig.update_layout(height=520, margin=dict(l=0, r=0, t=0, b=0))
    st.plotly_chart(fig, width="stretch")
    st.caption(
        "Top 50 coordinate clusters, rounded to ~110 m. The source has no street or intersection names, "
        "so these are grid hotspots, not named intersections."
    )


def dq_panel(dq: pd.DataFrame) -> None:
    # parquet gives booleans, CSV gives "True"/"False"; normalise both
    passed = dq["passed"].astype(str).str.strip().str.lower().isin(["true", "1", "yes"])
    errors = dq[(dq["severity"] == "error") & ~passed]
    warns = dq[(dq["severity"] == "warn") & ~passed]

    c1, c2, c3 = st.columns(3)
    c1.metric("Checks", len(dq))
    c2.metric("Blocking failures", len(errors))
    c3.metric("Warnings", len(warns))

    view = dq.copy()
    view["status"] = passed.map({True: "PASS", False: "FAIL"})
    view["failures"] = view["failures"].fillna(0).astype("int64").map("{:,}".format)
    st.dataframe(
        view[["status", "check_name", "severity", "failures", "checked_at"]],
        width="stretch",
        hide_index=True,
    )


def main() -> None:
    try:
        df, dq = load_data()
    except FileNotFoundError as exc:
        st.error(
            f"Missing export files in `{DATA_DIR}`: **{exc}**\n\n"
            "Run `notebooks/05_export_gold.py` in Databricks, download the files from "
            "`/Volumes/workspace/collisions_gold/exports/`, and place them in `app/data/`."
        )
        st.stop()

    st.sidebar.title("Filters")
    years = sorted(int(y) for y in df["year"].dropna().unique())
    if len(years) > 1:
        y0, y1 = st.sidebar.select_slider("Year range", options=years, value=(years[0], years[-1]))
    elif years:
        y0 = y1 = years[0]
    else:
        y0, y1 = 0, 0

    divisions = sorted(df["division"].dropna().unique())
    sel_div = st.sidebar.multiselect("Police division", divisions, help="Leave empty for all")
    night_only = st.sidebar.toggle("Night only (22:00–05:59)", value=False)

    st.sidebar.divider()
    st.sidebar.caption(
        "Source: City of Toronto Open Data — Traffic Collisions (snapshot 2026-07-20). "
        "Reported occurrences, not exposure-adjusted rates."
    )

    f = df[df["year"].between(y0, y1)]
    if sel_div:
        f = f[f["division"].isin(sel_div)]
    if night_only:
        f = f[f["is_night"]]

    st.title("Toronto Collision Safety")
    st.caption(
        "Which neighbourhoods should Vision Zero prioritize, and when are collisions concentrated?"
    )

    if f.empty:
        st.warning("No collisions match the current filters.")
        st.stop()

    kpi_row(f)
    st.divider()

    tab_overview, tab_hotspots, tab_users, tab_dq = st.tabs(
        ["Overview", "Hotspots", "Road users", "Data quality"]
    )

    with tab_overview:
        left, right = st.columns(2)
        with left:
            st.subheader("Monthly collisions")
            trend_chart(f)
        with right:
            st.subheader("When collisions happen")
            heatmap_chart(f)

    with tab_hotspots:
        left, right = st.columns([1, 1])
        min_vol = left.slider(
            "Minimum collisions per neighbourhood",
            min_value=50,
            max_value=2000,
            value=500,
            step=50,
        )
        with left:
            st.subheader("Highest injury rate")
            neighbourhood_chart(f, min_vol)
        with right:
            st.subheader("Collision clusters")
            hotspot_map(f)

    with tab_users:
        st.subheader("Who is involved")
        road_user_chart(f)

    with tab_dq:
        st.subheader("Pipeline quality checks")
        dq_panel(dq)


if __name__ == "__main__":
    main()
