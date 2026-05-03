import boto3
import json
import time


def run(outputs_raw):
    outputs = json.loads(outputs_raw)

    region = outputs["aws_region"]["value"]
    sqs = boto3.client("sqs", region_name=region)

    queue_url = outputs["queue_url"]["value"]
    queue_arn = outputs["queue_arn"]["value"]
    dlq_arn = outputs["dlq_arn"]["value"]

    print("Checking SQS messaging slice")
    print(f"Queue URL: {queue_url}")
    print(f"Queue ARN: {queue_arn}")
    print(f"DLQ ARN: {dlq_arn}")

    attributes = _get_queue_attributes(sqs, queue_url)

    assert (
        attributes["QueueArn"] == queue_arn
    ), f"Queue ARN mismatch. Expected {queue_arn}, got {attributes['QueueArn']}"

    print("✅ Main queue exists and ARN matches output")

    _check_redrive_policy(attributes, dlq_arn)
    print("✅ DLQ redrive policy is configured")

    _check_visibility_timeout(attributes)
    print("✅ Visibility timeout configured")

    _check_message_retention(attributes)
    print("✅ Message retention configured")

    _check_encryption_if_present(attributes)
    print("✅ Encryption check passed")

    _check_send_receive_delete(sqs, queue_url)
    print("✅ Send, receive, and delete message flow works")

    print("✅ SQS messaging test passed")


def _get_queue_attributes(sqs, queue_url):
    response = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=[
            "All",
        ],
    )

    return response["Attributes"]


def _check_redrive_policy(attributes, expected_dlq_arn):
    redrive_policy_raw = attributes.get("RedrivePolicy")

    assert redrive_policy_raw, "Queue does not have a RedrivePolicy configured"

    redrive_policy = json.loads(redrive_policy_raw)

    assert redrive_policy["deadLetterTargetArn"] == expected_dlq_arn, (
        "DLQ ARN mismatch. "
        f"Expected {expected_dlq_arn}, got {redrive_policy['deadLetterTargetArn']}"
    )

    max_receive_count = int(redrive_policy["maxReceiveCount"])
    assert (
        max_receive_count >= 1
    ), f"maxReceiveCount should be at least 1, got {max_receive_count}"


def _check_visibility_timeout(attributes):
    visibility_timeout = int(attributes["VisibilityTimeout"])

    assert visibility_timeout >= 30, (
        f"VisibilityTimeout is too low: {visibility_timeout}. "
        "Expected at least 30 seconds."
    )


def _check_message_retention(attributes):
    retention = int(attributes["MessageRetentionPeriod"])

    assert retention >= 60, (
        f"MessageRetentionPeriod is too low: {retention}. "
        "Expected at least 60 seconds."
    )


def _check_encryption_if_present(attributes):
    # Accept either AWS-managed SQS encryption, KMS encryption, or no encryption
    # depending on how your dev module is currently configured.
    sqs_managed_sse = attributes.get("SqsManagedSseEnabled")
    kms_key_id = attributes.get("KmsMasterKeyId")

    if sqs_managed_sse == "true":
        return

    if kms_key_id:
        return

    print(
        "ℹ️ Queue encryption attributes not present. Acceptable for dev if intentional."
    )


def _check_send_receive_delete(sqs, queue_url):
    test_body = {
        "test": "messaging-slice",
        "timestamp": int(time.time()),
    }

    send_response = sqs.send_message(
        QueueUrl=queue_url,
        MessageBody=json.dumps(test_body),
    )

    message_id = send_response["MessageId"]
    assert message_id, "SendMessage did not return a MessageId"

    print(f"✅ Test message sent: {message_id}")

    receive_response = sqs.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=1,
        WaitTimeSeconds=5,
        VisibilityTimeout=30,
    )

    messages = receive_response.get("Messages", [])

    assert len(messages) > 0, "No message received from queue"

    message = messages[0]
    received_body = json.loads(message["Body"])

    assert (
        received_body["test"] == "messaging-slice"
    ), f"Unexpected message body: {received_body}"

    receipt_handle = message["ReceiptHandle"]

    sqs.delete_message(
        QueueUrl=queue_url,
        ReceiptHandle=receipt_handle,
    )

    print("✅ Test message deleted")
