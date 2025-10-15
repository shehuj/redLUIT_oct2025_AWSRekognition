import boto3
import json
import os
from datetime import datetime, timezone
from decimal import Decimal

def upload_to_s3(s3_client, bucket, image_path):
    key = f"rekognition-input/{os.path.basename(image_path)}"
    s3_client.upload_file(image_path, bucket, key)
    return key

def analyze_image(rek_client, bucket, key):
    resp = rek_client.detect_labels(
        Image={'S3Object': {'Bucket': bucket, 'Name': key}},
        MaxLabels=10
    )
    return resp.get("Labels", [])

def write_to_dynamodb(dynamodb, table_name, item):
    # This is where the error arises if table_name is None
    table = dynamodb.Table(table_name)
    table.put_item(Item=item)

def main():
    aws_region = os.getenv("AWS_REGION")
    s3_bucket = os.getenv("S3_BUCKET")
    branch_name = os.getenv("GITHUB_REF_NAME") or "local"

    # Two table names from env
    tbl_beta = os.getenv("DYNAMODB_TABLE_BETA")
    tbl_prod = os.getenv("DYNAMODB_TABLE_PROD")

    # Decide which table
    if branch_name == "main":
        dynamodb_table = tbl_prod
    else:
        dynamodb_table = tbl_beta

    # Debug / sanity check
    print(f"[DEBUG] AWS_REGION = {aws_region}")
    print(f"[DEBUG] S3_BUCKET = {s3_bucket}")
    print(f"[DEBUG] branch_name = {branch_name}")
    print(f"[DEBUG] selected DynamoDB table = {dynamodb_table}")

    if not aws_region or not s3_bucket or not dynamodb_table:
        raise RuntimeError(
            "Missing required environment configuration. "
            "Ensure AWS_REGION, S3_BUCKET, and the correct DYNAMODB_TABLE_{BETA,PROD} env var are set."
        )

    s3 = boto3.client("s3", region_name=aws_region)
    rek = boto3.client("rekognition", region_name=aws_region)
    dynamodb = boto3.resource("dynamodb", region_name=aws_region)

    image_dir = "images"
    for image_file in os.listdir(image_dir):
        if image_file.lower().endswith((".jpg", ".png")):
            image_path = os.path.join(image_dir, image_file)
            print(f"Processing: {image_file}")

            key = upload_to_s3(s3, s3_bucket, image_path)
            labels = analyze_image(rek, s3_bucket, key)

            image_id = os.path.splitext(image_file)[0]
            image_type = os.path.splitext(image_file)[1].lstrip(".").lower()

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
            print(json.dumps(item, indent=2, default=str))

if __name__ == "__main__":
    main()