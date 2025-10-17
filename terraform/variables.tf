variable "aws_region" {
  type        = string
  description = "AWS region"
}
variable "s3_bucket_name" {
  type        = string
  description = "S3 bucket name for storing Rekognition images"
  default     = "ec2-shutdown-lambda-bucket"

}

variable "dynamodb_table_name" {
  type        = string
  description = "DynamoDB table name for storing Rekognition metadata"
}