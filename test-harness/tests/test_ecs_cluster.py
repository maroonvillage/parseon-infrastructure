import boto3
import json


def run(outputs_raw):
    outputs = json.loads(outputs_raw)
    region = outputs["aws_region"]["value"]
    ecs = boto3.client("ecs", region_name=region)

    cluster_name = outputs["cluster_name"]["value"]
    cluster_arn = outputs["cluster_arn"]["value"]

    expected_container_insights = _get_optional_output(
        outputs,
        "container_insights",
        default=None,
    )

    print("Checking ECS cluster slice")
    print(f"Cluster name: {cluster_name}")
    print(f"Cluster ARN: {cluster_arn}")

    cluster = _get_cluster(ecs, cluster_name)

    assert cluster["clusterName"] == cluster_name, (
        f"Cluster name mismatch. Expected {cluster_name}, "
        f"got {cluster['clusterName']}"
    )

    assert cluster["clusterArn"] == cluster_arn, (
        f"Cluster ARN mismatch. Expected {cluster_arn}, " f"got {cluster['clusterArn']}"
    )

    assert (
        cluster["status"] == "ACTIVE"
    ), f"Cluster is not ACTIVE. Current status: {cluster['status']}"

    print("✅ ECS cluster exists and outputs match")

    _check_container_insights(cluster, expected_container_insights)
    print("✅ Container Insights setting check passed")

    _check_cluster_capacity_state(cluster)
    print("✅ ECS cluster capacity state check passed")

    print("✅ ECS cluster test passed")


def _get_cluster(ecs, cluster_name):
    response = ecs.describe_clusters(
        clusters=[cluster_name],
        include=[
            "SETTINGS",
            "STATISTICS",
        ],
    )

    failures = response.get("failures", [])
    assert len(failures) == 0, f"ECS describe_clusters failures: {failures}"

    clusters = response.get("clusters", [])
    assert len(clusters) == 1, f"ECS cluster not found: {cluster_name}"

    return clusters[0]


def _check_container_insights(cluster, expected_container_insights):
    settings = cluster.get("settings", [])

    setting_map = {setting["name"]: setting["value"] for setting in settings}

    actual_value = setting_map.get("containerInsights")

    if expected_container_insights is None:
        print(
            f"ℹ️ Container Insights output not provided. "
            f"Actual value: {actual_value or 'not configured'}"
        )
        return

    expected_value = _normalize_container_insights_value(expected_container_insights)

    assert (
        actual_value == expected_value
    ), f"Container Insights mismatch. Expected {expected_value}, got {actual_value}"


def _normalize_container_insights_value(value):
    if isinstance(value, bool):
        return "enabled" if value else "disabled"

    value_string = str(value).lower()

    if value_string in ["true", "enabled"]:
        return "enabled"

    if value_string in ["false", "disabled"]:
        return "disabled"

    raise AssertionError(
        f"Invalid expected container_insights value: {value}. "
        "Use true/false or enabled/disabled."
    )


def _check_cluster_capacity_state(cluster):
    registered_container_instances = cluster.get(
        "registeredContainerInstancesCount",
        0,
    )

    running_tasks = cluster.get("runningTasksCount", 0)
    pending_tasks = cluster.get("pendingTasksCount", 0)
    active_services = cluster.get("activeServicesCount", 0)

    assert (
        registered_container_instances >= 0
    ), "registeredContainerInstancesCount should not be negative"

    assert running_tasks >= 0, "runningTasksCount should not be negative"
    assert pending_tasks >= 0, "pendingTasksCount should not be negative"
    assert active_services >= 0, "activeServicesCount should not be negative"

    print(f"ℹ️ Running tasks: {running_tasks}")
    print(f"ℹ️ Pending tasks: {pending_tasks}")
    print(f"ℹ️ Active services: {active_services}")


def _get_optional_output(outputs, key, default=None):
    if key not in outputs:
        return default

    return outputs[key].get("value", default)
