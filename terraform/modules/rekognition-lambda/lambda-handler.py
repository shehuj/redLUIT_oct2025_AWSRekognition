import os
import json
from datetime import datetime, timezone

import boto3

rek = boto3.client("rekognition")
dynamodb = boto3.resource("dynamodb")

def lambda_handler(event, context):
    table_name = os.environ["DYNAMODB_TABLE"]
    branch = os.environ.get("BRANCH", "unknown")
    tbl = dynamodb.Table(table_name)

    print("Received event:", json.dumps(event))

    for rec in event.get("Records", []):
        bucket = rec["s3"]["bucket"]["name"]
        key = rec["s3"]["object"]["key"]

        # perform Rekognition
        resp = rek.detect_labels(
            Image={"S3Object": {"Bucket": bucket, "Name": key}},
            MaxLabels=20,
            MinConfidence=50.0
        )
        labels = resp.get("Labels", [])

        timestamp = datetime.now(timezone.utc).isoformat()
        item = {
            "filename": key,
            "timestamp": timestamp,
            "branch": branch,
            "labels": json.dumps([{"Name": l["Name"], "Confidence": l["Confidence"]} for l in labels])
        }
        tbl.put_item(Item=item)
        print(f"Processed {key}, wrote item: {item}")

    return {"statusCode": 200, "body": "ok"}