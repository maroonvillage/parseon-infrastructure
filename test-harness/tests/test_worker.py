import boto3
import json
import time


def run(outputs_raw):
    outputs = json.loads(outputs_raw)

    queue_url = outputs["queue_url"]["value"]

    sqs = boto3.client("sqs", region_name="us-east-1")

    print("Sending test message...")

    sqs.send_message(QueueUrl=queue_url, MessageBody="test message")

    print("Waiting for worker to process message...")

    for i in range(10):
        attrs = sqs.get_queue_attributes(
            QueueUrl=queue_url, AttributeNames=["ApproximateNumberOfMessages"]
        )

        count = int(attrs["Attributes"]["ApproximateNumberOfMessages"])

        if count == 0:
            print("✅ Worker processed message")
            return

        time.sleep(5)

    raise Exception("❌ Worker did not process message")
