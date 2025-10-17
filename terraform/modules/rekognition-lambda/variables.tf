variable "lambda_name" {
  type        = string
  description = "Name of the Lambda function"
}

variable "handler_file" {
  type        = string
  description = "Path to the lambda handler file (relative in module directory) to package"
}

variable "dynamodb_table" {
  type        = string
  description = "DynamoDB table that lambda writes results to"
}

variable "branch_name" {
  type        = string
  description = "Branch identifier (beta / prod) passed to function via env var"
}

variable "s3_bucket" {
  type        = string
  description = "S3 bucket name (for permissions/read access)"
}

variable "s3_prefixes_to_read" {
  type        = list(string)
  description = "List of S3 key prefixes (within bucket) the Lambda should be triggered from / have read access to"
  default     = []
}