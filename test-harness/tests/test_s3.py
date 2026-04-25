# tests/test_s3.py

import boto3
import json


def run(outputs_raw):
    outputs = json.loads(outputs_raw)

    bucket = outputs["bucket_name"]["value"]

    s3 = boto3.client("s3")

    test_key = "test.txt"
    s3.put_object(Bucket=bucket, Key=test_key, Body="hello")

    obj = s3.get_object(Bucket=bucket, Key=test_key)

    assert obj["Body"].read().decode() == "hello"

    print("✅ S3 test passed")
