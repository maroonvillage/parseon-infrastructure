import requests
import boto3
import json
import time


def run(outputs_raw):
    outputs = json.loads(outputs_raw)

    url = f"http://{outputs['alb_dns']['value']}/upload"
    bucket = outputs["bucket_name"]["value"]
    queue_url = outputs["queue_url"]["value"]

    s3 = boto3.client("s3")
    sqs = boto3.client("sqs")

    print("Sending file via API...")

    files = {"file": ("test.txt", "hello world")}
    res = requests.post(url, files=files)

    assert res.status_code == 200, "API upload failed"

    print("✅ API upload succeeded")

    # confirm S3 object exists
    time.sleep(5)

    objs = s3.list_objects_v2(Bucket=bucket)

    assert "Contents" in objs, "File not in S3"

    print("✅ File stored in S3")

    # wait for worker to consume message
    print("Waiting for worker processing...")

    for i in range(15):
        attrs = sqs.get_queue_attributes(
            QueueUrl=queue_url, AttributeNames=["ApproximateNumberOfMessages"]
        )

        count = int(attrs["Attributes"]["ApproximateNumberOfMessages"])

        if count == 0:
            print("✅ Worker processed pipeline")
            return

        time.sleep(5)

    raise Exception("❌ Pipeline processing failed")
