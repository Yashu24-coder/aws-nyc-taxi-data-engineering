# AWS NYC Taxi Data Engineering Pipeline

A portfolio project demonstrating data ingestion, cleaning, analytics-ready datasets, and a deployable AWS data lakehouse foundation.

## Architecture

NYC TLC Parquet → Amazon S3 Bronze → AWS Glue / PySpark → S3 Silver + Gold → Glue Data Catalog → Amazon Athena.

The local Python/pandas pipeline is for development and tests; AWS Glue runs the Spark transformation in the cloud.

## Data source

- Official NYC TLC trip records: https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page
- AWS Open Data Registry: https://registry.opendata.aws/nyc-tlc-trip-records-pds/

Check the source schema and month availability before running. The starter deployment example uses yellow taxi data for January 2024.

## Repository layout

- `src/taxi_pipeline/`: local transform and validation functions
- `glue/glue_transform.py`: AWS Glue Spark job
- `scripts/download_sample.py`: download a TLC file
- `scripts/run_local.py`: run the local mode
- `scripts/deploy_aws.sh`: Terraform + upload + Glue run + crawlers
- `infrastructure/terraform/`: AWS infrastructure
- `sql/`: Athena analysis queries
- `tests/`: unit tests

## Run locally

Python 3.10+:

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

## Deploy to AWS (creates billable resources)

**Prerequisites:** AWS account, AWS CLI v2, Terraform 1.5+, and an IAM identity authorized to create S3 buckets, IAM roles/policies, Glue jobs/crawlers/catalog resources, and Athena workgroups. Use your own account credentials or role; never paste access keys into chat or commit them.

1. Configure the CLI with your own AWS SSO/profile or credentials and verify the identity:

   ```bash
   aws sts get-caller-identity
   ```

2. Download a Parquet file locally (or use a compatible TLC Parquet file you already have):

   ```bash
   python scripts/download_sample.py --year 2024 --month 1
   ```

3. Create the Terraform variables file and choose a **globally unique** lowercase bucket name:

   ```bash
   cp infrastructure/terraform/terraform.tfvars.example infrastructure/terraform/terraform.tfvars
   ```

   Edit `bucket_name` in `terraform.tfvars`. This local file is ignored by Git.

4. Run the deployment script from the repository root:

   ```bash
   chmod +x scripts/deploy_aws.sh
   ./scripts/deploy_aws.sh data/raw/yellow_tripdata_2024-01.parquet 2024 1
   ```

   Terraform displays a plan and asks for confirmation before creating resources. The script then uploads data, starts the Glue ETL job, waits for completion, and starts the Silver/Gold crawlers. If the chosen TLC file/schema differs, inspect the Glue CloudWatch logs and adjust the script/arguments rather than assuming success.

5. In the AWS Console, open **AWS Glue → Data Catalog → Tables** to inspect discovered tables, then open **Amazon Athena**, choose the `nyc-taxi-analytics` workgroup (or your configured prefix), and run a query from `sql/`. If the database name or table name differs, update the SQL query to match the Catalog.

### What Terraform creates

- Private S3 bucket with public access blocked, default S3-managed encryption, versioning, TLS-only bucket policy, and expiry on temporary/Athena query result objects
- AWS Glue service role plus project-bucket access policy
- Uploaded Glue job script, Glue ETL job, Glue database, Silver and Gold crawlers
- Athena workgroup with encrypted query-results location

Terraform does not automatically start the Glue job; the deployment script does this after the resources exist and the data is uploaded.

## Run and review outputs

The pipeline produces:
- Silver validated trip data and a separate quarantine prefix
- Gold daily metrics
- Glue Data Catalog tables created by crawlers
- Athena SQL query results

Run the queries in `sql/` only after confirming the actual Catalog table names and required columns.

## Costs and cleanup

S3 storage/requests, Glue job runtime, and Athena bytes scanned can incur charges; Glue is the main likely cost driver in this starter setup. Start with a small file, check current prices in the AWS Region/account, and set an AWS Budget alert before running larger inputs. Temporary and Athena-result objects have lifecycle expiration, but data lake objects and deployed resources remain until removed.

To remove infrastructure **after checking the Terraform plan**:

```bash
terraform -chdir=infrastructure/terraform plan -destroy
terraform -chdir=infrastructure/terraform destroy
```

Destroying the stack can delete cloud infrastructure; back up any output you want to keep first. Terraform's local state file is required for cleanup—keep it private and do not commit it.

## Data quality rules

- Required pickup/drop-off timestamps must parse and drop-off cannot precede pickup.
- Negative trip distance and fare values are quarantined.
- Exact duplicate rows are dropped; this does not identify all real-world duplicate trips.

## Publish real measurements

Use `docs/benchmark-template.csv` to record source rows/file size, valid/quarantined rows, Glue duration, output size, Athena bytes scanned and query time. Do not claim performance improvements or cost savings until measured.

## Security

Never commit AWS access keys, credentials, `terraform.tfvars`, Terraform state, or local data. Use IAM roles/least privilege and delete the resources when finished.
