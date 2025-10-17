variable "s3_bucket" {
  type        = string
  description = "S3 bucket name to attach notification"
}

variable "lambda_arn" {
  type        = string
  description = "Lambda function ARN to invoke"
}

variable "prefix_filter" {
  type        = string
  description = "S3 prefix filter (e.g. rekognition-input/beta/)"
}