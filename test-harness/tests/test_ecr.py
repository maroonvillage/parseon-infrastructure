import boto3
import json


def run(outputs_raw):
    outputs = json.loads(outputs_raw)
    region = outputs["aws_region"]["value"]
    ecr = boto3.client("ecr", region_name=region)

    repository_name = outputs["repository_name"]["value"]
    repository_url = outputs["repository_url"]["value"]
    repository_arn = outputs["repository_arn"]["value"]

    print("Checking ECR slice")
    print(f"Repository name: {repository_name}")
    print(f"Repository URL: {repository_url}")
    print(f"Repository ARN: {repository_arn}")

    repository = _get_repository(ecr, repository_name)

    assert repository["repositoryArn"] == repository_arn, (
        f"Repository ARN mismatch. Expected {repository_arn}, "
        f"got {repository['repositoryArn']}"
    )

    assert repository["repositoryUri"] == repository_url, (
        f"Repository URL mismatch. Expected {repository_url}, "
        f"got {repository['repositoryUri']}"
    )

    print("✅ ECR repository exists and outputs match")

    _check_scan_on_push(repository)
    print("✅ ECR scan-on-push check passed")

    _check_tag_mutability(repository)
    print("✅ ECR tag mutability check passed")

    _check_encryption(repository)
    print("✅ ECR encryption check passed")

    _check_lifecycle_policy_if_present(ecr, repository_name)
    print("✅ ECR lifecycle policy check passed")

    _check_repository_policy_if_present(ecr, repository_name)
    print("✅ ECR repository policy check passed")

    _check_images_if_present(ecr, repository_name)

    print("✅ ECR test passed")


def _get_repository(ecr, repository_name):
    response = ecr.describe_repositories(
        repositoryNames=[repository_name],
    )

    repositories = response.get("repositories", [])

    assert len(repositories) == 1, f"ECR repository not found: {repository_name}"

    return repositories[0]


def _check_scan_on_push(repository):
    scan_config = repository.get("imageScanningConfiguration", {})
    scan_on_push = scan_config.get("scanOnPush")

    assert scan_on_push is True, (
        "ECR scan-on-push is not enabled. "
        "Expected imageScanningConfiguration.scanOnPush = true."
    )


def _check_tag_mutability(repository):
    mutability = repository.get("imageTagMutability")

    assert mutability in [
        "MUTABLE",
        "IMMUTABLE",
    ], f"Unexpected ECR image tag mutability value: {mutability}"

    print(f"ℹ️ Image tag mutability: {mutability}")


def _check_encryption(repository):
    encryption_config = repository.get("encryptionConfiguration", {})
    encryption_type = encryption_config.get("encryptionType")

    assert encryption_type in [
        "AES256",
        "KMS",
    ], f"Unexpected ECR encryption type: {encryption_type}"

    if encryption_type == "KMS":
        assert encryption_config.get(
            "kmsKey"
        ), "ECR encryption type is KMS but no KMS key is configured"

    print(f"ℹ️ Encryption type: {encryption_type}")


def _check_lifecycle_policy_if_present(ecr, repository_name):
    try:
        response = ecr.get_lifecycle_policy(
            repositoryName=repository_name,
        )

        policy_text = response.get("lifecyclePolicyText")
        assert policy_text, "Lifecycle policy exists but policy text is empty"

        policy = json.loads(policy_text)
        rules = policy.get("rules", [])

        assert isinstance(rules, list), "Lifecycle policy rules must be a list"
        assert len(rules) > 0, "Lifecycle policy has no rules"

        print(f"ℹ️ Lifecycle policy rules found: {len(rules)}")

    except ecr.exceptions.LifecyclePolicyNotFoundException:
        print("ℹ️ No lifecycle policy configured. Acceptable for dev if intentional.")


def _check_repository_policy_if_present(ecr, repository_name):
    try:
        response = ecr.get_repository_policy(
            repositoryName=repository_name,
        )

        policy_text = response.get("policyText")
        assert policy_text, "Repository policy exists but policy text is empty"

        policy = json.loads(policy_text)
        statements = policy.get("Statement", [])

        assert isinstance(
            statements, list
        ), "Repository policy Statement must be a list"

        for statement in statements:
            effect = statement.get("Effect")
            assert effect in [
                "Allow",
                "Deny",
            ], f"Unexpected repository policy effect: {effect}"

        print(f"ℹ️ Repository policy statements found: {len(statements)}")

    except ecr.exceptions.RepositoryPolicyNotFoundException:
        print("ℹ️ No repository policy configured. Acceptable for private dev ECR.")


def _check_images_if_present(ecr, repository_name):
    response = ecr.list_images(
        repositoryName=repository_name,
        maxResults=100,
    )

    image_ids = response.get("imageIds", [])

    if not image_ids:
        print("ℹ️ No images currently pushed to this repository.")
        return

    print(f"ℹ️ Images found: {len(image_ids)}")

    describe_response = ecr.describe_images(
        repositoryName=repository_name,
        imageIds=image_ids[:10],
    )

    image_details = describe_response.get("imageDetails", [])

    for image in image_details:
        assert image.get("imageDigest"), "Image is missing imageDigest"
        assert image.get("imagePushedAt"), "Image is missing imagePushedAt"

    print("✅ Existing image metadata is valid")
