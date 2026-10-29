variable "bucket_name" {
  description = "Globally unique S3 bucket name for this portfolio project"
  type        = string
}

variable "aws_region" {
  description = "AWS Region to deploy into"
  type        = string
  default     = "ap-south-1"
}
