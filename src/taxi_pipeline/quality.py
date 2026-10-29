from __future__ import annotations
import pandas as pd


def validate_output(df: pd.DataFrame) -> list[str]:
    """Return a list of quality issues; an empty list means checks passed."""
    issues = []
    required = {"pickup_datetime", "dropoff_datetime", "trip_date"}
    missing = sorted(required - set(df.columns))
    if missing:
        issues.append(f"Missing required output columns: {missing}")
        return issues
    if df["pickup_datetime"].isna().any():
        issues.append("Null pickup_datetime values found")
    if df["dropoff_datetime"].isna().any():
        issues.append("Null dropoff_datetime values found")
    if (df["dropoff_datetime"] < df["pickup_datetime"]).any():
        issues.append("Drop-off precedes pickup")
    if df.duplicated().any():
        issues.append("Exact duplicate rows found")
    return issues
