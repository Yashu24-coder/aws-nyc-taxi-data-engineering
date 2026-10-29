import pandas as pd
from taxi_pipeline.quality import validate_output


def test_quality_passes_for_valid_rows():
    df = pd.DataFrame({
        "pickup_datetime": pd.to_datetime(["2024-01-01 08:00"]),
        "dropoff_datetime": pd.to_datetime(["2024-01-01 08:10"]),
        "trip_date": ["2024-01-01"],
    })
    assert validate_output(df) == []


def test_quality_flags_negative_duration():
    df = pd.DataFrame({
        "pickup_datetime": pd.to_datetime(["2024-01-01 08:10"]),
        "dropoff_datetime": pd.to_datetime(["2024-01-01 08:00"]),
        "trip_date": ["2024-01-01"],
    })
    assert any("precedes pickup" in issue for issue in validate_output(df))
