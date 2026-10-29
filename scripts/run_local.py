import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
from taxi_pipeline.transform import run_pipeline


def main():
    parser = argparse.ArgumentParser(description="Run the local NYC taxi data pipeline.")
    parser.add_argument("--input", required=True, help="Input Parquet file")
    parser.add_argument("--output", default="data/output")
    args = parser.parse_args()
    metrics = run_pipeline(args.input, args.output)
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
