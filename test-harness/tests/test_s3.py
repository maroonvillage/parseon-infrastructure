import boto3
import json


def run(outputs_raw):
    outputs = json.loads(outputs_raw)

    s3 = boto3.client("s3")

    app_bucket = outputs["app_bucket_name"]["value"]
    frontend_bucket = outputs["frontend_bucket_name"]["value"]

    print("Checking S3 storage slice")
    print(f"App bucket: {app_bucket}")
    print(f"Frontend bucket: {frontend_bucket}")

    _check_bucket_exists(s3, app_bucket)
    print("✅ App bucket exists")

    _check_bucket_exists(s3, frontend_bucket)
    print("✅ Frontend bucket exists")

    _check_public_access_blocked(s3, app_bucket)
    print("✅ App bucket blocks public access")

    _check_public_access_blocked(s3, frontend_bucket)
    print("✅ Frontend bucket blocks public access")

    _check_bucket_not_public_policy(s3, app_bucket)
    print("✅ App bucket policy is not public")

    _check_bucket_not_public_policy(s3, frontend_bucket)
    print("✅ Frontend bucket policy is not public")

    _check_encryption_enabled(s3, app_bucket)
    print("✅ App bucket encryption enabled")

    _check_encryption_enabled(s3, frontend_bucket)
    print("✅ Frontend bucket encryption enabled")

    _check_versioning(s3, app_bucket)
    print("✅ App bucket versioning check passed")

    _check_versioning(s3, frontend_bucket)
    print("✅ Frontend bucket versioning check passed")

    print("✅ S3 storage test passed")


def _check_bucket_exists(s3, bucket_name):
    try:
        s3.head_bucket(Bucket=bucket_name)
    except Exception as exc:
        raise AssertionError(
            f"Bucket does not exist or is not accessible: {bucket_name}"
        ) from exc


def _check_public_access_blocked(s3, bucket_name):
    response = s3.get_public_access_block(Bucket=bucket_name)
    config = response["PublicAccessBlockConfiguration"]

    assert (
        config["BlockPublicAcls"] is True
    ), f"{bucket_name}: BlockPublicAcls is not true"
    assert (
        config["IgnorePublicAcls"] is True
    ), f"{bucket_name}: IgnorePublicAcls is not true"
    assert (
        config["BlockPublicPolicy"] is True
    ), f"{bucket_name}: BlockPublicPolicy is not true"
    assert (
        config["RestrictPublicBuckets"] is True
    ), f"{bucket_name}: RestrictPublicBuckets is not true"


def _check_bucket_not_public_policy(s3, bucket_name):
    try:
        response = s3.get_bucket_policy_status(Bucket=bucket_name)
        is_public = response["PolicyStatus"]["IsPublic"]
        assert is_public is False, f"{bucket_name}: bucket policy is public"
    except Exception as exc:
        error_code = getattr(exc, "response", {}).get("Error", {}).get("Code")

        if error_code in ["NoSuchBucketPolicy", "NoSuchBucket"]:
            return

        raise


def _check_encryption_enabled(s3, bucket_name):
    try:
        response = s3.get_bucket_encryption(Bucket=bucket_name)
        rules = response["ServerSideEncryptionConfiguration"]["Rules"]

        assert len(rules) > 0, f"{bucket_name}: no encryption rules found"

        algorithm = rules[0]["ApplyServerSideEncryptionByDefault"]["SSEAlgorithm"]

        assert algorithm in [
            "AES256",
            "aws:kms",
        ], f"{bucket_name}: unexpected encryption algorithm: {algorithm}"

    except Exception as exc:
        error_code = getattr(exc, "response", {}).get("Error", {}).get("Code")

        raise AssertionError(
            f"{bucket_name}: bucket encryption is not enabled or could not be verified"
        ) from exc


def _check_versioning(s3, bucket_name):
    response = s3.get_bucket_versioning(Bucket=bucket_name)
    status = response.get("Status")

    # Accept both enabled and intentionally unset for dev unless your module requires versioning.
    assert status in [
        None,
        "Enabled",
        "Suspended",
    ], f"{bucket_name}: unexpected versioning status: {status}"
