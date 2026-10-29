#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/deploy_aws.sh data/raw/yellow_tripdata_2024-01.parquet [year] [month]
# Creates AWS resources with Terraform, uploads the Parquet file, runs Glue ETL,
# and starts the Glue crawlers. This can incur AWS charges.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/infrastructure/terraform"
INPUT_FILE="${1:-}"
YEAR="${2:-2024}"
MONTH="${3:-1}"

if [[ -z "$INPUT_FILE" || ! -f "$INPUT_FILE" ]]; then
  echo "Usage: $0 /path/to/yellow_tripdata_YYYY-MM.parquet [year] [month]" >&2
  exit 2
fi
if ! command -v aws >/dev/null 2>&1; then echo "AWS CLI v2 is required." >&2; exit 2; fi
if ! command -v terraform >/dev/null 2>&1; then echo "Terraform 1.5+ is required." >&2; exit 2; fi

echo "Checking AWS identity..."
aws sts get-caller-identity

if [[ ! -f "$TF_DIR/terraform.tfvars" ]]; then
  echo "Missing $TF_DIR/terraform.tfvars."
  echo "Copy terraform.tfvars.example to terraform.tfvars and set a unique S3 bucket name."
  exit 2
fi

echo "Initializing Terraform..."
terraform -chdir="$TF_DIR" init
echo "Review the plan. Terraform apply will ask for confirmation before creating resources."
terraform -chdir="$TF_DIR" plan
terraform -chdir="$TF_DIR" apply

BUCKET="$(terraform -chdir="$TF_DIR" output -raw data_lake_bucket)"
JOB_NAME="$(terraform -chdir="$TF_DIR" output -raw glue_job_name)"
SILVER_CRAWLER="$(terraform -chdir="$TF_DIR" output -raw silver_crawler_name)"
GOLD_CRAWLER="$(terraform -chdir="$TF_DIR" output -raw gold_crawler_name)"

MONTH_PADDED="$(printf "%02d" "$MONTH")"
S3_KEY="bronze/yellow/year=$YEAR/month=$MONTH_PADDED/$(basename "$INPUT_FILE")"
echo "Uploading dataset to s3://$BUCKET/$S3_KEY ..."
aws s3 cp "$INPUT_FILE" "s3://$BUCKET/$S3_KEY"

INPUT_URI="s3://$BUCKET/bronze/yellow/year=$YEAR/month=$MONTH_PADDED/"
SILVER_URI="s3://$BUCKET/silver/trips/"
GOLD_URI="s3://$BUCKET/gold/daily_metrics/"
TEMP_URI="s3://$BUCKET/tmp/"

echo "Starting AWS Glue ETL job..."
JOB_ARGS="{\"--INPUT_PATH\":\"$INPUT_URI\",\"--SILVER_PATH\":\"$SILVER_URI\",\"--GOLD_PATH\":\"$GOLD_URI\",\"--TempDir\":\"$TEMP_URI\"}"
RUN_ID="$(aws glue start-job-run --job-name "$JOB_NAME" \
  --arguments "$JOB_ARGS" \
  --query 'JobRunId' --output text)"
echo "Glue JobRunId: $RUN_ID"

while true; do
  STATUS="$(aws glue get-job-run --job-name "$JOB_NAME" --run-id "$RUN_ID" --query 'JobRun.JobRunState' --output text)"
  echo "Glue status: $STATUS"
  case "$STATUS" in
    SUCCEEDED) break ;;
    FAILED|TIMEOUT|STOPPED|ERROR)
      aws glue get-job-run --job-name "$JOB_NAME" --run-id "$RUN_ID" --query 'JobRun.ErrorMessage' --output text || true
      exit 1
      ;;
    *) sleep 20 ;;
  esac
done

for CRAWLER in "$SILVER_CRAWLER" "$GOLD_CRAWLER"; do
  echo "Starting crawler $CRAWLER..."
  aws glue start-crawler --name "$CRAWLER"
  # Wait for the crawler to enter RUNNING, then finish back at READY.
  while true; do
    STATE="$(aws glue get-crawler --name "$CRAWLER" --query 'Crawler.State' --output text)"
    [[ "$STATE" == "RUNNING" ]] && break
    sleep 5
  done
  while true; do
    STATE="$(aws glue get-crawler --name "$CRAWLER" --query 'Crawler.State' --output text)"
    [[ "$STATE" == "READY" ]] && break
    sleep 10
  done
done

CLI_REGION="$(aws configure get region 2>/dev/null || true)"
echo
echo "Deployment and first ETL run finished."
echo "Bucket: s3://$BUCKET/"
echo "Glue database: $(terraform -chdir="$TF_DIR" output -raw glue_database_name)"
echo "Athena workgroup: $(terraform -chdir="$TF_DIR" output -raw athena_workgroup_name)"
echo "Open Athena in configured AWS Region: ${CLI_REGION:-check your configured AWS Region}."
echo "Remember to clean up resources when finished; see README.md."
