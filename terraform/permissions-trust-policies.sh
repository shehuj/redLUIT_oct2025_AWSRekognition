#!/usr/bin/env bash
set -euo pipefail

### 👇 Configuration — YOU MUST EDIT THESE
AWS_ACCOUNT_ID="615299732970"
GITHUB_ORG="shehuj"
GITHUB_REPO="redLUIT_oct2025_AWSRekognition"
AWS_REGION="us-east-1"

ROLE_NAME="GitHubActionsOIDCNewRole"

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
        "lambda:*",
        "cloudformation:*",
        "dynamodb:*",
        "iam:PassRole"
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
    }
  ]
}
EOF
)

### End of config

# Validate that required commands exist
for cmd in aws jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' is required but not installed."
    exit 1
  fi
done

echo "Using AWS account: $AWS_ACCOUNT_ID, GitHub repo: $GITHUB_ORG/$GITHUB_REPO, region: $AWS_REGION"

## 1. Ensure OIDC provider exists (or skip if exists)
echo "==> Checking for existing OIDC provider..."
OIDC_PROVIDER_ARN=$(aws iam list-open-id-connect-providers \
  | jq -r ".OpenIDConnectProviderList[] | select(test(\"token.actions.githubusercontent.com\"))" \
  | xargs -r -I{} aws iam get-open-id-connect-provider --open-id-connect-provider-arn {} \
      | jq -r ".Arn" || true)

if [ -z "$OIDC_PROVIDER_ARN" ] || [ "$OIDC_PROVIDER_ARN" = "null" ]; then
  echo "OIDC provider not found. Creating one..."
  OIDC_PROVIDER_ARN=$(aws iam create-open-id-connect-provider \
    --url "https://token.actions.githubusercontent.com" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" \
    | jq -r ".OpenIDConnectProviderArn")
  echo "Created new OIDC provider: $OIDC_PROVIDER_ARN"
else
  echo "OIDC provider already exists: $OIDC_PROVIDER_ARN"
fi

## 2. Build trust policy JSON
TRUST_POLICY=$(jq -n \
  --arg fid "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" \
  --arg sub1 "repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/main" \
  --arg sub2 "repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/*" \
  '{
    Version: "2012-10-17",
    Statement: [
      {
        Effect: "Allow",
        Principal: {
          Federated: $fid
        },
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

## 3. Create or update IAM role with trust policy
echo "==> Checking IAM role '$ROLE_NAME'..."
role_info=$(aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null || true)
if [ -z "$role_info" ]; then
  echo "Role does not exist. Creating role..."
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document file://trust-policy.json
  echo "Role '$ROLE_NAME' created."
else
  echo "Role '$ROLE_NAME' already exists. Updating trust policy..."
  aws iam update-assume-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-document file://trust-policy.json
  echo "Trust policy updated."
fi

## 4. Attach (or skip) permissions policy
echo "==> Checking if permissions policy is already attached..."
policy_names=$(aws iam list-role-policies --role-name "$ROLE_NAME" | jq -r ".PolicyNames[]")
if echo "$policy_names" | grep -q "GitHubActionsPermissionsPolicy"; then
  echo "Permissions policy 'GitHubActionsPermissionsPolicy' already exists on role. Skipping."
else
  echo "Attaching permissions policy to role..."
  echo "$read_policy_json" > permissions-policy.json
  aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "GitHubActionsPermissionsPolicy" \
    --policy-document file://permissions-policy.json
  echo "Permissions policy attached."
fi

## 5. Retrieve and print role ARN
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text)
echo "✅ Role ARN: $ROLE_ARN"

echo
echo "Add or update your GitHub secret (e.g. AWS_GITHUB_OIDC_ROLE_ARN) in the repo settings with:"
echo "  $ROLE_ARN"
echo
echo "Update your GitHub Actions workflow to use that secret in the configure-aws-credentials step."

## 6. Optionally set GitHub secret via gh CLI
if command -v gh >/dev/null; then
  read -p "Would you like to set the secret automatically (via gh CLI)? y/n: " yn
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    gh secret set AWS_GITHUB_OIDC_ROLE_ARN --body "$ROLE_ARN"
    echo "Secret AWS_GITHUB_OIDC_ROLE_ARN set via gh CLI."
  else
    echo "Skipping GitHub secret update."
  fi
fi

echo "Script complete."