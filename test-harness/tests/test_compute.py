import boto3
import time
import json


def run(outputs_raw):
    outputs = json.loads(outputs_raw)

    ecs = boto3.client("ecs")

    cluster = outputs["cluster_name"]["value"]

    print(f"Checking ECS cluster: {cluster}")

    # wait for service stabilization
    time.sleep(15)

    services = ecs.list_services(cluster=cluster)["serviceArns"]

    assert len(services) > 0, "No ECS services found"

    service_arn = services[0]

    service = ecs.describe_services(cluster=cluster, services=[service_arn])[
        "services"
    ][0]

    running = service["runningCount"]
    desired = service["desiredCount"]

    assert running == desired, f"Service not stable: {running}/{desired}"

    print("✅ ECS service stable")

    # check tasks
    tasks = ecs.list_tasks(cluster=cluster)["taskArns"]
    assert len(tasks) > 0, "No running tasks"

    print("✅ ECS task running")
