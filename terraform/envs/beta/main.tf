module "rek_lambda_beta" {
  source = "../../modules/rekognition-lambda"

  lambda_name        = "rekognition-beta-handler"
  handler_file       = "${path.module}/../../modules/rekognition-lambda/lambda_handler.py"
  dynamodb_table     = var.dynamodb_table_beta
  branch_name        = "beta"
  s3_bucket          = var.s3_bucket
  s3_prefixes_to_read = ["rekognition-input/beta/"]
}

module "s3_notify_beta" {
  source = "../../modules/s3-notify"
  s3_bucket    = var.s3_bucket
  lambda_arn   = module.rek_lambda_beta.lambda_arn
  prefix_filter = "rekognition-input/beta/"
}