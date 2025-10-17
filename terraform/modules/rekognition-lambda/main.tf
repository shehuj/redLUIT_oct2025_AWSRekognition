resource "aws_iam_role" "lambda_exec" {
  name = "${var.lambda_name}-exec-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "rekognition:DetectLabels",
      "s3:GetObject",
      "dynamodb:PutItem",
    ]
    resources = concat(
      [var.s3_bucket],
      [for p in var.s3_prefixes_to_read : "${var.s3_bucket}/${p}*"]
    )
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy" "lambda_policy_attach" {
  name = "${var.lambda_name}-policy"
  role = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_lambda_function" "this" {
  function_name = var.lambda_name
  runtime       = "python3.11"
  handler       = "lambda_handler.lambda_handler"
  role          = aws_iam_role.lambda_exec.arn
  filename      = var.handler_file  # you can also use S3 or local zip

  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table
      BRANCH         = var.branch_name
    }
  }

  # If you use large dependencies, you might build and upload separately
}