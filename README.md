# redLUIT_oct2025_AWSRekognition
This repo automates the tagging of image contents and classification for Pixel Learning Co., a digital-first education startup focused on visual learning tools.


# Amazon Rekognition Image Analysis CI/CD Pipeline

This repository implements an automated CI/CD pipeline that analyzes image files using Amazon Rekognition and logs the results in branch-specific DynamoDB tables.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [AWS Resources Setup](#aws-resources-setup)
- [GitHub Configuration](#github-configuration)
- [Usage](#usage)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

## Overview

This pipeline automatically processes images through Amazon Rekognition when:
- **Pull Requests** are created targeting the main branch → Results stored in `beta_results` table
- **Merges** occur to the main branch → Results stored in `prod_results` table

The system detects labels in images with confidence scores and maintains a complete audit trail in DynamoDB.

## Architecture

```
GitHub Repository
├── images/                  # Image files to analyze
├── scripts/
│   └── analyze_image.py    # Main processing script
├── .github/workflows/
│   ├── on_pull_request.yml # PR workflow
│   └── on_merge.yml        # Merge workflow
└── README.md
```

**Data Flow:**
1. Images added to `images/` folder
2. GitHub Actions triggered (PR or merge)
3. Images uploaded to S3 bucket
4. Amazon Rekognition analyzes images
5. Results stored in DynamoDB

## Prerequisites

Before setting up this pipeline, ensure you have:

- AWS Account with appropriate permissions
- GitHub repository (public or private)
- AWS CLI installed locally (for initial setup)
- Python 3.8+ for local testing

## AWS Resources Setup

### 1. Create S3 Bucket

```bash
# Create the S3 bucket
aws s3api create-bucket \
  --bucket your-rekognition-images-bucket \
  --region us-east-1

# Enable versioning (recommended)
aws s3api put-bucket-versioning \
  --bucket your-rekognition-images-bucket \
  --versioning-configuration Status=Enabled
```

### 2. Create DynamoDB Tables

Create two tables for beta and production results:

#### Beta Results Table

```bash
aws dynamodb create-table \
  --table-name beta_results \
  --attribute-definitions \
    AttributeName=filename,AttributeType=S \
    AttributeName=timestamp,AttributeType=S \
  --key-schema \
    AttributeName=filename,KeyType=HASH \
    AttributeName=timestamp,KeyType=RANGE \
  --provisioned-throughput \
    ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-east-1
```

#### Production Results Table

```bash
aws dynamodb create-table \
  --table-name prod_results \
  --attribute-definitions \
    AttributeName=filename,AttributeType=S \
    AttributeName=timestamp,AttributeType=S \
  --key-schema \
    AttributeName=filename,KeyType=HASH \
    AttributeName=timestamp,KeyType=RANGE \
  --provisioned-throughput \
    ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-east-1
```

### 3. Create IAM User for GitHub Actions

Create an IAM user with programmatic access:

```bash
aws iam create-user --user-name github-rekognition-pipeline
aws iam create-access-key --user-name github-rekognition-pipeline
```

Save the Access Key ID and Secret Access Key for GitHub configuration.

### 4. Attach IAM Policy

Create a policy file `rekognition-pipeline-policy.json`:

```json
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
        "arn:aws:s3:::your-rekognition-images-bucket",
        "arn:aws:s3:::your-rekognition-images-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "rekognition:DetectLabels"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ],
      "Resource": [
        "arn:aws:dynamodb:*:*:table/beta_results",
        "arn:aws:dynamodb:*:*:table/prod_results"
      ]
    }
  ]
}
```

Apply the policy:

```bash
aws iam put-user-policy \
  --user-name github-rekognition-pipeline \
  --policy-name RekognitionPipelinePolicy \
  --policy-document file://rekognition-pipeline-policy.json
```

## GitHub Configuration

### Setting Up Repository Secrets

Navigate to your GitHub repository → Settings → Secrets and variables → Actions

Add the following secrets:

| Secret Name | Description | Example Value |
|------------|-------------|---------------|
| `AWS_ACCESS_KEY_ID` | IAM user access key | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_REGION` | AWS region | `us-east-1` |
| `S3_BUCKET` | S3 bucket name | `your-rekognition-images-bucket` |
| `DYNAMODB_TABLE_BETA` | Beta DynamoDB table | `beta_results` |
| `DYNAMODB_TABLE_PROD` | Production DynamoDB table | `prod_results` |

### Workflow Files Setup

The repository includes two workflow files that should be placed in `.github/workflows/`:

- `on_pull_request.yml` - Runs on pull requests
- `on_merge.yml` - Runs on merges to main

## Usage

### Adding New Images

1. Add `.jpg` or `.png` files to the `images/` folder:

```bash
git add images/my-new-image.jpg
git commit -m "Add new image for analysis"
git push origin feature-branch
```

2. Create a Pull Request:
   - The PR workflow will automatically trigger
   - Images will be analyzed and results stored in `beta_results`

3. Merge the PR:
   - The merge workflow will trigger
   - Results will be stored in `prod_results`

### Supported Image Formats

- JPEG (`.jpg`, `.jpeg`)
- PNG (`.png`)
- PDF (`.pdf`)

### Supported Image Dimensions

- Maximum file size: 15 MB (Rekognition limit)
- Minimum image dimension: 80 pixels
- Maximum image dimension: 10,000 pixels

### Example Output Structure

Results are stored in DynamoDB with the following structure:

```json
{
  "filename": "rekognition-input/beach-scene.jpg",
  "labels": [
    {"Name": "Beach", "Confidence": 99.23},
    {"Name": "Ocean", "Confidence": 98.76},
    {"Name": "Sand", "Confidence": 97.45},
    {"Name": "Sky", "Confidence": 96.12},
    {"Name": "Outdoors", "Confidence": 95.89}
  ],
  "timestamp": "2025-01-15T10:30:45Z",
  "branch": "feature-add-beach-image"
}
```

## Verification

### 1. Verify S3 Upload

Check if images are uploaded to S3:

```bash
aws s3 ls s3://your-rekognition-images-bucket/rekognition-input/
```

### 2. Query DynamoDB Tables

#### Check Beta Results (from PRs)

```bash
aws dynamodb scan \
  --table-name beta_results \
  --region us-east-1
```

#### Check Production Results (from merges)

```bash
aws dynamodb scan \
  --table-name prod_results \
  --region us-east-1
```

### 3. Query Specific Image Results

```bash
aws dynamodb query \
  --table-name prod_results \
  --key-condition-expression "filename = :fname" \
  --expression-attribute-values '{":fname":{"S":"rekognition-input/your-image.jpg"}}' \
  --region us-east-1
```

### 4. Monitor GitHub Actions

- Go to your repository → Actions tab
- View workflow runs and their logs
- Check for any errors in the execution

## Troubleshooting

### Common Issues and Solutions

#### 1. Authentication Errors

**Error:** `Unable to locate credentials`

**Solution:** Verify GitHub secrets are correctly set:
- Check secret names match exactly
- Ensure no extra spaces in secret values
- Verify IAM user has active access keys

#### 2. S3 Access Denied

**Error:** `Access Denied when calling PutObject`

**Solution:** 
- Verify S3 bucket name in secrets
- Check IAM policy includes correct bucket ARN
- Ensure bucket exists in the specified region

#### 3. Rekognition Errors

**Error:** `InvalidImageFormatException`

**Solution:**
- Ensure image is JPEG or PNG format
- Check file size is under 15 MB
- Verify image dimensions are within limits

#### 4. DynamoDB Write Failures

**Error:** `ResourceNotFoundException`

**Solution:**
- Confirm table names in secrets match actual table names
- Verify tables exist in the specified region
- Check IAM permissions include DynamoDB access

#### 5. Workflow Not Triggering

**Issue:** GitHub Actions not running

**Solution:**
- Verify workflow files are in `.github/workflows/`
- Check workflow syntax is valid
- Ensure branch protection rules don't block workflows
- For PRs, confirm target branch is `main`

### Viewing Detailed Logs

1. Navigate to Actions tab in GitHub
2. Click on the failed workflow run
3. Expand the step that failed
4. Review error messages and stack traces

### Local Testing

To test the image analysis script locally:

```bash
# Set environment variables
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_REGION="us-east-1"
export S3_BUCKET="your-bucket"
export DYNAMODB_TABLE="test_results"

# Run the script
python scripts/analyze_image.py images/test-image.jpg
```

## Security Best Practices

1. **Never commit credentials** - Always use GitHub Secrets
2. **Rotate access keys regularly** - Update IAM credentials periodically
3. **Use least privilege** - Grant only necessary permissions
4. **Enable S3 versioning** - Maintain image history
5. **Monitor AWS CloudTrail** - Track API calls for security auditing
6. **Set up billing alerts** - Prevent unexpected charges

## Cost Optimization

- **DynamoDB:** Consider using on-demand pricing for variable workloads
- **S3:** Implement lifecycle policies to archive old images
- **Rekognition:** First 5,000 images/month are free tier eligible
- **GitHub Actions:** Free for public repos, 2,000 minutes/month for private

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add your images to the `images/` folder
4. Create a pull request
5. Wait for automated analysis
6. Review results in DynamoDB

## Support

For issues or questions:
1. Check the Troubleshooting section
2. Review GitHub Actions logs
3. Open an issue with:
   - Error messages
   - Workflow run ID
   - Steps to reproduce