#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="us-east-1"   # set your region if needed for IAM (IAM is global usually)
AWS_ACCOUNT_ID="615299732970"

# The OIDC URL to match
OIDC_URL="token.actions.githubusercontent.com"

echo "Looking for OIDC provider matching '${OIDC_URL}' in account ${AWS_ACCOUNT_ID}..."

# Get list of OIDC provider ARNs
provider_arns=$(aws iam list-open-id-connect-providers \
  | jq -r ".OpenIDConnectProviderList[].Arn")

if [ -z "$provider_arns" ]; then
  echo "No OIDC providers found."
  exit 0
fi

# Filter for providers that include the GitHub URL
matching=""
for arn in $provider_arns; do
  details=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$arn")
  issuer=$(echo "$details" | jq -r '.Url')
  if echo "$issuer" | grep -q "$OIDC_URL"; then
    matching="$matching $arn"
  fi
done

if [ -z "$matching" ]; then
  echo "No matching OIDC provider found for GitHub Actions."
  exit 0
fi

for arn in $matching; do
  echo "Deleting OIDC provider: $arn"
  aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$arn"
  echo "Deleted $arn"
done

echo "Done."