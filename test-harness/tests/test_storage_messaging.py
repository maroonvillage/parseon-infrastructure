import boto3
import json
import time


def run(outputs_raw):
    outputs = json.loads(outputs_raw)

    bucket = outputs["bucket_name"]["value"]
    queue_url = outputs["queue_url"]["value"]

    s3 = boto3.client("s3")
    sqs = boto3.client("sqs")

    test_key = "test-file.txt"

    print(f"Uploading file to {bucket}...")

    s3.put_object(Bucket=bucket, Key=test_key, Body="hello world")

    print("Waiting for SQS message...")

    for i in range(10):
        messages = sqs.receive_message(
            QueueUrl=queue_url, MaxNumberOfMessages=1, WaitTimeSeconds=2
        )

        if "Messages" in messages:
            print("✅ Event received in SQS")
            return

        time.sleep(2)

    raise Exception("❌ No SQS message received")
