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
    table = dynamodb.Table(table_name)
    table.put_item(Item=item)

def main():
    aws_region = os.getenv("AWS_REGION")
    s3_bucket = os.getenv("S3_BUCKET")
    ref_name = os.getenv("GITHUB_REF_NAME", "")
    head_ref = os.getenv("GITHUB_HEAD_REF", "")
    # Use PR head_ref if present, else fallback
    branch_name = head_ref if head_ref else (ref_name or "local")

    tbl_beta = os.getenv("DYNAMODB_TABLE_BETA")
    tbl_prod = os.getenv("DYNAMODB_TABLE_PROD")

    # If branch is exactly “dev”, use prod; else use beta
    if branch_name == "dev":
        dynamodb_table = os.getenv("DYNAMODB_TABLE_BETA")
    elif tbl_prod:
        dynamodb_table = os.getenv("DYNAMODB_TABLE_PROD")
    else:
        tbl_beta = os.getenv("DYNAMODB_TABLE_BETA")

    print(f"[DEBUG] GITHUB_HEAD_REF = {head_ref}")
    print(f"[DEBUG] GITHUB_REF_NAME = {ref_name}")
    print(f"[DEBUG] resolved branch_name = {branch_name}")
    print(f"[DEBUG] selected DynamoDB table = {dynamodb_table}")

    if not aws_region or not s3_bucket or not dynamodb_table:
        raise RuntimeError(
            "Missing one of AWS_REGION, S3_BUCKET, or the table name. "
            "Got: aws_region=%s, s3_bucket=%s, dynamodb_table=%s"
            % (aws_region, s3_bucket, dynamodb_table)
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
            print("Written to DynamoDB.\n")

if __name__ == "__main__":
    main()