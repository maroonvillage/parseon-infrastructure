# tests/test_sqs.py

import boto3
import json


def run(outputs_raw):
    outputs = json.loads(outputs_raw)

    queue_url = outputs["queue_url"]["value"]

    sqs = boto3.client("sqs")

    sqs.send_message(QueueUrl=queue_url, MessageBody="test message")

    messages = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=1)

    assert "Messages" in messages

    print("✅ SQS test passed")
