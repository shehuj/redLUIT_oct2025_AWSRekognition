#!/usr/bin/env bash
set -euo pipefail

### 👇 Configuration
AWS_ACCOUNT_ID="615299732970"
GITHUB_ORG="shehuj"
GITHUB_REPO="redLUIT_oct2025_AWSRekognition"
AWS_REGION="us-east-1"
ROLE_NAME="GitHubActionsOIDCNewRole"

# 👇 Permissions policy (includes S3, Rekognition, Lambda, Terraform, Logs, etc.)
read_policy_json=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::ec2-shutdown-lambda-bucket",
        "arn:aws:s3:::ec2-shutdown-lambda-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "rekognition:*",
        "lambda:*",
        "cloudformation:*",
        "dynamodb:*",
        "iam:PassRole",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "iam:List*",
        "iam:Get*",
        "s3:ListAllMyBuckets"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "terraform:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)

# Validate required tools
for cmd in aws jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ Error: '$cmd' is required but not installed."
    exit 1
  fi
done

echo "🔧 Using AWS account: $AWS_ACCOUNT_ID, Repo: $GITHUB_ORG/$GITHUB_REPO, Region: $AWS_REGION"

### 1️⃣ Ensure OIDC Provider exists (or skip)
echo "==> Checking for existing OIDC provider..."
OIDC_PROVIDER_ARN=$(aws iam list-open-id-connect-providers \
  | jq -r ".OpenIDConnectProviderList[] | select(.Arn | test(\"token.actions.githubusercontent.com\"))" \
  | xargs -r -I{} aws iam get-open-id-connect-provider --open-id-connect-provider-arn {} \
      | jq -r ".Arn" || true)

if [ -z "$OIDC_PROVIDER_ARN" ] || [ "$OIDC_PROVIDER_ARN" = "null" ]; then
  echo "Creating new GitHub OIDC provider..."
  OIDC_PROVIDER_ARN=$(aws iam create-open-id-connect-provider \
    --url "https://token.actions.githubusercontent.com" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" \
    | jq -r ".OpenIDConnectProviderArn")
  echo "✅ Created OIDC provider: $OIDC_PROVIDER_ARN"
else
  echo "✅ OIDC provider already exists: $OIDC_PROVIDER_ARN"
fi

### 2️⃣ Build Trust Policy
TRUST_POLICY=$(jq -n \
  --arg fid "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" \
  --arg sub1 "repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/main" \
  --arg sub2 "repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/*" \
  '{
    Version: "2012-10-17",
    Statement: [
      {
        Effect: "Allow",
        Principal: { Federated: $fid },
        Action: "sts:AssumeRoleWithWebIdentity",
        Condition: {
          StringEquals: {
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
          },
          StringLike: {
            "token.actions.githubusercontent.com:sub": [$sub1, $sub2]
          }
        }
      }
    ]
  }')

echo "$TRUST_POLICY" > trust-policy.json

### 3️⃣ Create or Update IAM Role
echo "==> Checking IAM Role '$ROLE_NAME'..."
if ! aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
  echo "Creating role '$ROLE_NAME'..."
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document file://trust-policy.json
  echo "✅ Role created."
else
  echo "Role already exists. Updating trust policy..."
  aws iam update-assume-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-document file://trust-policy.json
  echo "✅ Trust policy updated."
fi

### 4️⃣ Attach Inline Policy (skip if exists)
echo "==> Checking inline policies..."
POLICY_EXISTS=$(aws iam list-role-policies --role-name "$ROLE_NAME" | jq -r '.PolicyNames[]' | grep -Fx "GitHubActionsPermissionsPolicy" || true)
if [ -n "$POLICY_EXISTS" ]; then
  echo "Policy already exists — updating instead of re-attaching."
  echo "$read_policy_json" > permissions-policy.json
  aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "GitHubActionsPermissionsPolicy" \
    --policy-document file://permissions-policy.json
else
  echo "Attaching new inline permissions policy..."
  echo "$read_policy_json" > permissions-policy.json
  aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "GitHubActionsPermissionsPolicy" \
    --policy-document file://permissions-policy.json
  echo "✅ Policy attached."
fi

### 5️⃣ Print Role ARN
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text)
echo ""
echo "✅ ROLE READY: $ROLE_ARN"
echo ""
echo "👉 Add to your GitHub repo secrets as:"
echo "   AWS_GITHUB_OIDC_ROLE_ARN = $ROLE_ARN"
echo ""
echo "Then reference it in your GitHub Actions workflow under:"
echo "   role-to-assume: \${{ secrets.AWS_GITHUB_OIDC_ROLE_ARN }}"

### 6️⃣ Optional — Auto-set GitHub secret via gh CLI
if command -v gh >/dev/null; then
  read -p "Set GitHub secret automatically via gh CLI? (y/n): " yn
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    gh secret set AWS_GITHUB_OIDC_ROLE_ARN --body "$ROLE_ARN"
    echo "✅ Secret set in GitHub."
  else
    echo "Skipped setting GitHub secret."
  fi
fi

echo ""
echo "🎯 Complete! OIDC + IAM role setup finished successfully."