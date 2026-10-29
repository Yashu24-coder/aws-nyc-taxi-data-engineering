# AWS NYC Taxi Data Engineering Pipeline

A portfolio-ready starter project demonstrating batch ingestion, data cleaning, analytics-ready datasets, data quality checks, and an AWS deployment path.

## Architecture

NYC TLC Parquet files → S3 Bronze → AWS Glue / PySpark → S3 Silver + Gold (Parquet) → Glue Data Catalog → Amazon Athena

A local mode is included so the pipeline and tests can be demonstrated without AWS credentials. The local runner uses Python and pandas; the AWS Glue script is a separate Spark job.

## Dataset

- Official NYC TLC trip records: https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page
- AWS Open Data Registry: https://registry.opendata.aws/nyc-tlc-trip-records-pds/

The example download script defaults to January 2024 yellow taxi data. Verify that the chosen month is available before running. Dataset schemas can change across years; the pipeline validates required columns and reports schema problems.

## Setup locally

Python 3.10+ is recommended.

```bash
python -m venv .venv
# Windows PowerShell:
.venv\Scripts\Activate.ps1
# macOS/Linux:
# source .venv/bin/activate

pip install -r requirements.txt
python scripts/download_sample.py --year 2024 --month 1
python scripts/run_local.py --input data/raw/yellow_tripdata_2024-01.parquet --output data/output
pytest -q
```

The local pipeline writes cleaned/quarantined Silver datasets, Gold daily and pickup-zone metrics, and run metrics. It is a development/test harness, not a substitute for running Spark on AWS Glue at scale.

## AWS deployment outline

1. Create a dedicated S3 bucket in your chosen AWS Region and upload source files under a bronze prefix.
2. Create an IAM role for Glue with access limited to the project bucket and required Glue operations.
3. Upload `glue/glue_transform.py` to an S3 scripts prefix and create a Glue Spark job. Pass `--INPUT_PATH`, `--SILVER_PATH`, and `--GOLD_PATH`.
4. Configure the Glue Data Catalog database and register output tables or run a crawler.
5. Query tables in Athena and set an S3 query-results location.
6. Enable CloudWatch logging and configure budget alerts.

The Terraform files provide a minimal S3 bucket foundation only. IAM, Glue jobs, catalog resources, lifecycle policies, and account-specific settings must be reviewed and completed for your environment before production use.

## Data quality rules

- Pickup and drop-off timestamps must parse; drop-off cannot precede pickup.
- Trip distance and fare amount must be non-negative when present.
- Required-field failures are quarantined; missing optional fields remain null.
- Exact duplicate rows are dropped; this does not identify all real-world duplicate trips.

## Benchmarks

Run the same input repeatedly and record input size/rows, valid and quarantined rows, runtime, output size, Athena bytes scanned/query time, and actual AWS costs if applicable. Fill `docs/benchmark-template.csv` with measured results. Do not claim percentage improvements until you measure comparable runs.

## Security

Never commit AWS access keys, credentials, `.env` files, personal data, or Terraform state. Use IAM roles and least privilege. Delete resources after experiments to avoid ongoing charges.
