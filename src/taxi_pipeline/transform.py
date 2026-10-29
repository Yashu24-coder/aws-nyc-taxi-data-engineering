from __future__ import annotations

from pathlib import Path
import pandas as pd

PICKUP_CANDIDATES = ["tpep_pickup_datetime", "lpep_pickup_datetime", "pickup_datetime"]
DROPOFF_CANDIDATES = ["tpep_dropoff_datetime", "lpep_dropoff_datetime", "dropoff_datetime"]


def _find_column(columns, candidates):
    for name in candidates:
        if name in columns:
            return name
    return None


def normalize_columns(df: pd.DataFrame) -> pd.DataFrame:
    """Normalize common TLC schema variations into standard column names."""
    out = df.copy()
    pickup = _find_column(out.columns, PICKUP_CANDIDATES)
    dropoff = _find_column(out.columns, DROPOFF_CANDIDATES)
    if pickup is None or dropoff is None:
        raise ValueError(
            "Required pickup/drop-off timestamp columns not found. "
            f"Available columns: {list(out.columns)}"
        )
    if pickup != "pickup_datetime":
        out = out.rename(columns={pickup: "pickup_datetime"})
    if dropoff != "dropoff_datetime":
        out = out.rename(columns={dropoff: "dropoff_datetime"})
    return out


def clean_trips(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Return (valid, quarantined) with optional source columns handled defensively."""
    out = normalize_columns(df).drop_duplicates().copy()
    out["pickup_datetime"] = pd.to_datetime(out["pickup_datetime"], errors="coerce")
    out["dropoff_datetime"] = pd.to_datetime(out["dropoff_datetime"], errors="coerce")

    for col in ("trip_distance", "fare_amount", "total_amount"):
        if col in out.columns:
            out[col] = pd.to_numeric(out[col], errors="coerce")

    invalid = (
        out["pickup_datetime"].isna()
        | out["dropoff_datetime"].isna()
        | (out["dropoff_datetime"] < out["pickup_datetime"])
    )
    if "trip_distance" in out.columns:
        invalid |= out["trip_distance"].notna() & (out["trip_distance"] < 0)
    if "fare_amount" in out.columns:
        invalid |= out["fare_amount"].notna() & (out["fare_amount"] < 0)

    quarantined = out.loc[invalid].copy()
    quarantined["quarantine_reason"] = "required timestamp invalid, negative duration, or invalid negative measure"
    valid = out.loc[~invalid].copy()
    valid["trip_date"] = valid["pickup_datetime"].dt.date.astype("string")
    valid["pickup_hour"] = valid["pickup_datetime"].dt.hour.astype("Int64")
    valid["trip_duration_minutes"] = (
        valid["dropoff_datetime"] - valid["pickup_datetime"]
    ).dt.total_seconds() / 60.0
    return valid, quarantined


def build_daily_metrics(valid: pd.DataFrame) -> pd.DataFrame:
    if valid.empty:
        return pd.DataFrame(columns=[
            "trip_date", "trip_count", "avg_trip_distance",
            "total_fare_amount", "total_amount"
        ])
    work = valid.copy()
    for col in ("trip_distance", "fare_amount", "total_amount"):
        if col not in work:
            work[col] = pd.NA
    return (
        work.groupby("trip_date", dropna=False)
        .agg(
            trip_count=("pickup_datetime", "size"),
            avg_trip_distance=("trip_distance", "mean"),
            total_fare_amount=("fare_amount", "sum"),
            total_amount=("total_amount", "sum"),
        )
        .reset_index()
    )


def build_pickup_zone_metrics(valid: pd.DataFrame) -> pd.DataFrame:
    if "PULocationID" not in valid.columns:
        return pd.DataFrame(columns=["PULocationID", "trip_count"])
    return (
        valid.groupby("PULocationID", dropna=False)
        .size().rename("trip_count").reset_index()
        .sort_values("trip_count", ascending=False)
    )


def run_pipeline(input_path: str | Path, output_dir: str | Path) -> dict:
    input_path, output_dir = Path(input_path), Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    raw = pd.read_parquet(input_path)
    valid, quarantined = clean_trips(raw)

    silver_dir, gold_dir = output_dir / "silver", output_dir / "gold"
    silver_dir.mkdir(parents=True, exist_ok=True)
    gold_dir.mkdir(parents=True, exist_ok=True)
    valid.to_parquet(silver_dir / "trips_clean.parquet", index=False)
    quarantined.to_parquet(silver_dir / "trips_quarantined.parquet", index=False)
    build_daily_metrics(valid).to_parquet(gold_dir / "daily_metrics.parquet", index=False)
    build_pickup_zone_metrics(valid).to_parquet(gold_dir / "pickup_zone_metrics.parquet", index=False)

    metrics = {
        "input_path": str(input_path),
        "input_rows": int(len(raw)),
        "valid_rows": int(len(valid)),
        "quarantined_rows": int(len(quarantined)),
        "duplicate_rows_removed_before_validation": int(len(raw) - len(raw.drop_duplicates())),
    }
    import json
    (output_dir / "run_metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    return metrics
