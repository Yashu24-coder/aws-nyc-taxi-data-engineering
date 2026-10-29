import argparse
from pathlib import Path
import requests

BASE_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{year}-{month:02d}.parquet"


def main():
    parser = argparse.ArgumentParser(description="Download a NYC TLC yellow taxi Parquet file.")
    parser.add_argument("--year", type=int, default=2024)
    parser.add_argument("--month", type=int, default=1, choices=range(1, 13))
    parser.add_argument("--out-dir", default="data/raw")
    args = parser.parse_args()
    url = BASE_URL.format(year=args.year, month=args.month)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    destination = out_dir / f"yellow_tripdata_{args.year}-{args.month:02d}.parquet"

    response = requests.get(url, timeout=120, stream=True)
    response.raise_for_status()
    with destination.open("wb") as f:
        for chunk in response.iter_content(chunk_size=1024 * 1024):
            if chunk:
                f.write(chunk)
    print(f"Downloaded: {destination}")
    print("Check the official TLC page if the selected period is unavailable.")


if __name__ == "__main__":
    main()
