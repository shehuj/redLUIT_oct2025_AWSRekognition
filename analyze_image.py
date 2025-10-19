import boto3
import os
import json
from datetime import datetime

def analyze_image(file_path, branch):
    s3_bucket = os.environ["S3_BUCKET"]
    region = os.environ["AWS_REGION"]

    # Select correct DynamoDB table based on branch
    table_name = (
        os.environ["DYNAMODB_TABLE_BETA"]
        if branch != "main"
        else os.environ["DYNAMODB_TABLE_PROD"]
    )

    # Initialize AWS clients
    s3 = boto3.client("s3", region_name=region)
    rekognition = boto3.client("rekognition", region_name=region)
    dynamodb = boto3.resource("dynamodb", region_name=region)
    table = dynamodb.Table(table_name)

    filename = os.path.basename(file_path)
    s3_key = f"rekognition-input/{filename}"

    print(f"📤 Uploading {filename} to S3 bucket {s3_bucket}/{s3_key}")
    s3.upload_file(file_path, s3_bucket, s3_key)

    print(f"🔍 Analyzing {filename} with Rekognition...")
    response = rekognition.detect_labels(
        Image={"S3Object": {"Bucket": s3_bucket, "Name": s3_key}},
        MaxLabels=10,
        MinConfidence=70
    )

    labels = [
        {"Name": label["Name"], "Confidence": round(label["Confidence"], 2)}
        for label in response["Labels"]
    ]

    result_item = {
        "filename": s3_key,
        "labels": labels,
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "branch": branch,
    }

    print(f"🪣 Writing analysis result to DynamoDB table {table_name}")
    table.put_item(Item=result_item)

    print(json.dumps(result_item, indent=2))
    return result_item


if __name__ == "__main__":
    import sys
    branch = os.environ.get("GITHUB_REF_NAME", "unknown-branch")

    for root, _, files in os.walk("images"):
        for f in files:
            if f.lower().endswith((".jpg", ".jpeg", ".png", ".pdf")):
                analyze_image(os.path.join(root, f), branch)