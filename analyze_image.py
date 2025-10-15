import boto3
import json
import os
from datetime import datetime, timezone
from decimal import Decimal

def upload_to_s3(s3_client, bucket, image_path):
    key = f"rekognition-input/{os.path.basename(image_path)}"
    s3_client.upload_file(image_path, bucket, key)
    return key

def analyze_image(rekognition_client, bucket, key):
    response = rekognition_client.detect_labels(
        Image={'S3Object': {'Bucket': bucket, 'Name': key}},
        MaxLabels=10
    )
    return response["Labels"]

def write_to_dynamodb(dynamodb, table_name, item):
    table = dynamodb.Table(table_name)
    table.put_item(Item=item)

def main():
    aws_region = os.getenv("AWS_REGION")
    s3_bucket = os.getenv("S3_BUCKET")
    branch_name = os.getenv("GITHUB_REF_NAME") or "local"

    # Which DynamoDB table to use based on branch
    if branch_name == "main":
        dynamodb_table = os.getenv("DYNAMODB_TABLE_PROD")
    else:
        dynamodb_table = os.getenv("DYNAMODB_TABLE_BETA")

    s3 = boto3.client("s3", region_name=aws_region)
    rekognition = boto3.client("rekognition", region_name=aws_region)
    dynamodb = boto3.resource("dynamodb", region_name=aws_region)

    image_dir = "images"
    for image_file in os.listdir(image_dir):
        if image_file.lower().endswith((".jpg", ".png", ".jpeg", ".pdf")):
            image_path = os.path.join(image_dir, image_file)
            print(f"Processing: {image_file}")

            # S3 upload
            key = upload_to_s3(s3, s3_bucket, image_path)
            labels = analyze_image(rekognition, s3_bucket, key)

            # Derive image_id and image_type from filename (or however you choose)
            # For example, split filename at period:
            image_id = os.path.splitext(image_file)[0]   # e.g. "dna"
            image_type = os.path.splitext(image_file)[1].lstrip(".").lower()  # e.g. "jpg" or "png"

            # Build item including required key attributes
            item = {
                "image_id": image_id,
                "image_type": image_type,
                "filename": key,
                "labels": [
                    {"Name": lbl["Name"], "Confidence": Decimal(str(lbl["Confidence"]))}
                    for lbl in labels
                ],
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "branch": branch_name,
            }

            write_to_dynamodb(dynamodb, dynamodb_table, item)
            # Use default=str so Decimal in dict can be printed
            print(json.dumps(item, indent=2, default=str))

if __name__ == "__main__":
    main()