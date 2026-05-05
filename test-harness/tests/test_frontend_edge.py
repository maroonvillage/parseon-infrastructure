import json
import time
import urllib.error
import urllib.request

import boto3


def run(outputs_raw):
    outputs = json.loads(outputs_raw)
    region = outputs["aws_region"]["value"]
    cloudfront = boto3.client("cloudfront", region_name=region)
    elbv2 = boto3.client("elbv2", region_name=region)
    s3 = boto3.client("s3", region_name=region)

    distribution_id = outputs["cloudfront_distribution_id"]["value"]
    distribution_arn = outputs["cloudfront_distribution_arn"]["value"]
    cloudfront_domain = outputs["cloudfront_domain_name"]["value"]
    frontend_bucket = outputs["frontend_bucket_id"]["value"]
    frontend_bucket_arn = outputs["frontend_bucket_arn"]["value"]
    alb_arn = outputs["alb_arn"]["value"]
    alb_dns_name = outputs["alb_dns_name"]["value"]
    target_group_arn = outputs["target_group_arn"]["value"]
    index_key = outputs.get("index_object_key", {}).get("value", "index.html")
    api_path_pattern = outputs.get("api_path_pattern", {}).get("value", "/api/*")

    print("Checking frontend edge slice")
    print(f"CloudFront distribution: {distribution_id}")
    print(f"CloudFront domain: {cloudfront_domain}")
    print(f"Frontend bucket: {frontend_bucket}")
    print(f"ALB DNS: {alb_dns_name}")

    distribution = _get_distribution(cloudfront, distribution_id)
    config = distribution["DistributionConfig"]

    assert (
        distribution["ARN"] == distribution_arn
    ), f"Distribution ARN mismatch. Expected {distribution_arn}, got {distribution['ARN']}"
    assert config["Enabled"] is True, "CloudFront distribution is not enabled"

    print("✅ CloudFront distribution exists and is enabled")

    _check_alb(elbv2, alb_arn, alb_dns_name)
    print("✅ ALB exists and DNS output matches")

    _check_target_group(elbv2, target_group_arn)
    print("✅ ALB target group exists")

    _check_frontend_bucket(s3, frontend_bucket, index_key)
    print("✅ Frontend S3 bucket exists and contains index.html")

    _check_cloudfront_origins(config, frontend_bucket, alb_dns_name)
    print("✅ CloudFront has S3 and ALB origins")

    _check_default_behavior(config)
    print("✅ CloudFront default behavior routes to S3 frontend origin")

    _check_api_behavior(config, api_path_pattern)
    print(f"✅ CloudFront ordered behavior routes {api_path_pattern} to ALB origin")

    _check_spa_fallback(config)
    print("✅ SPA fallback custom error responses are configured")

    _check_bucket_policy_allows_cloudfront_oac(
        s3, frontend_bucket, distribution_arn, frontend_bucket_arn
    )
    print("✅ Frontend bucket policy allows this CloudFront distribution via OAC")

    _wait_for_distribution_deployed(cloudfront, distribution_id)
    print("✅ CloudFront distribution is deployed")

    _check_frontend_http_response(cloudfront_domain)
    print("✅ CloudFront frontend path responds")

    _check_api_path_reaches_non_s3_origin(cloudfront_domain)
    print("✅ CloudFront /api/* path reaches ALB origin behavior")

    print("✅ Frontend edge test passed")


def _get_distribution(cloudfront, distribution_id):
    response = cloudfront.get_distribution(Id=distribution_id)
    return response["Distribution"]


def _check_alb(elbv2, alb_arn, expected_dns_name):
    response = elbv2.describe_load_balancers(LoadBalancerArns=[alb_arn])
    load_balancers = response.get("LoadBalancers", [])

    assert len(load_balancers) == 1, f"ALB not found: {alb_arn}"

    alb = load_balancers[0]
    assert (
        alb["DNSName"] == expected_dns_name
    ), f"ALB DNS mismatch. Expected {expected_dns_name}, got {alb['DNSName']}"
    assert alb["State"]["Code"] in [
        "active",
        "provisioning",
    ], f"Unexpected ALB state: {alb['State']['Code']}"
    assert (
        alb["Scheme"] == "internet-facing"
    ), "ALB should be internet-facing for CloudFront origin"


def _check_target_group(elbv2, target_group_arn):
    response = elbv2.describe_target_groups(TargetGroupArns=[target_group_arn])
    target_groups = response.get("TargetGroups", [])

    assert len(target_groups) == 1, f"Target group not found: {target_group_arn}"

    tg = target_groups[0]
    assert tg["TargetType"] == "ip", f"Expected target type ip, got {tg['TargetType']}"
    assert tg["Protocol"] == "HTTP", f"Expected HTTP target group, got {tg['Protocol']}"
    assert tg["HealthCheckPath"], "Target group is missing a health check path"


def _check_frontend_bucket(s3, bucket_name, index_key):
    s3.head_bucket(Bucket=bucket_name)
    s3.head_object(Bucket=bucket_name, Key=index_key)

    pab = s3.get_public_access_block(Bucket=bucket_name)[
        "PublicAccessBlockConfiguration"
    ]
    assert pab["BlockPublicAcls"] is True, "Frontend bucket BlockPublicAcls is not true"
    assert (
        pab["IgnorePublicAcls"] is True
    ), "Frontend bucket IgnorePublicAcls is not true"
    assert (
        pab["BlockPublicPolicy"] is True
    ), "Frontend bucket BlockPublicPolicy is not true"
    assert (
        pab["RestrictPublicBuckets"] is True
    ), "Frontend bucket RestrictPublicBuckets is not true"


def _check_cloudfront_origins(config, frontend_bucket, alb_dns_name):
    origins = _as_list(config["Origins"].get("Items", []))
    origin_by_id = {origin["Id"]: origin for origin in origins}

    assert "s3-frontend" in origin_by_id, "Missing CloudFront s3-frontend origin"
    assert "alb-origin" in origin_by_id, "Missing CloudFront alb-origin origin"

    s3_origin = origin_by_id["s3-frontend"]
    alb_origin = origin_by_id["alb-origin"]

    assert (
        frontend_bucket in s3_origin["DomainName"]
    ), f"S3 origin domain does not contain frontend bucket name: {s3_origin['DomainName']}"
    assert s3_origin.get(
        "OriginAccessControlId"
    ), "S3 origin is missing Origin Access Control ID"

    assert (
        alb_origin["DomainName"] == alb_dns_name
    ), f"ALB origin DNS mismatch. Expected {alb_dns_name}, got {alb_origin['DomainName']}"
    assert alb_origin.get(
        "CustomOriginConfig"
    ), "ALB origin is missing CustomOriginConfig"


def _check_default_behavior(config):
    behavior = config["DefaultCacheBehavior"]

    assert (
        behavior["TargetOriginId"] == "s3-frontend"
    ), f"Default behavior should target s3-frontend, got {behavior['TargetOriginId']}"
    assert (
        behavior["ViewerProtocolPolicy"] == "redirect-to-https"
    ), f"Unexpected default viewer protocol policy: {behavior['ViewerProtocolPolicy']}"

    allowed_methods = set(behavior["AllowedMethods"]["Items"])
    assert {"GET", "HEAD"}.issubset(
        allowed_methods
    ), f"Default behavior missing GET/HEAD allowed methods: {allowed_methods}"


def _check_api_behavior(config, expected_path_pattern):
    cache_behaviors = config.get("CacheBehaviors", {})
    items = _as_list(cache_behaviors.get("Items", []))

    api_behaviors = [
        item for item in items if item.get("PathPattern") == expected_path_pattern
    ]
    assert (
        len(api_behaviors) == 1
    ), f"Expected one {expected_path_pattern} behavior, found {len(api_behaviors)}"

    behavior = api_behaviors[0]
    assert (
        behavior["TargetOriginId"] == "alb-origin"
    ), f"API behavior should target alb-origin, got {behavior['TargetOriginId']}"
    assert (
        behavior["ViewerProtocolPolicy"] == "redirect-to-https"
    ), f"Unexpected API viewer protocol policy: {behavior['ViewerProtocolPolicy']}"

    allowed_methods = set(behavior["AllowedMethods"]["Items"])
    expected_methods = {"GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"}
    assert expected_methods.issubset(
        allowed_methods
    ), f"API behavior missing methods. Expected {expected_methods}, got {allowed_methods}"

    assert behavior["MinTTL"] == 0, f"API MinTTL should be 0, got {behavior['MinTTL']}"
    assert (
        behavior["DefaultTTL"] == 0
    ), f"API DefaultTTL should be 0, got {behavior['DefaultTTL']}"
    assert behavior["MaxTTL"] == 0, f"API MaxTTL should be 0, got {behavior['MaxTTL']}"


def _check_spa_fallback(config):
    custom_errors = config.get("CustomErrorResponses", {})
    items = _as_list(custom_errors.get("Items", []))

    by_code = {item["ErrorCode"]: item for item in items}

    for code in [403, 404]:
        assert code in by_code, f"Missing SPA fallback for error code {code}"
        assert (
            by_code[code]["ResponseCode"] == "200"
        ), f"Error {code} should return response code 200"
        assert (
            by_code[code]["ResponsePagePath"] == "/index.html"
        ), f"Error {code} should map to /index.html"


def _check_bucket_policy_allows_cloudfront_oac(
    s3, bucket_name, distribution_arn, bucket_arn
):
    response = s3.get_bucket_policy(Bucket=bucket_name)
    policy = json.loads(response["Policy"])
    statements = policy.get("Statement", [])
    if isinstance(statements, dict):
        statements = [statements]

    expected_resource = f"{bucket_arn}/*"

    for statement in statements:
        actions = statement.get("Action", [])
        if isinstance(actions, str):
            actions = [actions]

        resources = statement.get("Resource", [])
        if isinstance(resources, str):
            resources = [resources]

        principal = statement.get("Principal", {})
        service_principal = None
        if isinstance(principal, dict):
            service_principal = principal.get("Service")

        condition = statement.get("Condition", {})
        source_arn = condition.get("StringEquals", {}).get(
            "AWS:SourceArn"
        ) or condition.get("StringLike", {}).get("AWS:SourceArn")

        if (
            statement.get("Effect") == "Allow"
            and "s3:GetObject" in actions
            and expected_resource in resources
            and service_principal == "cloudfront.amazonaws.com"
            and source_arn == distribution_arn
        ):
            return

    raise AssertionError(
        "No bucket policy statement found allowing this CloudFront distribution via OAC"
    )


def _wait_for_distribution_deployed(
    cloudfront, distribution_id, timeout_seconds=900, poll_seconds=20
):
    deadline = time.time() + timeout_seconds

    while time.time() < deadline:
        distribution = _get_distribution(cloudfront, distribution_id)
        status = distribution["Status"]
        print(f"ℹ️ CloudFront status: {status}")

        if status == "Deployed":
            return

        time.sleep(poll_seconds)

    raise AssertionError(
        f"CloudFront distribution did not deploy within {timeout_seconds} seconds"
    )


def _check_frontend_http_response(cloudfront_domain):
    url = f"https://{cloudfront_domain}/"
    response = _http_get(url)

    assert (
        response["status"] == 200
    ), f"Expected frontend status 200, got {response['status']}"
    assert (
        "frontend-edge-ok" in response["body"]
    ), "Frontend response did not contain test marker"


def _check_api_path_reaches_non_s3_origin(cloudfront_domain):
    # This slice does not register ECS targets behind the ALB, so ALB-origin responses
    # may be 503. That is acceptable here. What matters is that /api/* does not return
    # the S3 index marker, which would indicate the path behavior failed.
    url = f"https://{cloudfront_domain}/api/health"
    response = _http_get(url, accept_error_status=True)

    assert response["status"] in [
        200,
        301,
        302,
        403,
        404,
        502,
        503,
        504,
    ], f"Unexpected /api/health status from CloudFront/ALB: {response['status']}"
    assert (
        "frontend-edge-ok" not in response["body"]
    ), "/api/health returned the frontend index marker, so it may be routing to S3 instead of ALB"

    print(
        f"ℹ️ /api/health returned status {response['status']} as expected for ALB-origin fixture"
    )


def _http_get(url, accept_error_status=False, timeout=20):
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "terraform-frontend-edge-test/1.0",
        },
        method="GET",
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8", errors="replace")
            return {"status": response.status, "body": body}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        if accept_error_status:
            return {"status": exc.code, "body": body}
        raise AssertionError(
            f"HTTP request failed for {url}: {exc.code} {body[:500]}"
        ) from exc


def _as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]
