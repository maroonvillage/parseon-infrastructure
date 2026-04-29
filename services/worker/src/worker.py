import boto3
import os
import time

sqs = boto3.client("sqs")
queue_url = os.environ["QUEUE_URL"]

print(f"Worker started. Listening to {queue_url}")

while True:
    response = sqs.receive_message(
        QueueUrl=queue_url, MaxNumberOfMessages=1, WaitTimeSeconds=10
    )

    messages = response.get("Messages", [])

    for msg in messages:
        print(f"Processing: {msg['Body']}")

        # simulate processing
        time.sleep(1)

        sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=msg["ReceiptHandle"])

        print("Message processed and deleted")
