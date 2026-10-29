# Architecture and design decisions

## Layers
- **Bronze:** source Parquet files preserved with source-period prefixes.
- **Silver:** normalized timestamps, validated measures, exact duplicate removal, and quarantined invalid records.
- **Gold:** daily and pickup-zone aggregates designed for analytics.

## Why these AWS services?
- **Amazon S3:** durable object storage for raw and curated data.
- **AWS Glue / PySpark:** managed batch transformations.
- **Glue Data Catalog:** shared table and schema metadata.
- **Amazon Athena:** serverless SQL over S3.
- **CloudWatch:** logs, metrics and alarms.
- **Step Functions (extension):** visible orchestration and failure handling.

## Design caveats
- Source schemas differ by taxi type and year. Confirm columns before deployment.
- Exact duplicate removal is not the same as identifying duplicate real-world trips.
- The starter Glue script uses overwrite writes for clarity. For true incremental production loads, use controlled partition replacement or transactional table formats, and add a manifest/run ledger.
- Use a separate quarantine prefix and define retention for rejected records.
- Set up lifecycle rules and a cost budget before processing large datasets.
