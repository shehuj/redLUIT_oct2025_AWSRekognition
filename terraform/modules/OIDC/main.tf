
##########################
# 1. Create / reference the OIDC provider
##########################

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = [
    "sts.amazonaws.com",
  ]
  # The thumbprint is commonly “6938fd4d98bab03faadb97b34396831e3780aea1” for GitHub Actions OIDC
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]
}

##########################
# 2. IAM Role assuming via OIDC
##########################

data "aws_iam_policy_document" "github_oidc_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Adjust this to your repo / branch. For example:
      # repo:MyOrg/MyRepo:ref:refs/heads/main
      # You can use wildcard for branches: e.g. "repo:MyOrg/MyRepo:*"
      values = [
        "repo:MyOrg/MyRepo:ref:refs/heads/main",
        "repo:MyOrg/MyRepo:ref:refs/heads/*"
      ]
    }
  }
}

resource "aws_iam_role" "github_actions_role" {
  name               = "GitHubActionsOIDCRole"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume.json
}

##########################
# 3. Attach policies to the role
##########################

# Example: you may want your role to have permissions to manage Lambda, S3, DynamoDB, etc.
resource "aws_iam_policy" "github_actions_policy" {
  name        = "GitHubActionsPolicy"
  description = "Permissions for GitHub Actions to deploy infra"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          # adjust these ARNs to your bucket(s)
          "arn:aws:s3:::your-bucket-name",
          "arn:aws:s3:::your-bucket-name/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:UpdateFunctionCode",
          "lambda:InvokeFunction",
          "lambda:GetFunction",
          "lambda:DeleteFunction"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Resource = [
          # your DynamoDB table ARNs
          "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/your-beta-table",
          "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/your-prod-table"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_github_actions" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.github_actions_policy.arn
}

##########################
# 4. Output the Role ARN
##########################

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_role.arn
}