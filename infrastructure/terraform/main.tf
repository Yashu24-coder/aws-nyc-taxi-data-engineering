terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "data_lake" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket                  = aws_s3_bucket.data_lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "require_tls" {
  bucket = aws_s3_bucket.data_lake.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.data_lake.arn,
        "${aws_s3_bucket.data_lake.arn}/*"
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "expire-temporary-objects"
    status = "Enabled"
    filter { prefix = "tmp/" }
    expiration { days = 7 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }

  rule {
    id     = "expire-athena-results"
    status = "Enabled"
    filter { prefix = "athena-results/" }
    expiration { days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue" {
  name               = "${var.resource_prefix}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role.json
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

data "aws_iam_policy_document" "glue_bucket_access" {
  statement {
    sid       = "ListProjectBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
    resources = [aws_s3_bucket.data_lake.arn]
  }
  statement {
    sid    = "ReadWriteProjectObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
      "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"
    ]
    resources = ["${aws_s3_bucket.data_lake.arn}/*"]
  }
}

resource "aws_iam_role_policy" "glue_bucket_access" {
  name   = "${var.resource_prefix}-glue-s3-access"
  role   = aws_iam_role.glue.id
  policy = data.aws_iam_policy_document.glue_bucket_access.json
}

resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "scripts/glue_transform.py"
  source = "${path.module}/../../glue/glue_transform.py"
  etag   = filemd5("${path.module}/../../glue/glue_transform.py")
}

resource "aws_glue_catalog_database" "taxi" {
  name        = var.glue_database_name
  description = "NYC taxi lakehouse database for the portfolio pipeline"
}

resource "aws_glue_job" "taxi_etl" {
  name              = "${var.resource_prefix}-taxi-etl"
  description       = "Clean NYC TLC taxi Parquet data and produce Silver/Gold outputs"
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 30
  max_retries       = 0

  command {
    name            = "glueetl"
    script_location = aws_s3_object.glue_script.s3_uri
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                    = "python"
    "--enable-metrics"                  = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-job-insights"              = "true"
    "--INPUT_PATH"                       = "s3://${var.bucket_name}/bronze/yellow/year=2024/month=01/"
    "--SILVER_PATH"                      = "s3://${var.bucket_name}/silver/trips/"
    "--GOLD_PATH"                        = "s3://${var.bucket_name}/gold/daily_metrics/"
    "--TempDir"                          = "s3://${var.bucket_name}/tmp/"
  }

  depends_on = [
    aws_iam_role_policy_attachment.glue_service,
    aws_iam_role_policy.glue_bucket_access
  ]
}

resource "aws_glue_crawler" "silver" {
  name          = "${var.resource_prefix}-silver-crawler"
  database_name = aws_glue_catalog_database.taxi.name
  role          = aws_iam_role.glue.arn

  s3_target { path = "s3://${var.bucket_name}/silver/trips/" }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  depends_on = [
    aws_iam_role_policy_attachment.glue_service,
    aws_iam_role_policy.glue_bucket_access
  ]
}

resource "aws_glue_crawler" "gold" {
  name          = "${var.resource_prefix}-gold-crawler"
  database_name = aws_glue_catalog_database.taxi.name
  role          = aws_iam_role.glue.arn

  s3_target { path = "s3://${var.bucket_name}/gold/daily_metrics/" }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  depends_on = [
    aws_iam_role_policy_attachment.glue_service,
    aws_iam_role_policy.glue_bucket_access
  ]
}

resource "aws_athena_workgroup" "taxi" {
  name = "${var.resource_prefix}-analytics"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${var.bucket_name}/athena-results/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}

output "data_lake_bucket" {
  value       = aws_s3_bucket.data_lake.bucket
  description = "S3 bucket for bronze, silver, gold, scripts and Athena results"
}

output "glue_database_name" {
  value       = aws_glue_catalog_database.taxi.name
  description = "AWS Glue Data Catalog database name"
}

output "glue_job_name" {
  value       = aws_glue_job.taxi_etl.name
  description = "AWS Glue ETL job name"
}

output "silver_crawler_name" {
  value       = aws_glue_crawler.silver.name
  description = "Crawler for the curated Silver table"
}

output "gold_crawler_name" {
  value       = aws_glue_crawler.gold.name
  description = "Crawler for the Gold metrics table"
}

output "athena_workgroup_name" {
  value       = aws_athena_workgroup.taxi.name
  description = "Athena workgroup configured for project query results"
}
