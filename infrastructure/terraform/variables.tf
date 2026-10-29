variable "bucket_name" {
  description = "Globally unique S3 bucket name, lowercase letters/numbers/hyphens only"
  type        = string
}

variable "aws_region" {
  description = "AWS Region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "resource_prefix" {
  description = "Short prefix for named AWS resources; use lowercase letters, numbers, and hyphens"
  type        = string
  default     = "nyc-taxi"
}

variable "glue_database_name" {
  description = "Glue Data Catalog database name"
  type        = string
  default     = "taxi_lakehouse"
}
