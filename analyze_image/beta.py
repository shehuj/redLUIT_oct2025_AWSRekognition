import boto3
import json
import os
from datetime import datetime, timezone
from decimal import Decimal


def upload_to_s3(s3_client, bucket, image_path):
    """Upload an image file to S3 bucket."""
    key = f"rekognition-input/dev/{os.path.basename(image_path)}"
    s3_client.upload_file(image_path, bucket, key)
    return key


def analyze_image(rek_client, bucket, key):
    """Analyze image using AWS Rekognition to detect labels."""
    resp = rek_client.detect_labels(
        Image={'S3Object': {'Bucket': bucket, 'Name': key}},
        MaxLabels=10
    )
    return resp.get("Labels", [])


def write_to_dynamodb(dynamodb, table_name, item):
    """Write an item to DynamoDB table."""
    table = dynamodb.Table(table_name)
    table.put_item(Item=item)


def main():
    # Get environment variables
    aws_region = os.getenv("AWS_REGION")
    s3_bucket = os.getenv("S3_BUCKET")
    s3_bucket_path = os.getenv("S3_BUCKET_PATH")
    dynamodb_table = os.getenv("DYNAMODB_TABLE_BETA")
    
    # Debug output
    print(f"[DEBUG] AWS_REGION = {aws_region}")
    print(f"[DEBUG] S3_BUCKET = {s3_bucket}")
    print(f"[DEBUG] S3_BUCKET_PATH = {s3_bucket_path}")
    print(f"[DEBUG] DYNAMODB_TABLE_BETA = {dynamodb_table}\n")
    
    # Validate required environment variables
    if not aws_region or not s3_bucket or not dynamodb_table:
        raise RuntimeError(
            "Missing one of AWS_REGION, S3_BUCKET, or DYNAMODB_TABLE_BETA. "
            "Got: aws_region=%s, "
            "s3_bucket=%s, "
            "dynamodb_table=%s, "
            "s3_bucket_path=%s"
            % (aws_region, s3_bucket, dynamodb_table, s3_bucket_path)
        )
    
    # Initialize AWS clients
    s3 = boto3.client("s3", region_name=aws_region)
    rek = boto3.client("rekognition", region_name=aws_region)
    dynamodb = boto3.resource("dynamodb", region_name=aws_region)
    
    # Process images from directory
    image_dir = "images"
    
    # Check if image directory exists
    if not os.path.exists(image_dir):
        print(f"Warning: '{image_dir}' directory not found.")
        return
    
    # Process each image file
    for image_file in os.listdir(image_dir):
        # Note: Rekognition doesn't support PDF files directly
        if image_file.lower().endswith((".jpg", ".png", ".jpeg")):
            image_path = os.path.join(image_dir, image_file)
            print(f"Processing: {image_file}")
            
            try:
                # Upload to S3
                key = upload_to_s3(s3, s3_bucket, image_path)
                
                # Analyze with Rekognition
                labels = analyze_image(rek, s3_bucket, key)
                
                # Construct S3 path
                s3_full_path = f"s3://{s3_bucket}/{key}"
                
                # Prepare item for DynamoDB
                image_id = os.path.splitext(image_file)[0]
                image_type = os.path.splitext(image_file)[1].lstrip(".").lower()
                
                item = {
                    "image_id": image_id,
                    "image_type": image_type,
                    "filename": key,
                    "s3_path": s3_full_path,
                    "labels": [
                        {
                            "Name": lbl["Name"], 
                            "Confidence": Decimal(str(lbl["Confidence"]))
                        }
                        for lbl in labels
                    ],
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "branch": "dev",
                }
                
                # Write to DynamoDB
                write_to_dynamodb(dynamodb, dynamodb_table, item)
                
                # Display result
                print(json.dumps(item, indent=2, default=str))
                print("Written to DynamoDB.\n")
                
            except Exception as e:
                print(f"Error processing {image_file}: {str(e)}\n")
                continue


if __name__ == "__main__":
    main()