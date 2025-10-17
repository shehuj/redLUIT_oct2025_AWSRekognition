#!/usr/bin/env bash
set -euo pipefail

### 👇 Configuration — YOU MUST EDIT THESE
AWS_ACCOUNT_ID="615299735647"
GITHUB_ORG="YourOrg"
GITHUB_REPO="YourRepo"
AWS_REGION="us-east-1"

# The role name you want to create
ROLE_NAME="GitHubActionsOIDCRole"

# Permissions you want to grant — customize as needed
# Here’s an example policy JSON string
read_policy_json=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject", "s3:GetObject", "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::your-bucket-name",
        "arn:aws:s3:::your-bucket-name/*"
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

### 👍 End of config

# Validate required tools
for cmd in aws jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' is required but not installed."
    exit 1
  fi
done

echo "Using AWS account: $AWS_ACCOUNT_ID, GitHub repo: $GITHUB_ORG/$GITHUB_REPO, region: $AWS_REGION"

# 1. Create / ensure the OIDC provider for GitHub exists
OIDC_PROVIDER_ARN=$(aws iam list-open-id-connect-providers \
  | jq -r ".OpenIDConnectProviderList[] | select(test(\"token.actions.githubusercontent.com\"))" \
  | xargs -I{} aws iam get-open-id-connect-provider --open-id-connect-provider-arn {} \
          | jq -r ".OpenIDConnectProviderArn" \
  || true)

if [ -z "$OIDC_PROVIDER_ARN" ] || [ "$OIDC_PROVIDER_ARN" = "null" ]; then
  echo "Creating new OIDC provider for GitHub Actions..."
  # Without specifying thumbprint (AWS now can derive it)
  OIDC_PROVIDER_ARN=$(aws iam create-open-id-connect-provider \
    --url "https://token.actions.githubusercontent.com" \
    --client-id-list "sts.amazonaws.com" \
    | jq -r ".OpenIDConnectProviderArn")
  echo "Created OIDC provider ARN: $OIDC_PROVIDER_ARN"
else
  echo "Found existing OIDC provider: $OIDC_PROVIDER_ARN"
fi

# 2. Build trust policy JSON file
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

# 3. Create the role (or catch if already exists)
echo "$TRUST_POLICY" > trust-policy.json

role_exists=$(aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null || true)
if [ -z "$role_exists" ]; then
  echo "Creating IAM role '$ROLE_NAME'..."
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document file://trust-policy.json
else
  echo "Role '$ROLE_NAME' already exists."
  # Optionally update trust policy:
  aws iam update-assume-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-document file://trust-policy.json
  echo "Updated trust policy for existing role."
fi

# 4. Attach the permissions policy (inline) to the role
echo "Attaching permissions policy to '$ROLE_NAME'..."
echo "$read_policy_json" > permissions-policy.json

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "GitHubActionsPermissionsPolicy" \
  --policy-document file://permissions-policy.json

# 5. Fetch & output the role ARN
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text)
echo "✅ Role ARN: $ROLE_ARN"

echo ""
echo "Now, go to your GitHub repository → Settings → Secrets and Variables → Actions"
echo "and add a secret (e.g. AWS_GITHUB_OIDC_ROLE_ARN) with value:"
echo "  $ROLE_ARN"
echo ""
echo "Then update your GitHub Actions workflow to use that secret in configure-aws-credentials step."

# 6. (Optional) Update GitHub secret via gh CLI if installed and authenticated
if command -v gh >/dev/null; then
  read -p "Do you want to set the secret automatically via gh CLI? (y/n) " yn
  if [ "$yn" = "y" ]; then
    gh secret set AWS_GITHUB_OIDC_ROLE_ARN --body "$ROLE_ARN"
    echo "Secret updated in GitHub repo via gh CLI."
  else
    echo "Skipped automatic GitHub secret setup."
  fi
fi

echo "Script complete."