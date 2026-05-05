import json
import time
import urllib.request
import urllib.error

import boto3


def run(outputs_raw):
    outputs = json.loads(outputs_raw)

    region = outputs["aws_region"]["value"]
    ecs = boto3.client("ecs", region_name=region)
    elbv2 = boto3.client("elbv2", region_name=region)
    ec2 = boto3.client("ec2", region_name=region)
    iam = boto3.client("iam", region_name=region)

    cluster_name = outputs["cluster_name"]["value"]
    cluster_arn = outputs["cluster_arn"]["value"]
    service_name = outputs["ecs_service_name"]["value"]
    service_arn = outputs["ecs_service_arn"]["value"]
    task_definition_arn = outputs["task_definition_arn"]["value"]
    target_group_arn = outputs["target_group_arn"]["value"]
    alb_dns_name = outputs["alb_dns_name"]["value"]
    private_subnet_ids = set(outputs["private_subnet_ids"]["value"])
    ecs_sg_id = outputs["ecs_security_group_id"]["value"]
    execution_role_arn = outputs["ecs_execution_role_arn"]["value"]
    task_role_arn = outputs["ecs_task_role_arn"]["value"]
    container_port = int(outputs.get("container_port", {}).get("value", 8000))
    health_check_path = outputs.get("health_check_path", {}).get("value", "/health")
    ecr_image_uri = outputs["ecr_image_uri"]["value"]

    print("Checking API compute slice")
    print(f"Cluster: {cluster_name}")
    print(f"Service: {service_name}")
    print(f"ALB DNS: {alb_dns_name}")
    print(f"Target group: {target_group_arn}")

    _check_alb_and_target_group(elbv2, target_group_arn)
    print("✅ ALB target group exists")

    cluster = _get_cluster(ecs, cluster_name)
    assert cluster["clusterArn"] == cluster_arn, "Cluster ARN output does not match ECS"
    assert cluster["status"] == "ACTIVE", f"Cluster is not ACTIVE: {cluster['status']}"
    print("✅ ECS cluster exists")

    service = _wait_for_service_stable(ecs, cluster_name, service_name)
    assert service["serviceArn"] == service_arn, "Service ARN output does not match ECS"
    assert (
        service["runningCount"] == service["desiredCount"]
    ), f"Service not stable: {service['runningCount']}/{service['desiredCount']}"
    print("✅ ECS service is stable")

    _check_service_attached_to_target_group(service, target_group_arn, container_port)
    print("✅ ECS service is attached to ALB target group")

    task_definition = ecs.describe_task_definition(taskDefinition=task_definition_arn)[
        "taskDefinition"
    ]

    _check_task_definition_roles(task_definition, execution_role_arn, task_role_arn)
    print("✅ IAM execution role and task role are attached to task definition")

    _check_task_definition_image(task_definition, ecr_image_uri, container_port)
    print("✅ Task definition uses expected ECR image and container port")

    _check_iam_role_exists(iam, execution_role_arn)
    _check_iam_role_exists(iam, task_role_arn)
    print("✅ IAM roles exist")

    task_arns = _wait_for_running_tasks(ecs, cluster_name, service_name)
    print(f"✅ Running ECS tasks found: {len(task_arns)}")

    tasks = ecs.describe_tasks(cluster=cluster_name, tasks=task_arns)["tasks"]
    _check_tasks_in_private_subnets(ec2, tasks, private_subnet_ids, ecs_sg_id)
    print("✅ ECS tasks are running in private subnets with expected security group")

    _check_target_health(elbv2, target_group_arn)
    print("✅ ALB target group has healthy ECS targets")

    _check_health_endpoint(alb_dns_name, health_check_path)
    print("✅ ALB health endpoint responds successfully")

    print("✅ API compute test passed")


def _get_cluster(ecs, cluster_name):
    response = ecs.describe_clusters(clusters=[cluster_name], include=["SETTINGS"])
    failures = response.get("failures", [])
    assert not failures, f"ECS describe_clusters failures: {failures}"

    clusters = response.get("clusters", [])
    assert len(clusters) == 1, f"Cluster not found: {cluster_name}"
    return clusters[0]


def _check_alb_and_target_group(elbv2, target_group_arn):
    response = elbv2.describe_target_groups(TargetGroupArns=[target_group_arn])
    groups = response.get("TargetGroups", [])
    assert len(groups) == 1, f"Target group not found: {target_group_arn}"

    group = groups[0]
    assert (
        group["TargetType"] == "ip"
    ), f"Fargate target group should use target_type=ip, got {group['TargetType']}"
    assert group["Protocol"] in [
        "HTTP",
        "HTTPS",
    ], f"Unexpected target group protocol: {group['Protocol']}"


def _wait_for_service_stable(ecs, cluster_name, service_name, timeout_seconds=420):
    deadline = time.time() + timeout_seconds
    last_status = None

    while time.time() < deadline:
        response = ecs.describe_services(cluster=cluster_name, services=[service_name])
        failures = response.get("failures", [])
        assert not failures, f"ECS describe_services failures: {failures}"

        services = response.get("services", [])
        assert len(services) == 1, f"Service not found: {service_name}"
        service = services[0]

        deployments = service.get("deployments", [])
        running = service.get("runningCount", 0)
        desired = service.get("desiredCount", 0)
        status = service.get("status")
        rollout_states = [d.get("rolloutState") for d in deployments]

        last_status = {
            "status": status,
            "running": running,
            "desired": desired,
            "deployments": len(deployments),
            "rollout_states": rollout_states,
        }

        if (
            status == "ACTIVE"
            and desired > 0
            and running == desired
            and len(deployments) == 1
            and deployments[0].get("rolloutState") in [None, "COMPLETED"]
        ):
            return service

        if any(state == "FAILED" for state in rollout_states):
            raise AssertionError(
                f"ECS deployment rollout FAILED — aborting wait. Status: {last_status}"
            )

        print(f"Waiting for ECS service stability: {last_status}")
        time.sleep(15)

    raise AssertionError(f"ECS service did not stabilize: {last_status}")


def _check_service_attached_to_target_group(service, target_group_arn, container_port):
    load_balancers = service.get("loadBalancers", [])
    assert load_balancers, "ECS service has no load balancer attachment"

    matches = [
        lb
        for lb in load_balancers
        if lb.get("targetGroupArn") == target_group_arn
        and int(lb.get("containerPort")) == container_port
    ]

    assert matches, (
        "ECS service is not attached to the expected target group/container port. "
        f"Expected {target_group_arn}:{container_port}, got {load_balancers}"
    )


def _check_task_definition_roles(task_definition, execution_role_arn, task_role_arn):
    assert task_definition.get("executionRoleArn") == execution_role_arn, (
        "Task definition execution role mismatch. "
        f"Expected {execution_role_arn}, got {task_definition.get('executionRoleArn')}"
    )

    assert task_definition.get("taskRoleArn") == task_role_arn, (
        "Task definition task role mismatch. "
        f"Expected {task_role_arn}, got {task_definition.get('taskRoleArn')}"
    )


def _check_task_definition_image(task_definition, expected_image, expected_port):
    container_definitions = task_definition.get("containerDefinitions", [])
    assert container_definitions, "Task definition has no container definitions"

    container = container_definitions[0]
    actual_image = container.get("image")
    assert (
        actual_image == expected_image
    ), f"Container image mismatch. Expected {expected_image}, got {actual_image}"

    port_mappings = container.get("portMappings", [])
    assert any(
        int(pm.get("containerPort")) == expected_port for pm in port_mappings
    ), f"Container port {expected_port} not found in task definition port mappings"

    # This helps prove execution-role secret/config injection wiring exists.
    secrets = container.get("secrets", [])
    assert secrets, "Container definition has no ECS secrets configured"


def _check_iam_role_exists(iam, role_arn):
    role_name = role_arn.split("/")[-1]
    response = iam.get_role(RoleName=role_name)
    assert (
        response["Role"]["Arn"] == role_arn
    ), f"IAM role ARN mismatch. Expected {role_arn}, got {response['Role']['Arn']}"


def _wait_for_running_tasks(ecs, cluster_name, service_name, timeout_seconds=180):
    deadline = time.time() + timeout_seconds

    while time.time() < deadline:
        response = ecs.list_tasks(
            cluster=cluster_name,
            serviceName=service_name,
            desiredStatus="RUNNING",
        )
        task_arns = response.get("taskArns", [])
        if task_arns:
            return task_arns

        print("Waiting for running ECS tasks")
        time.sleep(10)

    raise AssertionError("No running ECS tasks found")


def _check_tasks_in_private_subnets(ec2, tasks, private_subnet_ids, expected_sg_id):
    eni_ids = []

    for task in tasks:
        attachments = task.get("attachments", [])
        for attachment in attachments:
            if attachment.get("type") != "ElasticNetworkInterface":
                continue

            details = {d["name"]: d["value"] for d in attachment.get("details", [])}
            eni_id = details.get("networkInterfaceId")
            if eni_id:
                eni_ids.append(eni_id)

    assert eni_ids, "No task ENIs found"

    response = ec2.describe_network_interfaces(NetworkInterfaceIds=eni_ids)
    interfaces = response.get("NetworkInterfaces", [])

    for interface in interfaces:
        subnet_id = interface["SubnetId"]
        assert (
            subnet_id in private_subnet_ids
        ), f"Task ENI {interface['NetworkInterfaceId']} is not in a private subnet: {subnet_id}"

        association = interface.get("Association", {})
        assert (
            "PublicIp" not in association
        ), f"Task ENI {interface['NetworkInterfaceId']} has a public IP"

        group_ids = {group["GroupId"] for group in interface.get("Groups", [])}
        assert (
            expected_sg_id in group_ids
        ), f"Task ENI {interface['NetworkInterfaceId']} missing expected ECS SG {expected_sg_id}"


def _check_target_health(elbv2, target_group_arn, timeout_seconds=240):
    deadline = time.time() + timeout_seconds
    last_health = None

    while time.time() < deadline:
        response = elbv2.describe_target_health(TargetGroupArn=target_group_arn)
        descriptions = response.get("TargetHealthDescriptions", [])
        last_health = descriptions

        healthy = [
            d
            for d in descriptions
            if d.get("TargetHealth", {}).get("State") == "healthy"
        ]

        if healthy:
            return

        states = [d.get("TargetHealth", {}).get("State") for d in descriptions]
        print(f"Waiting for healthy ALB targets. Current states: {states}")
        time.sleep(10)

    raise AssertionError(f"No healthy targets found. Last health: {last_health}")


def _check_health_endpoint(alb_dns_name, health_check_path):
    url = f"http://{alb_dns_name}{health_check_path}"

    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            status = response.status
            assert 200 <= status < 400, f"Unexpected health endpoint status: {status}"
    except urllib.error.HTTPError as exc:
        raise AssertionError(
            f"Health endpoint returned HTTP {exc.code}: {url}"
        ) from exc
    except Exception as exc:
        raise AssertionError(f"Health endpoint check failed for {url}") from exc
