import pandas as pd
from taxi_pipeline.transform import clean_trips, build_daily_metrics, build_pickup_zone_metrics


def sample_data():
    return pd.DataFrame({
        "tpep_pickup_datetime": [
            "2024-01-01 08:00:00", "2024-01-01 09:00:00",
            "bad-date", "2024-01-02 10:00:00",
        ],
        "tpep_dropoff_datetime": [
            "2024-01-01 08:20:00", "2024-01-01 09:15:00",
            "2024-01-01 09:30:00", "2024-01-02 09:00:00",
        ],
        "trip_distance": [2.5, 1.2, 3.0, -1.0],
        "fare_amount": [12.0, 8.0, 15.0, 5.0],
        "total_amount": [16.0, 11.0, 20.0, 7.0],
        "PULocationID": [100, 100, 101, 102],
    })


def test_clean_trips_quarantines_invalid_rows():
    valid, bad = clean_trips(sample_data())
    assert len(valid) == 2
    assert len(bad) == 2
    assert "trip_date" in valid.columns
    assert "quarantine_reason" in bad.columns


def test_daily_metrics_counts_valid_rows():
    valid, _ = clean_trips(sample_data())
    daily = build_daily_metrics(valid)
    assert int(daily["trip_count"].sum()) == 2


def test_pickup_zone_metrics():
    valid, _ = clean_trips(sample_data())
    zones = build_pickup_zone_metrics(valid)
    assert int(zones["trip_count"].sum()) == 2
    assert zones.iloc[0]["PULocationID"] == 100
